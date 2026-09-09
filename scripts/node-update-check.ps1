# Read-only. Phase 0 / Phase 2 snapshot-and-diff for the Node update-
# execution proof (PLAN-update-execution-v1.md Section 9, step 3). Captures
# node/npm versions, binary paths, and an optional build baseline; Phase 2
# re-captures the same facts and diffs against Phase 0. No model call, no
# install, no mutating command — this script only reads version strings and
# writes its own JSON record under records\runs\. (The one exception: if
# Matt explicitly supplies -BuildCommand, that command runs verbatim — this
# script never invents or runs one on its own.)
#
# One -RunId ties a Phase 0 capture to its Phase 2 verify: run -Phase
# capture first, then — whatever happened in between (nothing, for a dry
# run; a real install, for a real one) — run -Phase verify with the same
# -RunId.
#
# Pass/fail definition:
#   - If a -TargetVersion was given at capture time (or is given again at
#     verify time), Phase 2 passes when the current `node --version` equals
#     that target — the real post-update check.
#   - If no target was ever given, Phase 2 passes when nothing drifted from
#     the Phase 0 capture — the dry-run / no-op check, which proves the
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
  [string]$BuildCommand,
  [string]$BuildWorkingDir,
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$ScriptsDir = 'C:\automation\infra-watch\scripts',
  [switch]$PostToDiscord
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Get-NodeSnapshot {
  param([string]$BuildCommand, [string]$BuildWorkingDir)

  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  $npmCmd  = Get-Command npm -ErrorAction SilentlyContinue

  $nodeVersion = if ($nodeCmd) { (node --version 2>&1 | Out-String).Trim() } else { $null }
  $npmVersion  = if ($npmCmd)  { (npm --version 2>&1 | Out-String).Trim() } else { $null }

  $build = [PSCustomObject]@{
    configured = [bool]$BuildCommand
    command    = $BuildCommand
    exit_code  = $null
    ok         = $null
    note       = $null
  }
  if ($BuildCommand) {
    $priorLocation = Get-Location
    try {
      if ($BuildWorkingDir) { Set-Location $BuildWorkingDir }
      Invoke-Expression "$BuildCommand 2>&1" | Out-String | Out-Null
      $build.exit_code = $LASTEXITCODE
      $build.ok = ($LASTEXITCODE -eq 0)
    }
    finally {
      Set-Location $priorLocation
    }
  }
  else {
    $build.note = 'No dependent build command configured for this run — see records\runbooks\node.md Phase 0. Pass -BuildCommand to check one.'
  }

  [PSCustomObject]@{
    node_version = $nodeVersion
    npm_version  = $npmVersion
    node_path    = if ($nodeCmd) { $nodeCmd.Source } else { $null }
    npm_path     = if ($npmCmd) { $npmCmd.Source } else { $null }
    build        = $build
  }
}

if ($Phase -eq 'capture') {
  $snapshot = Get-NodeSnapshot -BuildCommand $BuildCommand -BuildWorkingDir $BuildWorkingDir
  $record = [PSCustomObject]@{
    run_id         = $RunId
    phase          = 'capture'
    timestamp      = (Get-Date).ToString('o')
    target_version = $TargetVersion
    snapshot       = $snapshot
  }
  $outPath = Join-Path $runDir 'node-update-phase0.json'
  $json = $record | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
  Write-Output $json
  Write-Output "Written to $outPath"
  exit 0
}

# $Phase -eq 'verify'
$phase0Path = Join-Path $runDir 'node-update-phase0.json'
if (-not (Test-Path $phase0Path)) {
  throw "Phase 0 capture missing for run '$RunId': $phase0Path (run -Phase capture first with the same -RunId)"
}
$phase0 = Get-Content $phase0Path -Encoding utf8 -Raw | ConvertFrom-Json

$current = Get-NodeSnapshot -BuildCommand $BuildCommand -BuildWorkingDir $BuildWorkingDir

$target = if ($TargetVersion) { $TargetVersion } elseif ($phase0.target_version) { $phase0.target_version } else { $null }
$mode = if ($target) { 'target-check' } else { 'no-op-check' }

$diff = [PSCustomObject]@{
  node_version = [PSCustomObject]@{ before = $phase0.snapshot.node_version; after = $current.node_version; changed = ($phase0.snapshot.node_version -ne $current.node_version) }
  npm_version  = [PSCustomObject]@{ before = $phase0.snapshot.npm_version; after = $current.npm_version; changed = ($phase0.snapshot.npm_version -ne $current.npm_version) }
  node_path    = [PSCustomObject]@{ before = $phase0.snapshot.node_path; after = $current.node_path; changed = ($phase0.snapshot.node_path -ne $current.node_path) }
  npm_path     = [PSCustomObject]@{ before = $phase0.snapshot.npm_path; after = $current.npm_path; changed = ($phase0.snapshot.npm_path -ne $current.npm_path) }
}

$pass = if ($mode -eq 'target-check') {
  ($current.node_version -eq $target)
}
else {
  -not ($diff.node_version.changed -or $diff.npm_version.changed -or $diff.node_path.changed -or $diff.npm_path.changed)
}

$result = [PSCustomObject]@{
  run_id         = $RunId
  phase          = 'verify'
  timestamp      = (Get-Date).ToString('o')
  mode           = $mode
  target_version = $target
  current        = $current
  diff           = $diff
  pass           = $pass
}

$outPath = Join-Path $runDir 'node-update-phase2.json'
$json = $result | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
Write-Output $json
Write-Output "Written to $outPath"

$statusWord = if ($pass) { 'PASS' } else { 'FAIL' }
$targetNote = if ($target) { " (target $target)" } else { '' }
$summaryLine = "Node update verify [$mode]: $statusWord. node $($diff.node_version.before) -> $($diff.node_version.after)$targetNote."
Write-Output $summaryLine

if ($PostToDiscord) {
  $postScript = Join-Path $ScriptsDir 'post-discord.ps1'
  $postArgs = @('-Channel', 'decisions', '-Message', $summaryLine, '-Title', "Node update verify: $statusWord")
  $postOutput = & pwsh -NoProfile -File $postScript @postArgs 2>&1 | Out-String
  Write-Output $postOutput.Trim()
}
else {
  Write-Output 'PostToDiscord not set — no live post sent (dry run, or -PostToDiscord intentionally omitted).'
}

if (-not $pass) { exit 1 }
exit 0
