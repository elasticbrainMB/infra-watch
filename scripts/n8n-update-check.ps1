# Read-only. Phase 0 / Phase 2 snapshot-and-diff for the n8n update-execution
# runbook (records\runbooks\n8n.md). Single-target script, mirroring
# ollama-update-check.ps1's -Phase/-RunId shape (PLAN-update-execution-v1.md
# Section 9, step 3), not docker-update-check.ps1's whole-fleet shape — an n8n
# update bounces only the n8n container, not the engine.
#
# Captures: docker ps/health for the n8n container; /healthz and
# /healthz/readiness status codes and bodies; a docker-logs-since-start tail
# scanned for exception/error text; the live workflow count (total + active),
# read directly and read-only from n8n's own SQLite file via `docker exec n8n
# node -e "...node:sqlite..."` (no n8n API key is available to this project,
# and the UI needs Matt's own login — reading the DB file directly is the only
# read-only source of truth available here); and an execution of the chosen
# smoke-test workflow via its webhook.
#
# The migration-completion signal is NOT a log-text grep. Read directly from
# n8n's own source at the pinned target tag (packages/cli/src/abstract-server.ts,
# n8n@2.37.11): `/healthz/readiness` returns 200 only when
# `connectionState.connected && connectionState.migrated && fullyReady`, where
# `connectionState.migrated` is set true only after
# packages/@n8n/db/src/connection/db-connection.ts's `migrate()` completes
# `dataSource.runMigrations()` without throwing. So healthz/readiness's own
# 200/503 status *is* the authoritative migration-completed signal — the log
# scan below is a corroborating second signal (catches an exception's stack
# trace even if the process later stabilizes), not the primary one.
#
# No data-backup logic here — per records\runbooks\n8n.md Phase 0.3, the
# mandatory volume backup is Matt's own hand action (docker run is
# unconditionally deny-listed for this project, no carve-out), verified
# afterward with Windows' own tar.exe, outside this script.
#
# One -RunId ties a Phase 0 capture to its Phase 2 verify: run -Phase capture
# first, then — whatever happened in between (nothing, for a dry run; the real
# pull+recreate, for a real one) — run -Phase verify with the same -RunId.
#
# Pass/fail definition:
#   - If a -TargetVersion was given at capture time (or again at verify time),
#     Phase 2 passes when: the container is Up and not restarting; healthz and
#     healthz/readiness both return 200; the post-start log tail contains no
#     exception/error markers; the workflow count (total and active) matches
#     the Phase 0 baseline exactly (proves the migration carried real state,
#     not an empty store); and the smoke-test workflow's webhook call
#     succeeds.
#   - If no target was ever given, Phase 2 passes when nothing drifted from
#     the Phase 0 capture at all — the dry-run / no-op check, proving the
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
  [string]$Container = 'n8n',
  [string]$HealthzUrl = 'http://127.0.0.1:5678/healthz',
  [string]$ReadinessUrl = 'http://127.0.0.1:5678/healthz/readiness',
  [string]$SmokeTestWorkflowName = 'caddy-ping',
  [string]$SmokeTestWebhookUrl = 'http://127.0.0.1:5678/webhook/caddy-ping',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$ScriptsDir = 'C:\automation\infra-watch\scripts',
  [switch]$PostToDiscord
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$errorMarkers = @('UnhandledPromiseRejection', 'FATAL', 'MigrationError', 'QueryFailedError', 'SqliteError', 'Unable to connect to the database', 'Error: connect ECONNREFUSED')

function Get-HttpCheck {
  param([string]$Uri)
  try {
    $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 15
    [PSCustomObject]@{
      ok        = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
      http_code = [int]$resp.StatusCode
      body      = if ($resp.Content.Length -le 500) { $resp.Content } else { $resp.Content.Substring(0, 500) + '...(truncated)' }
      error     = $null
    }
  }
  catch [Microsoft.PowerShell.Commands.HttpResponseException] {
    $code = [int]$_.Exception.Response.StatusCode
    [PSCustomObject]@{
      ok        = ($code -ge 200 -and $code -lt 300)
      http_code = $code
      body      = $null
      error     = $null
    }
  }
  catch {
    [PSCustomObject]@{
      ok        = $false
      http_code = $null
      body      = $null
      error     = $_.Exception.Message
    }
  }
}

function Get-ContainerState {
  param([string]$Container)
  $psRaw = (docker ps --filter "name=$Container" --format '{{json .}}' 2>&1 | Out-String).Trim()
  $health = (docker inspect --format '{{json .State.Health}}' $Container 2>&1 | Out-String).Trim()
  $startedAt = (docker inspect --format '{{.State.StartedAt}}' $Container 2>&1 | Out-String).Trim()
  $restartCount = (docker inspect --format '{{.RestartCount}}' $Container 2>&1 | Out-String).Trim()
  [PSCustomObject]@{
    ps_raw         = $psRaw
    up             = ($psRaw -ne '' -and $psRaw -notmatch '"State":"restarting"')
    health         = $health
    started_at     = $startedAt
    restart_count  = $restartCount
  }
}

function Get-LogSinceStart {
  param([string]$Container, [string]$StartedAt)
  $raw = (docker logs --since $StartedAt $Container 2>&1 | Out-String)
  $hits = @()
  foreach ($marker in $errorMarkers) {
    if ($raw -match [regex]::Escape($marker)) { $hits += $marker }
  }
  [PSCustomObject]@{
    clean       = ($hits.Count -eq 0)
    error_hits  = $hits
    tail_500    = if ($raw.Length -le 3000) { $raw } else { $raw.Substring($raw.Length - 3000) }
  }
}

function Get-WorkflowCounts {
  param([string]$Container)
  try {
    $script = 'const {DatabaseSync} = require("node:sqlite"); const db = new DatabaseSync("/home/node/.n8n/database.sqlite", {readOnly: true}); const total = db.prepare("SELECT COUNT(*) as c FROM workflow_entity").get(); const active = db.prepare("SELECT COUNT(*) as c FROM workflow_entity WHERE active = 1").get(); console.log(JSON.stringify({total: total.c, active: active.c})); db.close();'
    $raw = (docker exec $Container node -e $script 2>&1 | Out-String).Trim()
    $parsed = $raw | ConvertFrom-Json
    [PSCustomObject]@{ ok = $true; total = $parsed.total; active = $parsed.active; error = $null; raw = $raw }
  }
  catch {
    [PSCustomObject]@{ ok = $false; total = $null; active = $null; error = $_.Exception.Message; raw = $raw }
  }
}

function Get-SmokeTest {
  param([string]$WebhookUrl, [string]$WorkflowName)
  try {
    $resp = Invoke-WebRequest -Uri $WebhookUrl -Method Get -UseBasicParsing -TimeoutSec 30
    [PSCustomObject]@{
      ok         = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
      http_code  = [int]$resp.StatusCode
      workflow   = $WorkflowName
      body       = if ($resp.Content.Length -le 500) { $resp.Content } else { $resp.Content.Substring(0, 500) + '...(truncated)' }
      error      = $null
    }
  }
  catch {
    [PSCustomObject]@{
      ok         = $false
      http_code  = $null
      workflow   = $WorkflowName
      body       = $null
      error      = $_.Exception.Message
    }
  }
}

function Get-N8nSnapshot {
  param([string]$Container, [string]$HealthzUrl, [string]$ReadinessUrl, [string]$SmokeTestWebhookUrl, [string]$SmokeTestWorkflowName)

  $state       = Get-ContainerState -Container $Container
  $healthz     = Get-HttpCheck -Uri $HealthzUrl
  $readiness   = Get-HttpCheck -Uri $ReadinessUrl
  $logCheck    = if ($state.started_at) { Get-LogSinceStart -Container $Container -StartedAt $state.started_at } else { [PSCustomObject]@{ clean = $false; error_hits = @('no StartedAt available'); tail_500 = $null } }
  $workflows   = Get-WorkflowCounts -Container $Container
  $smokeTest   = Get-SmokeTest -WebhookUrl $SmokeTestWebhookUrl -WorkflowName $SmokeTestWorkflowName

  [PSCustomObject]@{
    container_state = $state
    healthz          = $healthz
    healthz_readiness = $readiness
    log_since_start  = $logCheck
    workflows        = $workflows
    smoke_test       = $smokeTest
  }
}

if ($Phase -eq 'capture') {
  $snapshot = Get-N8nSnapshot -Container $Container -HealthzUrl $HealthzUrl -ReadinessUrl $ReadinessUrl -SmokeTestWebhookUrl $SmokeTestWebhookUrl -SmokeTestWorkflowName $SmokeTestWorkflowName
  $record = [PSCustomObject]@{
    run_id         = $RunId
    phase          = 'capture'
    timestamp      = (Get-Date).ToString('o')
    target_version = $TargetVersion
    container      = $Container
    snapshot       = $snapshot
  }
  $outPath = Join-Path $runDir 'n8n-update-phase0.json'
  $json = $record | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
  Write-Output $json
  Write-Output "Written to $outPath"
  exit 0
}

# $Phase -eq 'verify'
$phase0Path = Join-Path $runDir 'n8n-update-phase0.json'
if (-not (Test-Path $phase0Path)) {
  throw "Phase 0 capture missing for run '$RunId': $phase0Path (run -Phase capture first with the same -RunId)"
}
$phase0 = Get-Content $phase0Path -Encoding utf8 -Raw | ConvertFrom-Json

$current = Get-N8nSnapshot -Container $Container -HealthzUrl $HealthzUrl -ReadinessUrl $ReadinessUrl -SmokeTestWebhookUrl $SmokeTestWebhookUrl -SmokeTestWorkflowName $SmokeTestWorkflowName

$target = if ($TargetVersion) { $TargetVersion } elseif ($phase0.target_version) { $phase0.target_version } else { $null }
$mode = if ($target) { 'target-check' } else { 'no-op-check' }

$workflowsMatch = ($phase0.snapshot.workflows.total -eq $current.workflows.total) -and ($phase0.snapshot.workflows.active -eq $current.workflows.active)

$diff = [PSCustomObject]@{
  container_up     = [PSCustomObject]@{ before = $phase0.snapshot.container_state.up; after = $current.container_state.up }
  healthz_ok       = [PSCustomObject]@{ before = $phase0.snapshot.healthz.ok; after = $current.healthz.ok }
  readiness_ok     = [PSCustomObject]@{ before = $phase0.snapshot.healthz_readiness.ok; after = $current.healthz_readiness.ok }
  log_clean        = [PSCustomObject]@{ before = $phase0.snapshot.log_since_start.clean; after = $current.log_since_start.clean }
  workflows        = [PSCustomObject]@{ before = $phase0.snapshot.workflows; after = $current.workflows; match = $workflowsMatch }
  smoke_test_ok    = [PSCustomObject]@{ before = $phase0.snapshot.smoke_test.ok; after = $current.smoke_test.ok }
}

$pass = if ($mode -eq 'target-check') {
  $current.container_state.up -and
  $current.healthz.ok -and
  $current.healthz_readiness.ok -and
  $current.log_since_start.clean -and
  $workflowsMatch -and
  $current.smoke_test.ok
}
else {
  ($phase0.snapshot.container_state.up -eq $current.container_state.up) -and
  ($phase0.snapshot.healthz.ok -eq $current.healthz.ok) -and
  ($phase0.snapshot.healthz_readiness.ok -eq $current.healthz_readiness.ok) -and
  ($phase0.snapshot.log_since_start.clean -eq $current.log_since_start.clean) -and
  $workflowsMatch -and
  ($phase0.snapshot.smoke_test.ok -eq $current.smoke_test.ok)
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

$outPath = Join-Path $runDir 'n8n-update-phase2.json'
$json = $result | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
Write-Output $json
Write-Output "Written to $outPath"

$statusWord = if ($pass) { 'PASS' } else { 'FAIL' }
$targetNote = if ($target) { " (target $target)" } else { '' }
$summaryLine = "n8n update verify [$mode]: $statusWord$targetNote. container up=$($current.container_state.up). healthz=$($current.healthz.ok) readiness=$($current.healthz_readiness.ok) log_clean=$($current.log_since_start.clean). workflows total=$($current.workflows.total) active=$($current.workflows.active) match=$workflowsMatch. smoke_test($SmokeTestWorkflowName)=$($current.smoke_test.ok)."
Write-Output $summaryLine

if ($PostToDiscord) {
  $postScript = Join-Path $ScriptsDir 'post-discord.ps1'
  $postArgs = @('-Channel', 'decisions', '-Message', $summaryLine, '-Title', "n8n update verify: $statusWord")
  $postOutput = & pwsh -NoProfile -File $postScript @postArgs 2>&1 | Out-String
  Write-Output $postOutput.Trim()
}
else {
  Write-Output 'PostToDiscord not set — no live post sent (dry run, or -PostToDiscord intentionally omitted).'
}

if (-not $pass) { exit 1 }
exit 0
