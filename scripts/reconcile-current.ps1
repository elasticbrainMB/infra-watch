# Closes the loop that post-notion.ps1's design otherwise leaves open: when a
# component that was previously behind (do-now/schedule/defer, with a real
# records\assessments\<id>.md file) becomes current again, nothing else in
# this project ever touches that file - it just sits there forever saying
# "you should update" even after the update has happened. This script
# replaces it with a short mechanical "current, no action needed" note
# whenever the deterministic facts (from check-releases.ps1's releases.json)
# say releases_behind is 0 for a component that already has a file on disk.
#
# No model call, by design - "current" is a fact, not a judgment call, same
# reasoning that keeps assess-update.ps1 from ever being asked to judge the
# deterministic fields it's handed.
#
# A component that has never been behind (no assessments\<id>.md file yet)
# is left alone - there's nothing to reconcile, and this project has never
# created a Notion row for it either.
param(
  [Parameter(Mandatory)][string]$RunId,
  [Parameter(Mandatory)][string]$ComponentId,
  [string]$InventoryPath = 'C:\automation\infra-watch\config\inventory.json',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$AssessmentsDir = 'C:\automation\infra-watch\records\assessments'
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId

$assessPath = Join-Path $AssessmentsDir "$ComponentId.md"
if (-not (Test-Path $assessPath)) {
  Write-Output "'$ComponentId' has no prior assessment file - never behind, nothing to reconcile."
  exit 0
}

$inventory = Get-Content $InventoryPath -Encoding utf8 -Raw | ConvertFrom-Json
$component = $inventory.components | Where-Object { $_.id -eq $ComponentId }
if (-not $component) { throw "No component '$ComponentId' in $InventoryPath" }

$releasesPath = Join-Path $runDir 'releases.json'
if (-not (Test-Path $releasesPath)) { throw "releases.json missing for run '$RunId': $releasesPath (run check-releases.ps1 first with the same -RunId)" }
$releases = Get-Content $releasesPath -Encoding utf8 -Raw | ConvertFrom-Json
$rel = $releases.components | Where-Object { $_.id -eq $ComponentId }
if (-not $rel) { throw "No releases.json entry for '$ComponentId' in run '$RunId'" }
if (-not $rel.ok) { throw "releases.json entry for '$ComponentId' is not ok: $($rel.error)" }
if ($rel.releases_behind -ne 0) { throw "'$ComponentId' has releases_behind=$($rel.releases_behind), not 0 - this script is only for components check-releases.ps1 found current this run" }

$newerMajor = if ($rel.newer_major_line_exists) { $rel.newer_major_line_exists } else { 'no' }

$why = "$($component.display) is running $($rel.installed_version), which is current within its own major line as of run ``$RunId`` - no release-driven action is pending. This note replaces the prior assessment now that the gap it described has closed."
if ($newerMajor -ne 'no') {
  $why += " A newer major line ($newerMajor) exists outside the tracked major version but is not counted here, per this project's same-major-line comparison rule."
}

$note = @"
# $($component.display) — $($rel.installed_version) (current)

_Assessment written $(Get-Date -Format 'yyyy-MM-dd'), run ``$RunId``._

| Field | Value |
|---|---|
| Component | ``$($component.id)`` |
| Installed version | ``$($rel.installed_version)`` |
| Current version (installed's own major line) | ``$($rel.current_version)`` |
| Releases behind | 0 |
| Minor boundary crossed | False |
| Newer major/track exists (uncounted) | $newerMajor |
| ``blast_radius`` | $($component.blast_radius) |

## Verdict: ``current``

$why

## What it will take

Nothing - already current. If a future run finds a new release, a fresh model assessment will replace this note.

## Source

Current release: $($rel.release_url)

---

_This is a mechanical reconciliation note, not a model assessment - no judgment call was needed since there is no pending update. ``blast_radius`` was declared by Matt in ``inventory.json``._
"@

New-Item -ItemType Directory -Force -Path $AssessmentsDir | Out-Null
[System.IO.File]::WriteAllText($assessPath, $note, $utf8NoBom)

Write-Output $note
Write-Output "Written to $assessPath"
exit 0
