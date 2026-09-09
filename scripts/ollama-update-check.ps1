# Read-only. Phase 0 / Phase 2 snapshot-and-diff for the Ollama update-
# execution runbook (records\runbooks\ollama.md). Captures ollama --version,
# the full `ollama list` output (diffed by name AND size, not count),
# `ollama ps`, a known-good query against the caddy model, and open-webui's
# dependent round-trip to Ollama over host.docker.internal. No model install,
# no rollback, no mutating command — this script only reads and writes its
# own JSON record under records\runs\. Mirrors node-update-check.ps1's
# -Phase/-RunId shape (PLAN-update-execution-v1.md Section 9, step 3).
#
# No data backup logic here — per PLAN-update-execution-v1.md §4c, an Ollama
# update is a binary swap and the models directory is untouched; the full
# model list is captured so the Phase 2 diff is meaningful, not as a backup.
#
# Openclaw is deliberately NOT probed here. CLAUDE.md's hard boundary for
# this project reads OpenClaw's version only and never edits its config;
# confirming its live Ollama connectivity would mean reading its provider
# config beyond that, so only open-webui's dependent round-trip is checked.
#
# One -RunId ties a Phase 0 capture to its Phase 2 verify: run -Phase
# capture first, then — whatever happened in between (nothing, for a dry
# run; a real install, for a real one) — run -Phase verify with the same
# -RunId.
#
# Pass/fail definition:
#   - If a -TargetVersion was given at capture time (or is given again at
#     verify time), Phase 2 passes when: `ollama --version` equals the
#     target; the model list has nothing missing and nothing changed size
#     against Phase 0 (new entries are not treated as a failure — pulling a
#     model is a normal, unrelated action); the known-good query against the
#     caddy model succeeded; and open-webui's round-trip to Ollama succeeded.
#   - If no target was ever given, Phase 2 passes when nothing drifted from
#     the Phase 0 capture at all (version, models, dependent status all
#     unchanged) — the dry-run / no-op check, which proves the
#     capture-and-diff mechanism works without any update having happened.
#
# Posting to #decisions is gated behind -PostToDiscord (a switch, default
# off) so a dry run never sends live Discord traffic. post-discord.ps1 is
# inherited and not modified here; a failed post never fails this script —
# disk stays the source of truth even if Discord is unreachable, same
# principle already in force for run-check.ps1's own alert calls.
param(
  [Parameter(Mandatory)][ValidateSet('capture', 'verify')][string]$Phase,
  [Parameter(Mandatory)][string]$RunId,
  [string]$TargetVersion,
  [string]$CaddyModel = 'qwen3.5-caddy',
  [string]$OllamaChatUrl = 'http://127.0.0.1:11434/api/chat',
  [string]$OllamaVersionUrl = 'http://127.0.0.1:11434/api/version',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$ScriptsDir = 'C:\automation\infra-watch\scripts',
  [switch]$PostToDiscord
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Get-OllamaModelList {
  $raw = (ollama list 2>&1 | Out-String)
  $lines = $raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
  $models = @()
  foreach ($line in $lines) {
    if ($line -match '^NAME\s+ID\s+SIZE') { continue }
    if ($line -match '^(?<name>\S+)\s+(?<id>\S+)\s+(?<sizeval>[\d.]+)\s+(?<sizeunit>\S+)\s+(?<modified>.+)$') {
      $models += [PSCustomObject]@{
        name       = $Matches.name
        id         = $Matches.id
        size_value = [double]$Matches.sizeval
        size_unit  = $Matches.sizeunit
        modified   = $Matches.modified.Trim()
      }
    }
  }
  [PSCustomObject]@{ raw = $raw.Trim(); models = $models }
}

function Get-KnownGoodQuery {
  param([string]$Model, [string]$ChatUrl)
  $question = 'Reply with the single word: OK.'
  $body = @{
    model      = $Model
    think      = $false
    stream     = $false
    keep_alive = -1
    messages   = @(
      @{ role = 'system'; content = 'You are a smoke-test assistant for infra-watch. Answer in one short sentence.' },
      @{ role = 'user'; content = $question }
    )
  } | ConvertTo-Json -Depth 6

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-RestMethod -Uri $ChatUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 120
    $sw.Stop()
    [PSCustomObject]@{
      ok         = $true
      model      = $Model
      question   = $question
      answer     = $resp.message.content
      latency_ms = $sw.ElapsedMilliseconds
      error      = $null
    }
  }
  catch {
    $sw.Stop()
    [PSCustomObject]@{
      ok         = $false
      model      = $Model
      question   = $question
      answer     = $null
      latency_ms = $sw.ElapsedMilliseconds
      error      = $_.Exception.Message
    }
  }
}

function Get-DependentCheck {
  $openWebui = [PSCustomObject]@{ checked = $false; http_code = $null; body = $null; ok = $false; error = $null }
  try {
    $code = (docker exec open-webui curl -s -o /dev/null -w "%{http_code}" http://host.docker.internal:11434/api/version 2>&1 | Out-String).Trim()
    $body = (docker exec open-webui curl -s http://host.docker.internal:11434/api/version 2>&1 | Out-String).Trim()
    $openWebui.checked   = $true
    $openWebui.http_code = $code
    $openWebui.body      = $body
    $openWebui.ok        = ($code -eq '200')
  }
  catch {
    $openWebui.checked = $true
    $openWebui.error   = $_.Exception.Message
  }

  [PSCustomObject]@{
    open_webui = $openWebui
    openclaw   = [PSCustomObject]@{
      checked = $false
      note    = 'Not probed. CLAUDE.md hard boundary: this project reads OpenClaw version only and never edits or actively touches its config; confirming live Ollama connectivity would require reading its provider config beyond that.'
    }
  }
}

function Get-OllamaSnapshot {
  param([string]$CaddyModel, [string]$ChatUrl, [string]$VersionUrl)

  $versionRaw = (ollama --version 2>&1 | Out-String).Trim()
  $psRaw      = (ollama ps 2>&1 | Out-String).Trim()
  $modelList  = Get-OllamaModelList
  $query      = Get-KnownGoodQuery -Model $CaddyModel -ChatUrl $ChatUrl
  $dependents = Get-DependentCheck

  [PSCustomObject]@{
    ollama_version   = $versionRaw
    ollama_ps        = $psRaw
    models           = $modelList
    known_good_query = $query
    dependents       = $dependents
  }
}

function Compare-ModelLists {
  param([array]$Before, [array]$After)
  $beforeMap = @{}
  foreach ($m in $Before) { $beforeMap[$m.name] = $m }
  $afterMap = @{}
  foreach ($m in $After) { $afterMap[$m.name] = $m }

  $missing = @($Before | Where-Object { -not $afterMap.ContainsKey($_.name) } | ForEach-Object { $_.name })
  $added   = @($After  | Where-Object { -not $beforeMap.ContainsKey($_.name) } | ForEach-Object { $_.name })
  $changedSize = @()
  foreach ($name in $beforeMap.Keys) {
    if ($afterMap.ContainsKey($name)) {
      $b = $beforeMap[$name]; $a = $afterMap[$name]
      if ($b.size_value -ne $a.size_value -or $b.size_unit -ne $a.size_unit) {
        $changedSize += [PSCustomObject]@{ name = $name; before_size = "$($b.size_value) $($b.size_unit)"; after_size = "$($a.size_value) $($a.size_unit)" }
      }
    }
  }
  [PSCustomObject]@{
    missing      = $missing
    added        = $added
    changed_size = $changedSize
  }
}

if ($Phase -eq 'capture') {
  $snapshot = Get-OllamaSnapshot -CaddyModel $CaddyModel -ChatUrl $OllamaChatUrl -VersionUrl $OllamaVersionUrl
  $record = [PSCustomObject]@{
    run_id         = $RunId
    phase          = 'capture'
    timestamp      = (Get-Date).ToString('o')
    target_version = $TargetVersion
    caddy_model    = $CaddyModel
    snapshot       = $snapshot
  }
  $outPath = Join-Path $runDir 'ollama-update-phase0.json'
  $json = $record | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
  Write-Output $json
  Write-Output "Written to $outPath"
  exit 0
}

# $Phase -eq 'verify'
$phase0Path = Join-Path $runDir 'ollama-update-phase0.json'
if (-not (Test-Path $phase0Path)) {
  throw "Phase 0 capture missing for run '$RunId': $phase0Path (run -Phase capture first with the same -RunId)"
}
$phase0 = Get-Content $phase0Path -Encoding utf8 -Raw | ConvertFrom-Json

$caddyModel = if ($CaddyModel) { $CaddyModel } elseif ($phase0.caddy_model) { $phase0.caddy_model } else { 'qwen3.5-caddy' }
$current = Get-OllamaSnapshot -CaddyModel $caddyModel -ChatUrl $OllamaChatUrl -VersionUrl $OllamaVersionUrl

$target = if ($TargetVersion) { $TargetVersion } elseif ($phase0.target_version) { $phase0.target_version } else { $null }
$mode = if ($target) { 'target-check' } else { 'no-op-check' }

$modelDiff = Compare-ModelLists -Before $phase0.snapshot.models.models -After $current.models.models

$versionChanged   = ($phase0.snapshot.ollama_version -ne $current.ollama_version)
$dependentsBefore = $phase0.snapshot.dependents.open_webui.ok
$dependentsAfter  = $current.dependents.open_webui.ok
$queryBefore      = $phase0.snapshot.known_good_query.ok
$queryAfter       = $current.known_good_query.ok

$diff = [PSCustomObject]@{
  ollama_version = [PSCustomObject]@{ before = $phase0.snapshot.ollama_version; after = $current.ollama_version; changed = $versionChanged }
  models         = $modelDiff
  known_good_query = [PSCustomObject]@{ before_ok = $queryBefore; after_ok = $queryAfter; changed = ($queryBefore -ne $queryAfter) }
  open_webui_dependent = [PSCustomObject]@{ before_ok = $dependentsBefore; after_ok = $dependentsAfter; changed = ($dependentsBefore -ne $dependentsAfter) }
}

$pass = if ($mode -eq 'target-check') {
  ($current.ollama_version -match [regex]::Escape($target)) -and
  ($modelDiff.missing.Count -eq 0) -and
  ($modelDiff.changed_size.Count -eq 0) -and
  $queryAfter -and
  $dependentsAfter
}
else {
  (-not $versionChanged) -and
  ($modelDiff.missing.Count -eq 0) -and
  ($modelDiff.added.Count -eq 0) -and
  ($modelDiff.changed_size.Count -eq 0) -and
  (-not $diff.known_good_query.changed) -and
  (-not $diff.open_webui_dependent.changed)
}

$result = [PSCustomObject]@{
  run_id         = $RunId
  phase          = 'verify'
  timestamp      = (Get-Date).ToString('o')
  mode           = $mode
  target_version = $target
  current        = $current
  diff           = $diff
  pass           = [bool]$pass
}

$outPath = Join-Path $runDir 'ollama-update-phase2.json'
$json = $result | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
Write-Output $json
Write-Output "Written to $outPath"

$statusWord = if ($pass) { 'PASS' } else { 'FAIL' }
$targetNote = if ($target) { " (target $target)" } else { '' }
$summaryLine = "Ollama update verify [$mode]: $statusWord. ollama $($diff.ollama_version.before) -> $($diff.ollama_version.after)$targetNote. models missing=$($modelDiff.missing.Count) added=$($modelDiff.added.Count) changed_size=$($modelDiff.changed_size.Count). known-good query after=$queryAfter. open-webui dependent after=$dependentsAfter."
Write-Output $summaryLine

if ($PostToDiscord) {
  $postScript = Join-Path $ScriptsDir 'post-discord.ps1'
  $postArgs = @('-Channel', 'decisions', '-Message', $summaryLine, '-Title', "Ollama update verify: $statusWord")
  $postOutput = & pwsh -NoProfile -File $postScript @postArgs 2>&1 | Out-String
  Write-Output $postOutput.Trim()
}
else {
  Write-Output 'PostToDiscord not set — no live post sent (dry run, or -PostToDiscord intentionally omitted).'
}

if (-not $pass) { exit 1 }
exit 0
