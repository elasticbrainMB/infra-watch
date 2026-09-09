# Read-only. Phase 0 / Phase 2 snapshot-and-diff for the Docker Engine
# update-execution runbook (records\runbooks\docker.md). Unlike
# node-update-check.ps1 / ollama-update-check.ps1 (single-target), this
# script snapshots and diffs an entire container FLEET, because updating the
# engine restarts the daemon and bounces every running container at once —
# per PLAN-update-execution-v1.md §4b, "the engine update isn't verified
# until the things running on it are." No install, no rollback, no mutating
# docker/daemon command — this script only reads state and writes its own
# JSON record under records\runs\.
#
# Captures: engine version; the full docker ps -a fleet (name/image/state/
# status/health), diffed by container name so a missing or stuck-restarting
# container is caught even if it isn't one of the three tracked ones; each
# of n8n/open-webui/openclaw's own health signal (docker health status plus
# each container's own HTTP smoke check); open-webui's and openclaw's live
# reachability to Ollama over host.docker.internal; and daemon.json's
# max-concurrent-downloads/-uploads settings (the 29.7.0 config wrinkle).
#
# Openclaw's Ollama-reachability check is a network-level curl from inside
# the container to host.docker.internal:11434 — it does not read OpenClaw's
# own provider config file or dump its container env (which would expose
# secrets, as happened incidentally during the Ollama sitting). This stays
# inside CLAUDE.md's hard boundary: version/health/network-reachability only,
# never OpenClaw's config content.
#
# One -RunId ties a Phase 0 capture to its Phase 2 verify: run -Phase
# capture first, then — whatever happened in between (nothing, for a dry
# run; the real engine update, for a real one) — run -Phase verify with the
# same -RunId.
#
# Pass/fail definition:
#   - If a -TargetVersion was given at capture time (or is given again at
#     verify time), Phase 2 passes when: the engine version equals the
#     target; every container present in the Phase 0 fleet snapshot is
#     present again in State=running (none missing, none stuck restarting —
#     new containers are not a failure, they're unrelated to this update);
#     n8n/open-webui/openclaw each pass their own HTTP/health check; both
#     dependents still reach Ollama; and (if -ExpectedMaxConcurrentDownloads
#     / -ExpectedMaxConcurrentUploads were given) daemon.json's concurrency
#     settings match the value Matt decided in Phase 0.6, not a silently
#     applied default.
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
  [Nullable[int]]$ExpectedMaxConcurrentDownloads,
  [Nullable[int]]$ExpectedMaxConcurrentUploads,
  [string]$DaemonJsonPath = "$env:USERPROFILE\.docker\daemon.json",
  [string[]]$TrackedContainers = @('n8n', 'open-webui', 'openclaw'),
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
  param([string]$Uri)
  try {
    $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 15
    [PSCustomObject]@{
      ok        = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
      http_code = [int]$resp.StatusCode
      body      = if ($resp.Content.Length -le 2000) { $resp.Content } else { $resp.Content.Substring(0, 2000) + '...(truncated)' }
      error     = $null
    }
  }
  catch [Microsoft.PowerShell.Commands.HttpResponseException] {
    # A non-2xx HTTP response (e.g. n8n's 401 on an unauthenticated API call)
    # is a real, informative status code, not a transport failure.
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

function Get-ContainerExecHttpCheck {
  param([string]$Container, [string]$Url)
  $result = [PSCustomObject]@{ checked = $true; http_code = $null; ok = $false; error = $null }
  try {
    $code = (docker exec $Container curl -s -o /dev/null -w '%{http_code}' $Url 2>&1 | Out-String).Trim()
    $result.http_code = $code
    $result.ok = ($code -eq '200')
  }
  catch {
    $result.error = $_.Exception.Message
  }
  $result
}

function Get-DockerFleet {
  $raw = (docker ps -a --format '{{json .}}' 2>&1 | Out-String)
  $lines = $raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
  $containers = @()
  foreach ($line in $lines) {
    try {
      $c = $line | ConvertFrom-Json
      $containers += [PSCustomObject]@{
        name          = $c.Names
        image         = $c.Image
        state         = $c.State
        status        = $c.Status
        health_status = $c.HealthStatus
      }
    }
    catch {
      # Non-JSON line (e.g. a docker warning on stderr) — keep it visible
      # rather than silently dropping a container from the fleet snapshot.
      $containers += [PSCustomObject]@{ name = $null; image = $null; state = $null; status = $null; health_status = $null; raw_unparsed = $line }
    }
  }
  [PSCustomObject]@{ raw = $raw.Trim(); containers = $containers }
}

function Get-TrackedContainerChecks {
  [PSCustomObject]@{
    n8n = [PSCustomObject]@{
      docker_health = (docker inspect --format '{{json .State.Health}}' n8n 2>&1 | Out-String).Trim()
      healthz            = Get-HttpCheck -Uri 'http://127.0.0.1:5678/healthz'
      healthz_readiness  = Get-HttpCheck -Uri 'http://127.0.0.1:5678/healthz/readiness'
    }
    open_webui = [PSCustomObject]@{
      docker_health = (docker inspect --format '{{json .State.Health}}' open-webui 2>&1 | Out-String).Trim()
      root          = Get-HttpCheck -Uri 'http://127.0.0.1:3000/'
      api_version   = Get-HttpCheck -Uri 'http://127.0.0.1:3000/api/version'
    }
    openclaw = [PSCustomObject]@{
      docker_health = (docker inspect --format '{{json .State.Health}}' openclaw 2>&1 | Out-String).Trim()
      control_ui    = Get-HttpCheck -Uri 'http://127.0.0.1:18789/'
    }
  }
}

function Get-DependentOllamaChecks {
  [PSCustomObject]@{
    open_webui = Get-ContainerExecHttpCheck -Container 'open-webui' -Url 'http://host.docker.internal:11434/api/version'
    openclaw   = Get-ContainerExecHttpCheck -Container 'openclaw' -Url 'http://host.docker.internal:11434/api/version'
  }
}

function Get-DaemonJsonSnapshot {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return [PSCustomObject]@{ path = $Path; exists = $false; raw = $null; max_concurrent_downloads = $null; max_concurrent_uploads = $null }
  }
  $raw = Get-Content $Path -Raw -Encoding utf8
  $parsed = $null
  try { $parsed = $raw | ConvertFrom-Json } catch {}
  [PSCustomObject]@{
    path                      = $Path
    exists                    = $true
    raw                       = $raw
    max_concurrent_downloads  = if ($parsed -and ($parsed.PSObject.Properties.Name -contains 'max-concurrent-downloads')) { $parsed.'max-concurrent-downloads' } else { $null }
    max_concurrent_uploads    = if ($parsed -and ($parsed.PSObject.Properties.Name -contains 'max-concurrent-uploads')) { $parsed.'max-concurrent-uploads' } else { $null }
  }
}

function Get-DockerSnapshot {
  param([string]$DaemonJsonPath)
  $engineVersion = (docker version --format '{{.Server.Version}}' 2>&1 | Out-String).Trim()
  $fleet         = Get-DockerFleet
  $tracked       = Get-TrackedContainerChecks
  $dependents    = Get-DependentOllamaChecks
  $daemonJson    = Get-DaemonJsonSnapshot -Path $DaemonJsonPath

  [PSCustomObject]@{
    engine_version = $engineVersion
    fleet          = $fleet
    tracked        = $tracked
    dependents     = $dependents
    daemon_json    = $daemonJson
  }
}

function Compare-Fleet {
  param([array]$Before, [array]$After)
  $beforeMap = @{}
  foreach ($c in $Before) { if ($c.name) { $beforeMap[$c.name] = $c } }
  $afterMap = @{}
  foreach ($c in $After) { if ($c.name) { $afterMap[$c.name] = $c } }

  $missing = @($Before | Where-Object { $_.name -and -not $afterMap.ContainsKey($_.name) } | ForEach-Object { $_.name })
  $added   = @($After  | Where-Object { $_.name -and -not $beforeMap.ContainsKey($_.name) } | ForEach-Object { $_.name })
  $notRunning = @()
  foreach ($name in $beforeMap.Keys) {
    if ($afterMap.ContainsKey($name) -and $afterMap[$name].state -ne 'running') {
      $notRunning += [PSCustomObject]@{ name = $name; state = $afterMap[$name].state; status = $afterMap[$name].status }
    }
  }
  [PSCustomObject]@{
    missing      = $missing
    added        = $added
    not_running  = $notRunning
  }
}

if ($Phase -eq 'capture') {
  $snapshot = Get-DockerSnapshot -DaemonJsonPath $DaemonJsonPath
  $record = [PSCustomObject]@{
    run_id          = $RunId
    phase           = 'capture'
    timestamp       = (Get-Date).ToString('o')
    target_version  = $TargetVersion
    tracked_containers = $TrackedContainers
    snapshot        = $snapshot
  }
  $outPath = Join-Path $runDir 'docker-update-phase0.json'
  $json = $record | ConvertTo-Json -Depth 12
  [System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
  Write-Output $json
  Write-Output "Written to $outPath"
  exit 0
}

# $Phase -eq 'verify'
$phase0Path = Join-Path $runDir 'docker-update-phase0.json'
if (-not (Test-Path $phase0Path)) {
  throw "Phase 0 capture missing for run '$RunId': $phase0Path (run -Phase capture first with the same -RunId)"
}
$phase0 = Get-Content $phase0Path -Encoding utf8 -Raw | ConvertFrom-Json

$current = Get-DockerSnapshot -DaemonJsonPath $DaemonJsonPath

$target = if ($TargetVersion) { $TargetVersion } elseif ($phase0.target_version) { $phase0.target_version } else { $null }
$mode = if ($target) { 'target-check' } else { 'no-op-check' }

$fleetDiff = Compare-Fleet -Before $phase0.snapshot.fleet.containers -After $current.fleet.containers

$engineChanged = ($phase0.snapshot.engine_version -ne $current.engine_version)

$trackedOkBefore = [PSCustomObject]@{
  n8n        = ($phase0.snapshot.tracked.n8n.healthz.ok -and $phase0.snapshot.tracked.n8n.healthz_readiness.ok)
  open_webui = ($phase0.snapshot.tracked.open_webui.root.ok -and $phase0.snapshot.tracked.open_webui.api_version.ok)
  openclaw   = $phase0.snapshot.tracked.openclaw.control_ui.ok
}
$trackedOkAfter = [PSCustomObject]@{
  n8n        = ($current.tracked.n8n.healthz.ok -and $current.tracked.n8n.healthz_readiness.ok)
  open_webui = ($current.tracked.open_webui.root.ok -and $current.tracked.open_webui.api_version.ok)
  openclaw   = $current.tracked.openclaw.control_ui.ok
}

$dependentsOkBefore = [PSCustomObject]@{
  open_webui = $phase0.snapshot.dependents.open_webui.ok
  openclaw   = $phase0.snapshot.dependents.openclaw.ok
}
$dependentsOkAfter = [PSCustomObject]@{
  open_webui = $current.dependents.open_webui.ok
  openclaw   = $current.dependents.openclaw.ok
}

$concurrencyMatch = $true
$concurrencyNote = 'No expected concurrency values supplied — reporting only, not gating.'
if ($null -ne $ExpectedMaxConcurrentDownloads -or $null -ne $ExpectedMaxConcurrentUploads) {
  $dlMatch = (-not $ExpectedMaxConcurrentDownloads) -or ($current.daemon_json.max_concurrent_downloads -eq $ExpectedMaxConcurrentDownloads)
  $ulMatch = (-not $ExpectedMaxConcurrentUploads) -or ($current.daemon_json.max_concurrent_uploads -eq $ExpectedMaxConcurrentUploads)
  $concurrencyMatch = [bool]($dlMatch -and $ulMatch)
  $concurrencyNote = "Expected downloads=$ExpectedMaxConcurrentDownloads uploads=$ExpectedMaxConcurrentUploads; got downloads=$($current.daemon_json.max_concurrent_downloads) uploads=$($current.daemon_json.max_concurrent_uploads)."
}

$diff = [PSCustomObject]@{
  engine_version = [PSCustomObject]@{ before = $phase0.snapshot.engine_version; after = $current.engine_version; changed = $engineChanged }
  fleet          = $fleetDiff
  tracked_ok     = [PSCustomObject]@{ before = $trackedOkBefore; after = $trackedOkAfter }
  dependents_ok  = [PSCustomObject]@{ before = $dependentsOkBefore; after = $dependentsOkAfter }
  daemon_json    = [PSCustomObject]@{ match = $concurrencyMatch; note = $concurrencyNote; before = $phase0.snapshot.daemon_json; after = $current.daemon_json }
}

$pass = if ($mode -eq 'target-check') {
  ($current.engine_version -eq $target) -and
  ($fleetDiff.missing.Count -eq 0) -and
  ($fleetDiff.not_running.Count -eq 0) -and
  $trackedOkAfter.n8n -and $trackedOkAfter.open_webui -and $trackedOkAfter.openclaw -and
  $dependentsOkAfter.open_webui -and $dependentsOkAfter.openclaw -and
  $concurrencyMatch
}
else {
  (-not $engineChanged) -and
  ($fleetDiff.missing.Count -eq 0) -and
  ($fleetDiff.added.Count -eq 0) -and
  ($fleetDiff.not_running.Count -eq 0) -and
  ($trackedOkBefore.n8n -eq $trackedOkAfter.n8n) -and
  ($trackedOkBefore.open_webui -eq $trackedOkAfter.open_webui) -and
  ($trackedOkBefore.openclaw -eq $trackedOkAfter.openclaw) -and
  ($dependentsOkBefore.open_webui -eq $dependentsOkAfter.open_webui) -and
  ($dependentsOkBefore.openclaw -eq $dependentsOkAfter.openclaw)
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

$outPath = Join-Path $runDir 'docker-update-phase2.json'
$json = $result | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)
Write-Output $json
Write-Output "Written to $outPath"

$statusWord = if ($pass) { 'PASS' } else { 'FAIL' }
$targetNote = if ($target) { " (target $target)" } else { '' }
$summaryLine = "Docker Engine update verify [$mode]: $statusWord. engine $($diff.engine_version.before) -> $($diff.engine_version.after)$targetNote. fleet missing=$($fleetDiff.missing.Count) not_running=$($fleetDiff.not_running.Count) added=$($fleetDiff.added.Count). tracked after: n8n=$($trackedOkAfter.n8n) open-webui=$($trackedOkAfter.open_webui) openclaw=$($trackedOkAfter.openclaw). dependents after: open-webui=$($dependentsOkAfter.open_webui) openclaw=$($dependentsOkAfter.openclaw). daemon.json match=$concurrencyMatch."
Write-Output $summaryLine

if ($PostToDiscord) {
  $postScript = Join-Path $ScriptsDir 'post-discord.ps1'
  $postArgs = @('-Channel', 'decisions', '-Message', $summaryLine, '-Title', "Docker Engine update verify: $statusWord")
  $postOutput = & pwsh -NoProfile -File $postScript @postArgs 2>&1 | Out-String
  Write-Output $postOutput.Trim()
}
else {
  Write-Output 'PostToDiscord not set — no live post sent (dry run, or -PostToDiscord intentionally omitted).'
}

if (-not $pass) { exit 1 }
exit 0
