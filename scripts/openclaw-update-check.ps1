# Read-only. Phase 0 / Phase 2 snapshot-and-diff for the OpenClaw 2.0 update-
# execution runbook (records\runbooks\openclaw.md is not written separately;
# PLAN-openclaw-2.0-update-v1.md IS the runbook per prompts\openclaw-update-
# apply.md). Captures container up/healthy state, a startup-log-tail check
# for the migration-completion / "manual repair" signal, Control UI
# reachability (HTTP-level only), and the installed version label. No
# container mutation, no docker pull/run/stop/rm — this script only reads
# and writes its own JSON record under records\runs\. Mirrors node-update-
# check.ps1 / ollama-update-check.ps1's -Phase/-RunId shape.
#
# Two deliberate deviations from the other two scripts, both boundary-driven:
#
#   1. "Known-good query to the local model" and "Discord round-trip" are
#      NOT scripted here. Ollama's script could hit Ollama's own /api/chat
#      directly; OpenClaw has no equivalent simple REST endpoint for this —
#      its Control UI talks a custom WebSocket protocol, and scripting a
#      real interaction would mean actually using the live assistant (a
#      real Discord message, a real session entry) rather than reading it.
#      Per PLAN-openclaw-2.0-update-v1.md Phase 0.2's own phrasing ("from a
#      normal session"), these two checks are recorded as a human
#      confirmation passed in via -KnownGoodQueryConfirmed /
#      -DiscordRoundTripConfirmed (plus a free-text note each), not
#      fabricated as an automated pass. Default is unconfirmed — this
#      script never assumes a human check happened.
#
#   2. Whether a plugin is installed is NOT queried here (that would read
#      OpenClaw's own app-level state, crossing CLAUDE.md's "OpenClaw
#      config — read version only, never edit" boundary — the same one
#      that kept the Ollama sitting from reading openclaw's provider
#      config). The Phase 0.2 baseline log tail already answers this
#      passively (the startup line lists loaded plugins), so this script's
#      log-tail capture covers it without a dedicated app-state query.
#
# One -RunId ties a Phase 0 capture to its Phase 2 verify: run -Phase
# capture first, then — whatever happened in between (nothing, for a dry
# run; a real container recreate + mandatory volume backup, for a real one)
# — run -Phase verify with the same -RunId.
#
# Pass/fail definition:
#   - If a -TargetVersion was given at capture time (or is given again at
#     verify time), Phase 2 passes when: the container is Up and healthy;
#     the installed version label equals the target; the startup log tail
#     does NOT contain "manual repair" (the one documented failure signal
#     per the runbook's Phase 2/3) and DOES show a clean "ready"/"listening"
#     startup; the Control UI's health endpoint and root both return HTTP
#     200; and both human-confirmed checks (known-good query, Discord
#     round-trip) are marked ok.
#   - If no target was given, Phase 2 passes when nothing drifted from the
#     Phase 0 capture at all — the dry-run / no-op check.
#
# Posting to #decisions is gated behind -PostToDiscord (default off) so a
# dry run never sends live Discord traffic. A failed post never fails this
# script — disk stays the source of truth even if Discord is unreachable.
param(
  [Parameter(Mandatory)][ValidateSet('capture', 'verify')][string]$Phase,
  [Parameter(Mandatory)][string]$RunId,
  [string]$TargetVersion,
  [string]$ContainerName = 'openclaw',
  [string]$HealthzUrl = 'http://127.0.0.1:18789/healthz',
  [string]$ControlUiUrl = 'http://127.0.0.1:18789/',
  [int]$LogTailLines = 200,
  [switch]$KnownGoodQueryConfirmed,
  [string]$KnownGoodQueryNote,
  [switch]$DiscordRoundTripConfirmed,
  [string]$DiscordRoundTripNote,
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$ScriptsDir = 'C:\automation\infra-watch\scripts',
  [switch]$PostToDiscord
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Get-HttpCheck {
  param([string]$Url)
  try {
    $resp = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 15 -UseBasicParsing
    [PSCustomObject]@{ url = $Url; ok = $true; http_code = [int]$resp.StatusCode; error = $null }
  }
  catch {
    $code = $null
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    [PSCustomObject]@{ url = $Url; ok = $false; http_code = $code; error = $_.Exception.Message }
  }
}

function Get-OpenclawSnapshot {
  param([string]$ContainerName, [string]$HealthzUrl, [string]$ControlUiUrl, [int]$LogTailLines)

  $psRaw = (docker ps --filter "name=$ContainerName" --format '{{.Status}}' 2>&1 | Out-String).Trim()
  $up = $psRaw -match '^Up '

  $healthRaw = (docker inspect --format '{{json .State.Health}}' $ContainerName 2>&1 | Out-String).Trim()
  $healthStatus = $null
  try { $healthStatus = ($healthRaw | ConvertFrom-Json).Status } catch { $healthStatus = $null }

  $versionLabel = (docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' $ContainerName 2>&1 | Out-String).Trim()
  $imageRef = (docker inspect --format '{{.Config.Image}}' $ContainerName 2>&1 | Out-String).Trim()

  # Scoped to the CURRENT start, not a fixed line count. A fixed --tail window
  # can still contain an earlier crash-loop's log lines (confirmed live
  # 2026-09-09: a "doctor --fix" failure from before a repair was still inside
  # the most recent 200 lines well after the repair succeeded) - exactly the
  # "reading something next to the fact instead of the fact" trap. StartedAt
  # scopes the log read to what THIS run actually printed.
  $startedAt = (docker inspect --format '{{.State.StartedAt}}' $ContainerName 2>&1 | Out-String).Trim()
  $logTail = if ($startedAt) { (docker logs --since $startedAt $ContainerName 2>&1 | Out-String) } else { (docker logs --tail $LogTailLines $ContainerName 2>&1 | Out-String) }
  # "manual repair" never appears verbatim in OpenClaw's own output - that's the
  # runbook's paraphrase. The real signal, confirmed live 2026-09-09 against a
  # genuine maintenance-required failure: "gateway.maintenance_required" and/or
  # "doctor --fix" in the log text. Matching both in case one changes independently.
  $manualRepairSignal = ($logTail -match '(?i)maintenance_required') -or ($logTail -match '(?i)doctor --fix')
  $cleanStartupSignal = ($logTail -match '(?i)\[gateway\]\s+ready') -or ($logTail -match '(?i)http server listening')

  $healthz = Get-HttpCheck -Url $HealthzUrl
  $controlUi = Get-HttpCheck -Url $ControlUiUrl

  [PSCustomObject]@{
    container_up          = $up
    container_status_raw  = $psRaw
    health_status         = $healthStatus
    version_label         = $versionLabel
    image_ref             = $imageRef
    log_tail_manual_repair_signal = [bool]$manualRepairSignal
    log_tail_clean_startup_signal = [bool]$cleanStartupSignal
    log_tail_lines         = $LogTailLines
    healthz                = $healthz
    control_ui             = $controlUi
  }
}

if ($Phase -eq 'capture') {
  $snapshot = Get-OpenclawSnapshot -ContainerName $ContainerName -HealthzUrl $HealthzUrl -ControlUiUrl $ControlUiUrl -LogTailLines $LogTailLines
  $record = [PSCustomObject]@{
    run_id         = $RunId
    phase          = 'capture'
    timestamp      = (Get-Date).ToString('o')
    target_version = $TargetVersion
    snapshot       = $snapshot
    known_good_query = [PSCustomObject]@{ confirmed = [bool]$KnownGoodQueryConfirmed; note = $KnownGoodQueryNote }
    discord_round_trip = [PSCustomObject]@{ confirmed = [bool]$DiscordRoundTripConfirmed; note = $DiscordRoundTripNote }
  }
  $outPath = Join-Path $runDir 'openclaw-update-phase0.json'
  $json = $record | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
  Write-Output $json
  Write-Output "Written to $outPath"
  exit 0
}

# $Phase -eq 'verify'
$phase0Path = Join-Path $runDir 'openclaw-update-phase0.json'
if (-not (Test-Path $phase0Path)) {
  throw "Phase 0 capture missing for run '$RunId': $phase0Path (run -Phase capture first with the same -RunId)"
}
$phase0 = Get-Content $phase0Path -Encoding utf8 -Raw | ConvertFrom-Json

$current = Get-OpenclawSnapshot -ContainerName $ContainerName -HealthzUrl $HealthzUrl -ControlUiUrl $ControlUiUrl -LogTailLines $LogTailLines

$target = if ($TargetVersion) { $TargetVersion } elseif ($phase0.target_version) { $phase0.target_version } else { $null }
$mode = if ($target) { 'target-check' } else { 'no-op-check' }

$knownGood = [PSCustomObject]@{ confirmed = [bool]$KnownGoodQueryConfirmed; note = $KnownGoodQueryNote }
$discordRt = [PSCustomObject]@{ confirmed = [bool]$DiscordRoundTripConfirmed; note = $DiscordRoundTripNote }

$diff = [PSCustomObject]@{
  version_label = [PSCustomObject]@{ before = $phase0.snapshot.version_label; after = $current.version_label; changed = ($phase0.snapshot.version_label -ne $current.version_label) }
  container_up  = [PSCustomObject]@{ before = $phase0.snapshot.container_up; after = $current.container_up; changed = ($phase0.snapshot.container_up -ne $current.container_up) }
  health_status = [PSCustomObject]@{ before = $phase0.snapshot.health_status; after = $current.health_status; changed = ($phase0.snapshot.health_status -ne $current.health_status) }
  healthz       = [PSCustomObject]@{ before_ok = $phase0.snapshot.healthz.ok; after_ok = $current.healthz.ok; changed = ($phase0.snapshot.healthz.ok -ne $current.healthz.ok) }
  control_ui    = [PSCustomObject]@{ before_ok = $phase0.snapshot.control_ui.ok; after_ok = $current.control_ui.ok; changed = ($phase0.snapshot.control_ui.ok -ne $current.control_ui.ok) }
}

$pass = if ($mode -eq 'target-check') {
  $current.container_up -and
  ($current.health_status -eq 'healthy') -and
  ($current.version_label -eq $target) -and
  (-not $current.log_tail_manual_repair_signal) -and
  $current.log_tail_clean_startup_signal -and
  $current.healthz.ok -and
  $current.control_ui.ok -and
  $knownGood.confirmed -and
  $discordRt.confirmed
}
else {
  (-not $diff.version_label.changed) -and
  (-not $diff.container_up.changed) -and
  (-not $diff.health_status.changed) -and
  (-not $diff.healthz.changed) -and
  (-not $diff.control_ui.changed) -and
  (-not $current.log_tail_manual_repair_signal)
}

$result = [PSCustomObject]@{
  run_id         = $RunId
  phase          = 'verify'
  timestamp      = (Get-Date).ToString('o')
  mode           = $mode
  target_version = $target
  current        = $current
  known_good_query = $knownGood
  discord_round_trip = $discordRt
  diff           = $diff
  pass           = [bool]$pass
}

$outPath = Join-Path $runDir 'openclaw-update-phase2.json'
$json = $result | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
Write-Output $json
Write-Output "Written to $outPath"

$statusWord = if ($pass) { 'PASS' } else { 'FAIL' }
$targetNote = if ($target) { " (target $target)" } else { '' }
$summaryLine = "OpenClaw update verify [$mode]: $statusWord. version $($diff.version_label.before) -> $($diff.version_label.after)$targetNote. manual_repair_signal=$($current.log_tail_manual_repair_signal). healthz_ok=$($current.healthz.ok). control_ui_ok=$($current.control_ui.ok). known_good_query_confirmed=$($knownGood.confirmed). discord_round_trip_confirmed=$($discordRt.confirmed)."
Write-Output $summaryLine

if ($PostToDiscord) {
  $postScript = Join-Path $ScriptsDir 'post-discord.ps1'
  $postArgs = @('-Channel', 'decisions', '-Message', $summaryLine, '-Title', "OpenClaw update verify: $statusWord")
  $postOutput = & pwsh -NoProfile -File $postScript @postArgs 2>&1 | Out-String
  Write-Output $postOutput.Trim()
}
else {
  Write-Output 'PostToDiscord not set — no live post sent (dry run, or -PostToDiscord intentionally omitted).'
}

if (-not $pass) { exit 1 }
exit 0
