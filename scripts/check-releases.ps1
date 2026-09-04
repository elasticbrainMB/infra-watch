# Read-only. For each github-releases component in inventory.json, fetches
# the repo's releases and determines the current version WITHIN the
# installed version's own major line — not the highest tag in the repo
# overall. Several tracked repos mix unrelated tags in the same releases
# feed (n8n: a legacy 1.x patch line under the same "n8n@" prefix; moby/moby:
# client/vX and api/vX package tags alongside docker-vX engine tags; node:
# an official even-major-goes-LTS model where the newest even major is
# "Current", not the line most installs should compare against). Comparing
# against "highest tag anywhere" would misreport how far behind each one is.
# A newer major/track existing outside the installed line is still recorded,
# separately, as an informational (uncounted) flag.
param(
  [Parameter(Mandatory)][string]$RunId,
  [string]$InventoryPath = 'C:\automation\infra-watch\config\inventory.json',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs',
  [string]$SecretsFile = 'C:\automation\secrets\infra-watch.env'
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runDir = Join-Path $RunsDir $RunId
$installedPath = Join-Path $runDir 'installed.json'

if (-not (Test-Path $InventoryPath)) { throw "Inventory file missing: $InventoryPath" }
if (-not (Test-Path $installedPath)) { throw "installed.json missing for run '$RunId': $installedPath (run read-installed.ps1 first with the same -RunId)" }

$inventory = Get-Content $InventoryPath -Encoding utf8 -Raw | ConvertFrom-Json
$installed = Get-Content $installedPath -Encoding utf8 -Raw | ConvertFrom-Json
$installedById = @{}
foreach ($r in $installed.components) { $installedById[$r.id] = $r }

$githubToken = $null
if (Test-Path $SecretsFile) {
  foreach ($line in Get-Content $SecretsFile -Encoding utf8) {
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    if ($line.Substring(0, $idx) -ceq 'GITHUB_TOKEN') { $githubToken = $line.Substring($idx + 1); break }
  }
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$rawDir = Join-Path $runDir 'releases-raw'
New-Item -ItemType Directory -Force -Path $rawDir | Out-Null

function Get-GithubReleases {
  param([string]$Repo, [string]$RawPath, [string]$Token)
  $tmpHeader = [System.IO.Path]::GetTempFileName()
  try {
    $headerLines = @('header = "Accept: application/vnd.github+json"', 'header = "User-Agent: infra-watch"')
    if ($Token) { $headerLines += "header = `"Authorization: Bearer $Token`"" }
    [System.IO.File]::WriteAllText($tmpHeader, ($headerLines -join "`n") + "`n", $utf8NoBom)

    $httpCode = curl.exe -s -o $RawPath -w "%{http_code}" -K $tmpHeader "https://api.github.com/repos/$Repo/releases?per_page=100"
    $curlExit = $LASTEXITCODE
    if ($curlExit -ne 0) { throw "curl.exe failed reaching GitHub for $Repo, exit code $curlExit" }
    if ($httpCode -notmatch '^2\d\d$') {
      $body = if (Test-Path $RawPath) { [System.IO.File]::ReadAllText($RawPath, [Text.Encoding]::UTF8) } else { '' }
      throw "GitHub returned HTTP $httpCode for $Repo. $body"
    }
    return [System.IO.File]::ReadAllText($RawPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  }
  finally {
    Remove-Item $tmpHeader -Force -ErrorAction SilentlyContinue
  }
}

$results = foreach ($c in $inventory.components) {
  if ($c.releases_from.method -ne 'github-releases') {
    [PSCustomObject]@{ id = $c.id; ok = $false; error = "Unhandled releases_from.method '$($c.releases_from.method)'" }
    continue
  }

  $instRec = $installedById[$c.id]
  if (-not $instRec -or -not $instRec.ok) {
    [PSCustomObject]@{ id = $c.id; ok = $false; error = "No resolved installed version for '$($c.id)' in $installedPath" }
    continue
  }

  try {
    $rawPath = Join-Path $rawDir "$($c.id).json"
    $releases = Get-GithubReleases -Repo $c.releases_from.repo -RawPath $rawPath -Token $githubToken

    $pattern = $c.releases_from.tag_pattern
    $matched = foreach ($r in $releases) {
      if ($r.draft) { continue }
      if ($r.prerelease) { continue }
      $m = [regex]::Match($r.tag_name, $pattern)
      if (-not $m.Success) { continue }
      [PSCustomObject]@{
        version  = [version]$m.Groups[1].Value
        tag_name = $r.tag_name
        html_url = $r.html_url
        body     = $r.body
      }
    }

    if (@($matched).Count -eq 0) { throw "No release tags matched pattern '$pattern' in $(@($releases).Count) fetched releases for $($c.releases_from.repo)" }

    $installedVersion = [version]$instRec.installed_version
    $sameMajor = @($matched | Where-Object { $_.version.Major -eq $installedVersion.Major })
    if (@($sameMajor).Count -eq 0) { throw "No release on major line $($installedVersion.Major) found among matched tags for $($c.releases_from.repo) — installed version may be off the tracked line entirely" }

    $current = $sameMajor | Sort-Object version -Descending | Select-Object -First 1
    $behind = @($sameMajor | Where-Object { $_.version -gt $installedVersion })

    $otherMajors = @($matched | Where-Object { $_.version.Major -ne $installedVersion.Major } | Sort-Object version -Descending)
    $newerLine = $null
    if (@($otherMajors).Count -gt 0 -and $otherMajors[0].version.Major -gt $installedVersion.Major) {
      $newerLine = $otherMajors[0].tag_name
    }

    [PSCustomObject]@{
      id                  = $c.id
      ok                  = $true
      error               = $null
      installed_version   = $instRec.installed_version
      current_version     = $current.tag_name
      releases_behind     = @($behind).Count
      minor_boundary_crossed = ($current.version.Minor -ne $installedVersion.Minor)
      release_url         = $current.html_url
      newer_major_line_exists = $newerLine
    }
  }
  catch {
    [PSCustomObject]@{ id = $c.id; ok = $false; error = $_.Exception.Message }
  }
}

$record = [PSCustomObject]@{
  run_id     = $RunId
  timestamp  = (Get-Date).ToString('o')
  components = $results
}

$outPath = Join-Path $runDir 'releases.json'
$json = $record | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)

Write-Output $json
Write-Output "Written to $outPath"

$failed = @($results | Where-Object { -not $_.ok })
if ($failed.Count -gt 0) {
  Write-Output "STOP: $($failed.Count) component(s) failed to resolve a current version: $(($failed.id) -join ', ')"
  exit 1
}
exit 0
