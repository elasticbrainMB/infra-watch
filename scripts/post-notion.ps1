# Mirrors one component's records\assessments\<id>.md file to a row (page) in
# the "Infra-Watch - Component Assessments" Notion database, upserted on the
# Component property. Disk is the source of truth, Notion is a mirror - this
# script's only job is to make one Notion page match one file already on
# disk; it never decides a verdict and never invents a field.
#
# Never fails the run that calls it, same principle as post-discord.ps1: a
# run must succeed with Notion unreachable. Every failure here is caught,
# reported to stdout, and exits non-zero without throwing upward - run-check
# .ps1 calls this per assessed component and does not gate on its exit code.
#
# Field mapping and page-body structure follow PLAN-notion-board-v1.1.md.
# Uses Notion-Version 2022-06-28 (single-source classic database/page
# endpoints) - deliberately not the newer data-source-aware endpoints, since
# this database has exactly one data source and the classic endpoints are
# the more stable long-term target for a personal integration token.
param(
  [Parameter(Mandatory)][string]$RunId,
  [Parameter(Mandatory)][string]$ComponentId,
  [string]$AssessmentsDir = 'C:\automation\infra-watch\records\assessments',
  [string]$ConfigPath = 'C:\automation\infra-watch\config\notion.json'
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$secretsFile = 'C:\automation\secrets\infra-watch.env'
$tmpDir = Join-Path $env:TEMP 'infra-watch-post-notion'

function Get-EnvValue {
  param([string]$Path, [string]$Name)
  foreach ($line in Get-Content $Path -Encoding utf8) {
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    if ($line.Substring(0, $idx) -ceq $Name) { return $line.Substring($idx + 1) }
  }
  throw "Name '$Name' not found in $Path"
}

function Invoke-NotionApi {
  param(
    [Parameter(Mandatory)][string]$Method,
    [Parameter(Mandatory)][string]$Url,
    [string]$BodyJson,
    [Parameter(Mandatory)][string]$ApiKey,
    [Parameter(Mandatory)][string]$NotionVersion
  )
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $tmpHeader = Join-Path $tmpDir "hdr-$([guid]::NewGuid()).txt"
  $tmpBody = $null
  $headerLines = @(
    "header = `"Authorization: Bearer $ApiKey`""
    "header = `"Notion-Version: $NotionVersion`""
    "header = `"Content-Type: application/json`""
  )
  [System.IO.File]::WriteAllText($tmpHeader, (($headerLines -join "`n") + "`n"), $utf8NoBom)

  $curlArgs = @('-s', '-w', "`n%{http_code}", '-X', $Method, '-K', $tmpHeader)
  if ($BodyJson) {
    $tmpBody = Join-Path $tmpDir "body-$([guid]::NewGuid()).json"
    [System.IO.File]::WriteAllText($tmpBody, $BodyJson, $utf8NoBom)
    $curlArgs += @('-d', "@$tmpBody")
  }
  $curlArgs += $Url

  try {
    $raw = & curl.exe @curlArgs
    $curlExit = $LASTEXITCODE
  } finally {
    Remove-Item $tmpHeader -Force -ErrorAction SilentlyContinue
    if ($tmpBody) { Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue }
  }

  if ($curlExit -ne 0) { throw "curl.exe failed reaching Notion ($Method $Url), exit code $curlExit" }

  $rawLines = $raw -split "`n"
  $httpCode = $rawLines[-1]
  $bodyText = ($rawLines[0..($rawLines.Count - 2)] -join "`n")

  if ($httpCode -notmatch '^2\d\d$') {
    throw "Notion API returned HTTP ${httpCode} for ${Method} ${Url}: $bodyText"
  }
  if ($bodyText.Trim()) { return ($bodyText | ConvertFrom-Json) }
  return $null
}

try {
  $assessPath = Join-Path $AssessmentsDir "$ComponentId.md"
  if (-not (Test-Path $assessPath)) { throw "No assessment file for '$ComponentId': $assessPath" }
  $text = [System.IO.File]::ReadAllText($assessPath, [Text.Encoding]::UTF8)

  if (-not (Test-Path $ConfigPath)) { throw "Notion config missing: $ConfigPath" }
  $notionConfig = Get-Content $ConfigPath -Encoding utf8 -Raw | ConvertFrom-Json
  $databaseId = $notionConfig.database_id
  $notionVersion = $notionConfig.notion_version
  if (-not $databaseId) { throw "'database_id' missing from $ConfigPath" }
  if (-not $notionVersion) { throw "'notion_version' missing from $ConfigPath" }
  $apiKey = Get-EnvValue -Path $secretsFile -Name 'NOTION_API_KEY'

  $dotAllOpt = [System.Text.RegularExpressions.RegexOptions]::Singleline
  $noneOpt = [System.Text.RegularExpressions.RegexOptions]::None

  function Get-Field {
    param([string]$Pattern, [switch]$DotAll)
    $opts = if ($DotAll) { $dotAllOpt } else { $noneOpt }
    $m = [regex]::Match($text, $Pattern, $opts)
    if (-not $m.Success) { throw "Could not parse required field from ${assessPath} (pattern: $Pattern)" }
    return $m.Groups[1].Value.Trim()
  }

  $fileComponentId  = Get-Field '\|\s*Component\s*\|\s*`([^`]+)`\s*\|'
  if ($ComponentId -cne $fileComponentId) {
    throw "Component id in $assessPath ('$fileComponentId') does not match -ComponentId '$ComponentId'"
  }

  $display          = Get-Field '(?m)^# (.+?) — '
  $installedVersion = Get-Field '\|\s*Installed version\s*\|\s*`([^`]+)`\s*\|'
  $currentVersion   = Get-Field '\|\s*Current version \(installed''s own major line\)\s*\|\s*`([^`]+)`\s*\|'
  $releasesBehind   = [int](Get-Field '\|\s*Releases behind\s*\|\s*(\d+)\s*\|')
  $minorCrossedTxt  = Get-Field '\|\s*Minor boundary crossed\s*\|\s*(True|False)\s*\|'
  $minorCrossed     = ($minorCrossedTxt -eq 'True')
  $newerMajor       = Get-Field '\|\s*Newer major/track exists \(uncounted\)\s*\|\s*(.+?)\s*\|'
  $blastRadius      = Get-Field '\|\s*`blast_radius`\s*\|\s*(\w+)\s*\|'
  $assessDate       = Get-Field '_Assessment written (\d{4}-\d{2}-\d{2}), run `[^`]+`\._'
  $assessRunId      = Get-Field '_Assessment written \d{4}-\d{2}-\d{2}, run `([^`]+)`\._'
  $verdict          = Get-Field '(?m)^## Verdict: `(do-now|schedule|defer|current)`\s*$'
  $why              = Get-Field '## Verdict: `(?:do-now|schedule|defer|current)`\r?\n\r?\n(.+?)\r?\n\r?\n## What it will take' -DotAll
  $whatItWillTake   = Get-Field '## What it will take\r?\n\r?\n(.+?)\r?\n\r?\n## Source' -DotAll
  $sourceUrl        = Get-Field '(?:Raw release notes this verdict was drawn from|Current release):\s*(\S+)'

  $properties = @{
    'Name'                       = @{ title = @(@{ text = @{ content = $display } }) }
    'Component'                  = @{ select = @{ name = $ComponentId } }
    'Installed version'          = @{ rich_text = @(@{ text = @{ content = $installedVersion } }) }
    'Current version'            = @{ rich_text = @(@{ text = @{ content = $currentVersion } }) }
    'Releases behind'            = @{ number = $releasesBehind }
    'Minor boundary crossed'     = @{ checkbox = $minorCrossed }
    'Newer major/track exists'   = @{ rich_text = @(@{ text = @{ content = $newerMajor } }) }
    'Blast radius'               = @{ select = @{ name = $blastRadius } }
    'Verdict'                    = @{ select = @{ name = $verdict } }
    'Assessment date'            = @{ date = @{ start = $assessDate } }
    'Run ID'                     = @{ rich_text = @(@{ text = @{ content = $assessRunId } }) }
    'Source URL'                 = @{ url = $sourceUrl }
  }

  $children = @(
    @{ object = 'block'; type = 'heading_2'; heading_2 = @{ rich_text = @(
        @{ type = 'text'; text = @{ content = 'Verdict: ' } }
        @{ type = 'text'; text = @{ content = $verdict }; annotations = @{ code = $true } }
      ) } }
    @{ object = 'block'; type = 'paragraph'; paragraph = @{ rich_text = @(@{ type = 'text'; text = @{ content = $why } }) } }
    @{ object = 'block'; type = 'heading_2'; heading_2 = @{ rich_text = @(@{ type = 'text'; text = @{ content = 'What it will take' } }) } }
    @{ object = 'block'; type = 'paragraph'; paragraph = @{ rich_text = @(@{ type = 'text'; text = @{ content = $whatItWillTake } }) } }
    @{ object = 'block'; type = 'paragraph'; paragraph = @{ rich_text = @(@{ type = 'text'; text = @{ content = 'Raw release notes this verdict was drawn from'; link = @{ url = $sourceUrl } } }) } }
    @{ object = 'block'; type = 'callout'; callout = @{
        icon = @{ type = 'emoji'; emoji = "`u{26A0}`u{FE0F}" }
        rich_text = @(
          @{ type = 'text'; text = @{ content = "This verdict is a model's reading of the release notes, not a substitute for Matt's own judgment. " } }
          @{ type = 'text'; text = @{ content = 'blast_radius' }; annotations = @{ code = $true } }
          @{ type = 'text'; text = @{ content = ' was declared by Matt in ' } }
          @{ type = 'text'; text = @{ content = 'inventory.json' }; annotations = @{ code = $true } }
          @{ type = 'text'; text = @{ content = "; everything else on this page is the model's assessment of the change itself." } }
        )
      } }
  )

  $queryBody = @{ filter = @{ property = 'Component'; select = @{ equals = $ComponentId } }; page_size = 1 } | ConvertTo-Json -Depth 10 -Compress
  $queryResult = Invoke-NotionApi -Method 'POST' -Url "https://api.notion.com/v1/databases/$databaseId/query" -BodyJson $queryBody -ApiKey $apiKey -NotionVersion $notionVersion

  if (@($queryResult.results).Count -gt 0) {
    $pageId = $queryResult.results[0].id

    $updateBody = @{ properties = $properties } | ConvertTo-Json -Depth 10 -Compress
    Invoke-NotionApi -Method 'PATCH' -Url "https://api.notion.com/v1/pages/$pageId" -BodyJson $updateBody -ApiKey $apiKey -NotionVersion $notionVersion | Out-Null

    # Wipe and rewrite the body in place - same "overwrite, don't append"
    # behavior as records\assessments\<id>.md itself getting overwritten.
    # DELETE archives each top-level block; none of ours have nested
    # children, so archiving the top-level set is sufficient.
    $existingChildren = Invoke-NotionApi -Method 'GET' -Url "https://api.notion.com/v1/blocks/$pageId/children?page_size=100" -ApiKey $apiKey -NotionVersion $notionVersion
    foreach ($block in @($existingChildren.results)) {
      Invoke-NotionApi -Method 'DELETE' -Url "https://api.notion.com/v1/blocks/$($block.id)" -ApiKey $apiKey -NotionVersion $notionVersion | Out-Null
    }

    $appendBody = @{ children = $children } | ConvertTo-Json -Depth 10 -Compress
    Invoke-NotionApi -Method 'PATCH' -Url "https://api.notion.com/v1/blocks/$pageId/children" -BodyJson $appendBody -ApiKey $apiKey -NotionVersion $notionVersion | Out-Null

    Write-Output "Updated existing Notion page for '$ComponentId' ($pageId)."
  } else {
    $createBody = @{ parent = @{ database_id = $databaseId }; properties = $properties; children = $children } | ConvertTo-Json -Depth 10 -Compress
    $created = Invoke-NotionApi -Method 'POST' -Url 'https://api.notion.com/v1/pages' -BodyJson $createBody -ApiKey $apiKey -NotionVersion $notionVersion
    Write-Output "Created new Notion page for '$ComponentId' ($($created.id))."
  }
  exit 0
}
catch {
  # A failed Notion sync never fails the run that called it: report and exit non-zero, never throw upward.
  Write-Output "NOTION SYNC FAILED (component: $ComponentId): $($_.Exception.Message)"
  exit 1
}
