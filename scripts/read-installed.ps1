# Read-only. Resolves the installed version of every component in
# inventory.json against the live host and writes one JSON record. Never
# pulls, starts, stops, or otherwise changes anything it reads.
param(
  [string]$RunId,
  [string]$InventoryPath = 'C:\automation\infra-watch\config\inventory.json',
  [string]$RunsDir = 'C:\automation\infra-watch\records\runs'
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $RunId) { $RunId = Get-Date -Format 'yyyyMMdd-HHmmss' }
if (-not (Test-Path $InventoryPath)) { throw "Inventory file missing: $InventoryPath" }

$inventory = Get-Content $InventoryPath -Encoding utf8 -Raw | ConvertFrom-Json

$results = foreach ($c in $inventory.components) {
  $version = $null
  $ok = $false
  $errorMsg = $null
  $raw = $null

  try {
    switch ($c.installed_from.method) {
      'docker-label' {
        $raw = docker inspect $c.installed_from.container 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "docker inspect exited $LASTEXITCODE : $raw" }
        $inspected = ($raw | ConvertFrom-Json)[0]
        $labelName = $c.installed_from.label
        $version = $inspected.Config.Labels.($labelName)
        if (-not $version) { throw "Label '$labelName' not present on container '$($c.installed_from.container)'" }
      }
      'cli-version' {
        $raw = (Invoke-Expression "$($c.installed_from.command) 2>&1" | Out-String).Trim()
        $match = [regex]::Match($raw, $c.installed_from.extract_regex)
        if (-not $match.Success) { throw "Regex '$($c.installed_from.extract_regex)' did not match output: $raw" }
        $version = $match.Groups[1].Value
      }
      'pwsh-version-table' {
        $v = $PSVersionTable.PSVersion
        $version = "$($v.Major).$($v.Minor).$($v.Patch)"
        $raw = $PSVersionTable.PSVersion.ToString()
      }
      default { throw "Unknown installed_from.method '$($c.installed_from.method)'" }
    }

    if (-not $version -or $version -ceq 'latest') {
      throw "Installed version reads as '$version' - not a resolvable version"
    }
    $ok = $true
  }
  catch {
    $errorMsg = $_.Exception.Message
  }

  [PSCustomObject]@{
    id               = $c.id
    display          = $c.display
    kind             = $c.kind
    installed_version = $version
    ok               = $ok
    error            = $errorMsg
  }
}

$record = [PSCustomObject]@{
  run_id     = $RunId
  timestamp  = (Get-Date).ToString('o')
  components = $results
}

$outDir = Join-Path $RunsDir $RunId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir 'installed.json'
$json = $record | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)

Write-Output $json
Write-Output "Written to $outPath"

$failed = @($results | Where-Object { -not $_.ok })
if ($failed.Count -gt 0) {
  Write-Output "STOP: $($failed.Count) component(s) failed to resolve an installed version: $(($failed.id) -join ', ')"
  exit 1
}
exit 0
