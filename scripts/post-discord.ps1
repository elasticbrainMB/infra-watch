param(
  [Parameter(Mandatory)][ValidateSet('runs','decisions')][string]$Channel,
  [Parameter(Mandatory)][string]$Message,
  [string]$Title
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom        = New-Object System.Text.UTF8Encoding($false)
$secretsFile      = 'C:\automation\secrets\infra-watch.env'
$maxContentLength = 2000

function Get-EnvValue {
  param([string]$Path, [string]$Name)
  foreach ($line in Get-Content $Path -Encoding utf8) {
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    if ($line.Substring(0, $idx) -ceq $Name) { return $line.Substring($idx + 1) }
  }
  throw "Name '$Name' not found in $Path"
}

try {
  $envName = if ($Channel -eq 'runs') { 'DISCORD_WEBHOOK_RUNS' } else { 'DISCORD_WEBHOOK_DECISIONS' }
  $url = Get-EnvValue -Path $secretsFile -Name $envName

  $content = if ($Title) { "**[infra-watch] $Title**`n$Message" } else { "[infra-watch] $Message" }
  $truncated = $false
  if ($content.Length -gt $maxContentLength) {
    $marker = "`n...[truncated]"
    $content = $content.Substring(0, $maxContentLength - $marker.Length) + $marker
    $truncated = $true
  }

  $body = @{ content = $content } | ConvertTo-Json -Compress

  $tmpDir    = Join-Path $env:TEMP 'infra-watch-post-discord'
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $tmpBody   = Join-Path $tmpDir "body-$([guid]::NewGuid()).json"
  $tmpConfig = Join-Path $tmpDir "target-$([guid]::NewGuid()).txt"
  [System.IO.File]::WriteAllText($tmpBody, $body, $utf8NoBom)
  [System.IO.File]::WriteAllText($tmpConfig, "url = `"$url`"`n", $utf8NoBom)
  $url = $null

  try {
    $raw = curl.exe -s -w "`n%{http_code}" -X POST -H 'Content-Type: application/json' -K $tmpConfig -d "@$tmpBody"
    $curlExit = $LASTEXITCODE
  } finally {
    Remove-Item $tmpBody, $tmpConfig -Force -ErrorAction SilentlyContinue
  }

  if ($curlExit -ne 0) { throw "curl.exe failed reaching Discord, exit code $curlExit" }

  $rawLines = $raw -split "`n"
  $httpCode = $rawLines[-1]

  if ($httpCode -notmatch '^2\d\d$') {
    $bodyText = ($rawLines[0..($rawLines.Count - 2)] -join "`n")
    throw "Discord webhook returned HTTP ${httpCode}: $bodyText"
  }

  if ($truncated) { Write-Output "Posted to #$Channel (message truncated to $maxContentLength chars)." }
  else { Write-Output "Posted to #$Channel." }
  exit 0
}
catch {
  # A failed Discord post never fails the run that called it: report and exit non-zero, never throw upward.
  Write-Output "DISCORD POST FAILED (channel: $Channel): $($_.Exception.Message)"
  exit 1
}
