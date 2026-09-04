# Known limit: the cap check below runs before a call and does not estimate
# what that call will cost. A cap is a gate on starting new work, not a
# ceiling on spend — at $0.19 against a $0.20 per-day cap, a $2 call
# proceeds. Output is bounded by per_call_max_tokens; input is not bounded
# at all, and Phase B sends large rules-doc bundles. Designed behaviour,
# not a defect.
param(
  [Parameter(Mandatory)][ValidateSet('openrouter','ollama')][string]$Provider,
  [Parameter(Mandatory)][string]$Model,
  [Parameter(Mandatory)][string]$Step,
  [Parameter(Mandatory)][string]$RunId,
  [string]$SystemFile,
  [string]$SystemText,
  [string]$UserFile,
  [string]$UserText,
  [Parameter(Mandatory)][int]$MaxTokens,
  [double]$Temperature = 0,
  [string]$ReasoningEffort
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom   = New-Object System.Text.UTF8Encoding($false)
$secretsFile = 'C:\automation\secrets\infra-watch.env'
$capsFile    = 'C:\automation\infra-watch\config\model-caps.json'
$runsDir     = 'C:\automation\infra-watch\records\runs'
$logFile     = Join-Path $runsDir 'model-calls.jsonl'
$tmpDir      = Join-Path $env:TEMP 'infra-watch-invoke-model'

# If a previous call was killed mid-request, its temp auth file (holding the
# OpenRouter key) can survive in TEMP. Sweep it at the start of every run,
# before this run writes its own.
if (Test-Path $tmpDir) { Remove-Item (Join-Path $tmpDir '*') -Force -ErrorAction SilentlyContinue }

function Get-EnvValue {
  param([string]$Path, [string]$Name)
  foreach ($line in Get-Content $Path -Encoding utf8) {
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    if ($line.Substring(0, $idx) -ceq $Name) { return $line.Substring($idx + 1) }
  }
  throw "Name '$Name' not found in $Path"
}

if (-not $SystemFile -and -not $SystemText) { throw 'Supply -SystemFile or -SystemText' }
if (-not $UserFile -and -not $UserText)     { throw 'Supply -UserFile or -UserText' }

$systemContent = if ($SystemFile) { [System.IO.File]::ReadAllText($SystemFile, [Text.Encoding]::UTF8) } else { $SystemText }
$userContent   = if ($UserFile)   { [System.IO.File]::ReadAllText($UserFile, [Text.Encoding]::UTF8) }   else { $UserText }

if (-not (Test-Path $capsFile)) { throw "Caps file missing: $capsFile" }
$caps = Get-Content $capsFile -Encoding utf8 -Raw | ConvertFrom-Json

if ($MaxTokens -gt $caps.per_call_max_tokens) {
  throw "MaxTokens $MaxTokens exceeds per-call cap $($caps.per_call_max_tokens) in $capsFile"
}

New-Item -ItemType Directory -Force -Path $runsDir | Out-Null

$today = Get-Date -Format 'yyyy-MM-dd'
$daySpend = 0.0
$runSpend = 0.0
if (Test-Path $logFile) {
  foreach ($line in Get-Content $logFile -Encoding utf8) {
    if (-not $line.Trim()) { continue }
    $entry = $line | ConvertFrom-Json
    if (([datetime]$entry.Timestamp).ToString('yyyy-MM-dd') -eq $today) { $daySpend += [double]$entry.Cost }
    if ($entry.RunId -ceq $RunId) { $runSpend += [double]$entry.Cost }
  }
}

# Return contract: every non-exception path returns an object with a Status
# property ('ok' or 'capped'); genuine errors still throw. This script is
# meant to be dot-sourced or invoked with & in-process, so `return` hands the
# object back to the caller without ending the caller's own session. If this
# script is ever invoked as a separate process instead, that assumption
# breaks and exit codes would need to be reintroduced for the capped paths.
if ($daySpend -ge $caps.per_day_dollar_cap) {
  return [PSCustomObject]@{
    Status = 'capped'
    Reason = "STOP: day spend `$$daySpend already at or over per-day cap `$$($caps.per_day_dollar_cap). No call made."
  }
}
if ($runSpend -ge $caps.per_run_dollar_cap) {
  return [PSCustomObject]@{
    Status = 'capped'
    Reason = "STOP: run spend `$$runSpend already at or over per-run cap `$$($caps.per_run_dollar_cap). No call made."
  }
}

New-Item -ItemType Directory -Force -Path (Join-Path $runsDir $RunId) | Out-Null

function Write-CallLog {
  param([string]$Model, [int]$TokensIn, [int]$TokensOut, [double]$Cost)
  $entry = [PSCustomObject]@{
    Timestamp   = (Get-Date).ToString('o')
    RunId       = $RunId
    Step        = $Step
    Model       = $Model
    TokensIn    = $TokensIn
    TokensOut   = $TokensOut
    Cost        = $Cost
    CheckPassed = $null
  }
  $line = ($entry | ConvertTo-Json -Compress -Depth 4)
  [System.IO.File]::AppendAllText($logFile, $line + "`n", $utf8NoBom)
  return $entry
}

$rawPath = Join-Path (Join-Path $runsDir $RunId) "$Step-raw.json"

if ($Provider -eq 'ollama') {
  $body = @{
    model      = $Model
    think      = $false
    stream     = $false
    keep_alive = -1
    options    = @{ temperature = $Temperature }
    messages   = @(
      @{ role = 'system'; content = $systemContent }
      @{ role = 'user';   content = $userContent }
    )
  } | ConvertTo-Json -Depth 6 -Compress

  $tmpBody = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllText($tmpBody, $body, $utf8NoBom)

  # curl writes the response body straight to $rawPath as raw bytes (-o) so
  # it never passes through PowerShell's native-command stdout capture, which
  # decodes through [Console]::OutputEncoding - not guaranteed to be UTF-8 for
  # every process launch on this machine, and confirmed (records\phaseC-
  # session3-log.md) to have corrupted every em-dash in a live run despite
  # this same session showing UTF-8. Only the 3-digit HTTP code crosses
  # stdout, which is plain ASCII and safe under any code page.
  $httpCode = curl.exe -s -o $rawPath -w "%{http_code}" http://127.0.0.1:11434/api/chat -d "@$tmpBody"
  $curlExit = $LASTEXITCODE
  Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue

  if ($curlExit -ne 0) { throw "curl.exe failed reaching Ollama, exit code $curlExit" }

  if ($httpCode -notmatch '^2\d\d$') {
    throw "Ollama returned HTTP $httpCode. Raw response saved at $rawPath."
  }

  $bodyText = [System.IO.File]::ReadAllText($rawPath, [Text.Encoding]::UTF8)
  $parsed = $bodyText | ConvertFrom-Json
  $logEntry = Write-CallLog -Model $Model -TokensIn $parsed.prompt_eval_count -TokensOut $parsed.eval_count -Cost 0.0

  return [PSCustomObject]@{
    Status  = 'ok'
    Content = $parsed.message.content
    Log     = $logEntry
    RawPath = $rawPath
  }
}

# provider = openrouter
$key = Get-EnvValue -Path $secretsFile -Name 'OPENROUTER_API_KEY'

$bodyObj = @{
  model       = $Model
  max_tokens  = $MaxTokens
  temperature = $Temperature
  stream      = $false
  messages    = @(
    @{ role = 'system'; content = $systemContent }
    @{ role = 'user';   content = $userContent }
  )
}
# Opt-in only: a caller that doesn't pass -ReasoningEffort gets exactly the
# body this script has always sent, no `reasoning` key at all. reconcile-
# draft.ps1 relies on that — it must never send this parameter.
if ($ReasoningEffort) { $bodyObj.reasoning = @{ effort = $ReasoningEffort } }
$body = $bodyObj | ConvertTo-Json -Depth 6 -Compress

New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$tmpBody   = Join-Path $tmpDir "body-$([guid]::NewGuid()).json"
$tmpHeader = Join-Path $tmpDir "auth-$([guid]::NewGuid()).txt"
[System.IO.File]::WriteAllText($tmpBody, $body, $utf8NoBom)
[System.IO.File]::WriteAllText($tmpHeader, "header = `"Authorization: Bearer $key`"`n", $utf8NoBom)
$key = $null

$maxAttempts = 3
$attempt = 0
$httpCode = $null
$curlExit = 1
try {
  while ($attempt -lt $maxAttempts) {
    $attempt++
    # -o writes the response body straight to $rawPath as raw bytes, bypassing
    # PowerShell's native-command stdout capture (see the Ollama branch above
    # for why that capture is unsafe). Only the ASCII HTTP code crosses stdout.
    $httpCode = curl.exe -s -o $rawPath -w "%{http_code}" -X POST https://openrouter.ai/api/v1/chat/completions `
      -H 'Content-Type: application/json' -K $tmpHeader -d "@$tmpBody"
    $curlExit = $LASTEXITCODE
    if ($curlExit -eq 0) {
      if ($httpCode -match '^5\d\d$') {
        if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds ([math]::Pow(2, $attempt)); continue }
      }
      break
    }
    if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds ([math]::Pow(2, $attempt)) }
  }
} finally {
  Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
  Remove-Item $tmpHeader -Force -ErrorAction SilentlyContinue
}

if ($curlExit -ne 0) { throw "curl.exe failed reaching OpenRouter after $attempt attempt(s), exit code $curlExit" }

if ($httpCode -notmatch '^2\d\d$') {
  throw "OpenRouter returned HTTP $httpCode (never retried — 4xx is an answer, not a failure). Raw response saved at $rawPath."
}

$bodyText = [System.IO.File]::ReadAllText($rawPath, [Text.Encoding]::UTF8)
$parsed = $bodyText | ConvertFrom-Json

# usage.cost reads 0 on some error-terminated responses (e.g. finish_reason
# "error") even though the call was actually charged. usage.cost_details.
# upstream_inference_cost carries the real charge in the same response, so
# prefer it whenever present and non-zero. Confirmed against two real
# OpenRouter responses on 2026-08-21: one where both fields agreed, one
# where usage.cost read 0 and upstream_inference_cost read $0.1877.
$cost = $parsed.usage.cost
$upstreamCost = $parsed.usage.cost_details.upstream_inference_cost
if ($upstreamCost -and [double]$upstreamCost -ne 0) { $cost = [double]$upstreamCost }

$logEntry = Write-CallLog -Model $parsed.model -TokensIn $parsed.usage.prompt_tokens -TokensOut $parsed.usage.completion_tokens -Cost $cost

return [PSCustomObject]@{
  Status  = 'ok'
  Content = $parsed.choices[0].message.content
  Log     = $logEntry
  RawPath = $rawPath
}
