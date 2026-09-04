# One component per call, by design - batching risks one component's
# verdict leaking into another's ("an absence phrased beside neighbours
# gets recruited into the disagreement", per the caddy's own finding).
# Deterministic facts (installed/current version, releases behind, boundary
# crossed, blast_radius) are computed by check-releases.ps1 / inventory.json
# and handed to the model as fact, not asked of it - only the verdict, why,
# and what-it-will-take require actually reading the release notes.
param(
  [Parameter(Mandatory)][string]$RunId,
  [Parameter(Mandatory)][string]$ComponentId,
  [string]$InventoryPath = 'C:\automation\infra-watch\config\inventory.json',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$AssessmentsDir = 'C:\automation\infra-watch\records\assessments',
  [string]$Provider = 'openrouter',
  [string]$Model = 'z-ai/glm-5.3-20260816',
  [int]$MaxTokens = 2000
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId

$inventory = Get-Content $InventoryPath -Encoding utf8 -Raw | ConvertFrom-Json
$component = $inventory.components | Where-Object { $_.id -eq $ComponentId }
if (-not $component) { throw "No component '$ComponentId' in $InventoryPath" }

$releasesPath = Join-Path $runDir 'releases.json'
if (-not (Test-Path $releasesPath)) { throw "releases.json missing for run '$RunId': $releasesPath (run check-releases.ps1 first with the same -RunId)" }
$releases = Get-Content $releasesPath -Encoding utf8 -Raw | ConvertFrom-Json
$rel = $releases.components | Where-Object { $_.id -eq $ComponentId }
if (-not $rel) { throw "No releases.json entry for '$ComponentId' in run '$RunId'" }
if (-not $rel.ok) { throw "releases.json entry for '$ComponentId' is not ok: $($rel.error)" }

if ($rel.releases_behind -eq 0) {
  Write-Output "'$ComponentId' is already current ($($rel.installed_version)) - nothing to assess."
  exit 0
}

$rawPath = Join-Path $runDir "releases-raw\$ComponentId.json"
if (-not (Test-Path $rawPath)) { throw "Raw releases dump missing: $rawPath (check-releases.ps1 writes this; it may have been run for a different RunId)" }
$rawReleases = Get-Content $rawPath -Encoding utf8 -Raw | ConvertFrom-Json

$installedVersion = [version]$rel.installed_version
$pattern = $component.releases_from.tag_pattern

$inGap = foreach ($r in $rawReleases) {
  if ($r.draft -or $r.prerelease) { continue }
  $m = [regex]::Match($r.tag_name, $pattern)
  if (-not $m.Success) { continue }
  $v = [version]$m.Groups[1].Value
  if ($v.Major -ne $installedVersion.Major) { continue }
  if ($v -le $installedVersion) { continue }
  [PSCustomObject]@{ version = $v; tag_name = $r.tag_name; published_at = $r.published_at; body = $r.body }
}
$inGap = @($inGap | Sort-Object version)

if (@($inGap).Count -eq 0) { throw "releases.json says $($rel.releases_behind) behind but no matching releases found in $rawPath - raw dump may be stale for this RunId" }

$notesBlob = ($inGap | ForEach-Object {
  "### $($_.tag_name) ($($_.published_at))`n`n$($_.body)"
}) -join "`n`n---`n`n"

$systemText = @"
You are the judgment layer for infra-watch, a personal update-tracking tool for Matt's self-hosted infrastructure. Your only job: read the raw release notes below for one component's pending updates and produce a short, opinionated assessment of what changed. You are not deciding whether to apply the update (that's Matt's call) and not judging how costly an outage of this component would be (already declared separately, below) - judge only the change itself:

- Does it fix a security issue? If the notes literally say so, treat that as the security signal - no deeper vulnerability research is expected of you.
- Does it break anything - config format, API, CLI behavior, a required migration step?
- Or is it routine - bug fixes, minor features, nothing that needs action?

Respond in EXACTLY this format and nothing else - three lines, each starting with the exact label shown, no markdown, no preamble, no closing remarks:

VERDICT: <one of: do-now, schedule, defer>
WHY: <two to three plain sentences, grounded in what the notes actually say - not generic>
WHAT_IT_WILL_TAKE: <one to two sentences - a config change, a migration, a container recreation, or "nothing beyond the normal update process" if the notes call for nothing unusual>

Verdict guide:
- do-now: a real security fix, or something already broken / actively causing problems
- schedule: meaningful changes worth doing deliberately soon (a breaking change needing a migration, a feature Matt likely wants) but nothing urgent
- defer: routine patches, no security content, nothing broken, no reason to prioritize this over anything else
"@

$userText = @"
Component: $($component.display) ($($component.id))
Installed: $($rel.installed_version)
Current, within the installed version's own major line: $($rel.current_version)
Releases behind: $($rel.releases_behind)
Minor boundary crossed: $($rel.minor_boundary_crossed)
Blast radius if this component goes down (already declared by Matt - judge the change, not the stakes): $($component.blast_radius)

Raw release notes for every release between installed and current, oldest first:

$notesBlob
"@

$invokeModelPath = 'C:\automation\infra-watch\scripts\invoke-model.ps1'
$result = & $invokeModelPath -Provider $Provider -Model $Model -Step "assess-$ComponentId" -RunId $RunId `
  -SystemText $systemText -UserText $userText -MaxTokens $MaxTokens -Temperature 0

if ($result.Status -eq 'capped') {
  Write-Output "STOP: $($result.Reason)"
  exit 1
}

$content = $result.Content
if (-not $content -or -not $content.Trim()) {
  Write-Output "STOP: model call for '$ComponentId' returned empty content. Raw response: $($result.Log | ConvertTo-Json -Compress)"
  exit 1
}

$verdictMatch = [regex]::Match($content, 'VERDICT:\s*(do-now|schedule|defer)\b')
$whyMatch = [regex]::Match($content, 'WHY:\s*(.+?)(?=\r?\nWHAT_IT_WILL_TAKES?:|\z)', 'Singleline')
$whatMatch = [regex]::Match($content, 'WHAT_IT_WILL_TAKES?:\s*(.+)', 'Singleline')

if (-not $verdictMatch.Success -or -not $whyMatch.Success -or -not $whatMatch.Success) {
  Write-Output "STOP: model response for '$ComponentId' did not match the required VERDICT/WHY/WHAT_IT_WILL_TAKE format. Raw content:`n$content"
  exit 1
}

$verdict = $verdictMatch.Groups[1].Value
$why = $whyMatch.Groups[1].Value.Trim()
$whatItWillTake = $whatMatch.Groups[1].Value.Trim()

$assessment = @"
# $($component.display) — $($rel.installed_version) → $($rel.current_version)

_Assessment written $(Get-Date -Format 'yyyy-MM-dd'), run ``$RunId``._

| Field | Value |
|---|---|
| Component | ``$($component.id)`` |
| Installed version | ``$($rel.installed_version)`` |
| Current version (installed's own major line) | ``$($rel.current_version)`` |
| Releases behind | $($rel.releases_behind) |
| Minor boundary crossed | $($rel.minor_boundary_crossed) |
| Newer major/track exists (uncounted) | $(if ($rel.newer_major_line_exists) { $rel.newer_major_line_exists } else { 'no' }) |
| ``blast_radius`` | $($component.blast_radius) |

## Verdict: ``$verdict``

$why

## What it will take

$whatItWillTake

## Source

Raw release notes this verdict was drawn from: $($rel.release_url)

---

_This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. ``blast_radius`` was declared by Matt in ``inventory.json``; everything else on this page is the model's assessment of the change itself._
"@

New-Item -ItemType Directory -Force -Path $AssessmentsDir | Out-Null
$outPath = Join-Path $AssessmentsDir "$ComponentId.md"
[System.IO.File]::WriteAllText($outPath, $assessment, $utf8NoBom)

Write-Output $assessment
Write-Output "Written to $outPath"
Write-Output "Model call cost: `$$($result.Log.Cost) ($($result.Log.TokensIn) in / $($result.Log.TokensOut) out)"
exit 0
