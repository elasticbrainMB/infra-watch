# One command, end to end: read-installed -> check-releases -> assess-update
# (per component with a non-zero gap) -> Discord. Each stage is spawned as a
# real subprocess (pwsh -File), not called in-process via & or dot-source -
# all three end with `exit N`, and an in-process call would take run-check
# down with it. Only invoke-model.ps1 is safe to call in-process; it uses
# `return` for exactly this reason (see its own header comment).
#
# Stop rule: a failure in read-installed or check-releases halts the run
# before any model call - assessing against unreliable version data is
# worse than not assessing. A capped or malformed assess-update call for one
# component does not block assessing the others (a day-cap trip just makes
# every remaining call fail fast, cheaply) - but every failure is recorded
# and surfaced, never silently dropped.
param(
  [string]$RunId,
  [string]$InventoryPath = 'C:\automation\infra-watch\config\inventory.json',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$ScriptsDir = 'C:\automation\infra-watch\scripts'
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not $RunId) { $RunId = Get-Date -Format 'yyyyMMdd-HHmmss' }
$runDir = Join-Path $RunsDir $RunId

function Invoke-Stage {
  param([string]$ScriptPath, [string[]]$ScriptArgs)
  $output = & pwsh -NoProfile -File $ScriptPath @ScriptArgs 2>&1 | Out-String
  return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Send-Alert {
  param([string]$Channel, [string]$Message, [string]$Title)
  $args = @('-Channel', $Channel, '-Message', $Message)
  if ($Title) { $args += @('-Title', $Title) }
  $r = & pwsh -NoProfile -File (Join-Path $ScriptsDir 'post-discord.ps1') @args 2>&1 | Out-String
  Write-Output $r.Trim()
}

Write-Output "=== infra-watch run $RunId ==="

Write-Output "--- read-installed ---"
$installedStage = Invoke-Stage -ScriptPath (Join-Path $ScriptsDir 'read-installed.ps1') -ScriptArgs @('-RunId', $RunId, '-InventoryPath', $InventoryPath, '-RunsDir', $RunsDir)
Write-Output $installedStage.Output
if ($installedStage.ExitCode -ne 0) {
  $msg = "STOP: read-installed failed (exit $($installedStage.ExitCode)). Some component's installed version could not be resolved, or read as 'latest'. Run halted before any release check or model call. See records\runs\$RunId\installed.json."
  Write-Output $msg
  Send-Alert -Channel 'runs' -Message $msg -Title "Run $RunId failed"
  exit 1
}

Write-Output "--- check-releases ---"
$releasesStage = Invoke-Stage -ScriptPath (Join-Path $ScriptsDir 'check-releases.ps1') -ScriptArgs @('-RunId', $RunId, '-InventoryPath', $InventoryPath, '-RunsDir', $RunsDir)
Write-Output $releasesStage.Output
if ($releasesStage.ExitCode -ne 0) {
  $msg = "STOP: check-releases failed (exit $($releasesStage.ExitCode)). Some component's current version could not be resolved. Run halted before any model call. See records\runs\$RunId\releases.json."
  Write-Output $msg
  Send-Alert -Channel 'runs' -Message $msg -Title "Run $RunId failed"
  exit 1
}

$releases = Get-Content (Join-Path $runDir 'releases.json') -Encoding utf8 -Raw | ConvertFrom-Json
$inventory = Get-Content $InventoryPath -Encoding utf8 -Raw | ConvertFrom-Json
$inventoryById = @{}
foreach ($c in $inventory.components) { $inventoryById[$c.id] = $c }

$behind = @($releases.components | Where-Object { $_.ok -and $_.releases_behind -gt 0 })
$current = @($releases.components | Where-Object { $_.ok -and $_.releases_behind -eq 0 })

Write-Output "--- assess-update ($(@($behind).Count) component(s) behind) ---"
$assessments = foreach ($rel in $behind) {
  $stage = Invoke-Stage -ScriptPath (Join-Path $ScriptsDir 'assess-update.ps1') -ScriptArgs @('-RunId', $RunId, '-ComponentId', $rel.id, '-InventoryPath', $InventoryPath, '-RunsDir', $RunsDir)
  # Write-Host, not Write-Output: this loop's result is captured as $assessments
  # (foreach used as an expression) - anything written to the success stream
  # inside it, Write-Output included, gets swept into that collection too.
  Write-Host $stage.Output
  if ($stage.ExitCode -ne 0) {
    [PSCustomObject]@{ id = $rel.id; ok = $false; verdict = $null }
    continue
  }
  $assessPath = Join-Path 'C:\automation\infra-watch\records\assessments' "$($rel.id).md"
  $verdictLine = if (Test-Path $assessPath) { (Select-String -Path $assessPath -Pattern '^## Verdict: `(do-now|schedule|defer)`' | Select-Object -First 1) } else { $null }
  $verdict = if ($verdictLine) { $verdictLine.Matches[0].Groups[1].Value } else { $null }
  [PSCustomObject]@{ id = $rel.id; ok = $true; verdict = $verdict }
}
$assessments = @($assessments)

$failed = @($assessments | Where-Object { -not $_.ok })
$doNow = @($assessments | Where-Object { $_.verdict -eq 'do-now' })
$scheduleHigh = @($assessments | Where-Object { $_.verdict -eq 'schedule' -and $inventoryById[$_.id].blast_radius -eq 'high' })
$scheduleOther = @($assessments | Where-Object { $_.verdict -eq 'schedule' -and $inventoryById[$_.id].blast_radius -ne 'high' })
$defer = @($assessments | Where-Object { $_.verdict -eq 'defer' })

$runSpend = 0.0
$logFile = Join-Path $RunsDir 'model-calls.jsonl'
if (Test-Path $logFile) {
  foreach ($line in Get-Content $logFile -Encoding utf8) {
    if (-not $line.Trim()) { continue }
    $entry = $line | ConvertFrom-Json
    if ($entry.RunId -ceq $RunId) { $runSpend += [double]$entry.Cost }
  }
}

$summary = [PSCustomObject]@{
  run_id         = $RunId
  timestamp      = (Get-Date).ToString('o')
  tracked        = @($inventory.components).Count
  current        = @($current).Count
  behind         = @($behind).Count
  assessed_ok    = @($assessments | Where-Object { $_.ok }).Count
  assessed_failed = @($failed).Count
  verdicts       = [PSCustomObject]@{
    'do-now'   = @($doNow).Count
    'schedule' = @($assessments | Where-Object { $_.verdict -eq 'schedule' }).Count
    'defer'    = @($defer).Count
  }
  spend          = $runSpend
  components     = $assessments
}
$summaryPath = Join-Path $runDir 'summary.json'
[System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 6), $utf8NoBom)
Write-Output "--- summary ---"
Write-Output ($summary | ConvertTo-Json -Depth 6)
Write-Output "Written to $summaryPath"

$verdictBits = @()
if (@($doNow).Count -gt 0) { $verdictBits += "$(@($doNow).Count) do-now" }
$scheduleCount = @($assessments | Where-Object { $_.verdict -eq 'schedule' }).Count
if ($scheduleCount -gt 0) { $verdictBits += "$scheduleCount schedule" }
if (@($defer).Count -gt 0) { $verdictBits += "$(@($defer).Count) defer" }
$verdictSummary = if ($verdictBits.Count -gt 0) { $verdictBits -join ', ' } else { 'none' }

$alertMsg = "Run ${RunId}: $(@($inventory.components).Count) tracked, $(@($behind).Count) behind, $(@($assessments | Where-Object { $_.ok }).Count) assessed ($verdictSummary)$(if (@($failed).Count -gt 0) { ", $(@($failed).Count) FAILED: $(($failed.id) -join ', ')" }). Spend `$$([math]::Round($runSpend, 4))."
Send-Alert -Channel 'runs' -Message $alertMsg

$needsDecision = @($doNow) + @($scheduleHigh)
if (@($needsDecision).Count -gt 0) {
  $lines = foreach ($a in $needsDecision) {
    $c = $inventoryById[$a.id]
    "**$($c.display)** — ``$($a.verdict)`` (blast_radius: $($c.blast_radius)). See records\assessments\$($a.id).md"
  }
  $decisionMsg = ($lines -join "`n")
  Send-Alert -Channel 'decisions' -Message $decisionMsg -Title "Run $RunId needs a look"
} else {
  Write-Output "No do-now verdicts and no high-blast-radius schedule verdicts - nothing posted to #decisions."
}

if (@($failed).Count -gt 0) { exit 1 }
exit 0
