<#
  Downloads the NEED wiki into .\data so the website works without a proxy.

  Run it from the needutils-wiki-site folder:
      powershell -ExecutionPolicy Bypass -File build-static.ps1

  It downloads the index, categories, every article (English and Korean) and every image the
  articles refer to, then stops. To refresh the copy later, delete the data folder and run it again.
#>
param(
    [string]$Base = "http://151.145.74.228/patch/wiki/"
)

$ErrorActionPreference = "Stop"
$Base = $Base.TrimEnd('/') + '/'
$Out = Join-Path $PSScriptRoot "data"
$script:Downloaded = 0
$script:Missing = 0

# Downloads one file from the wiki server into .\data, keeping its folder layout.
# Returns $false if the server doesn't have it (English versions often don't exist).
function Save-WikiFile([string]$Rel) {
    $target = Join-Path $Out ($Rel -replace '/', '\')
    if (Test-Path $target) { return $true }

    $encoded = ($Rel -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    try {
        Invoke-WebRequest -UseBasicParsing -Uri ($Base + $encoded) -OutFile $target
        $script:Downloaded++
        return $true
    } catch {
        if (Test-Path $target) { Remove-Item $target }
        $script:Missing++
        return $false
    }
}

# 1. Index, categories and status, in both languages.
Write-Host "Downloading the index and categories..."
foreach ($f in 'articles_index.json', 'categories.json', 'server_status.json',
                'en/articles_index.json', 'en/categories.json', 'en/server_status.json') {
    Save-WikiFile $f | Out-Null
}

# 2. Every article the index lists, in both languages.
$ids = New-Object System.Collections.Generic.HashSet[string]
$extraFiles = New-Object System.Collections.Generic.HashSet[string]
foreach ($indexFile in @((Join-Path $Out 'articles_index.json'), (Join-Path $Out 'en\articles_index.json'))) {
    if (-not (Test-Path $indexFile)) { continue }
    $json = Get-Content $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = if ($json.articles) { $json.articles }
               elseif ($json.items) { $json.items }
               elseif ($json -is [array]) { $json }
               else { $json.PSObject.Properties | ForEach-Object { $_.Value } }

    foreach ($entry in $entries) {
        foreach ($key in 'id', 'article_id', 'key', 'slug', 'name') {
            if ($entry.$key) { [void]$ids.Add([string]$entry.$key); break }
        }
        foreach ($key in 'path', 'file') {
            if ($entry.$key -is [string] -and $entry.$key) { [void]$extraFiles.Add([string]$entry.$key) }
        }
    }
}

Write-Host "Downloading $($ids.Count) articles (English and Korean)..."
foreach ($id in $ids) {
    Save-WikiFile "en/articles/$id.json" | Out-Null
    Save-WikiFile "articles/$id.json" | Out-Null
}
foreach ($file in $extraFiles) { Save-WikiFile $file | Out-Null }

# 3. Every image the downloaded articles refer to. The data uses several forms: image fields,
#    inline [IMG:...] tags, and names with or without a file extension.
Write-Host "Finding images..."
$imageNames = New-Object System.Collections.Generic.HashSet[string]
$fieldPattern = '"(?:path|src|image|img|icon|file)"\s*:\s*"([^"]+)"'
$tagPattern = '\[(?:IMG|IMAGE|ICON):([^\]|]+)'
Get-ChildItem $Out -Recurse -Filter *.json | ForEach-Object {
    $text = Get-Content $_.FullName -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, $fieldPattern, 'IgnoreCase')) { [void]$imageNames.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, $tagPattern, 'IgnoreCase')) { [void]$imageNames.Add($m.Groups[1].Value.Trim()) }
}

$imageExtensions = '.png', '.jpg', '.gif', '.webp'
Write-Host "Downloading images..."
foreach ($name in $imageNames) {
    if ($name -match '^https?:') { continue }
    $imagePath = if ($name -match '/') { $name } else { "images/$name" }
    if ([System.IO.Path]::GetExtension($imagePath)) {
        Save-WikiFile $imagePath | Out-Null
    } else {
        # No extension in the data: try the common image types.
        foreach ($ext in $imageExtensions) {
            if (Save-WikiFile ($imagePath + $ext)) { break }
        }
    }
}

Write-Host ""
Write-Host "Done. Downloaded $script:Downloaded files into $Out."
Write-Host "$script:Missing lookups had nothing on the server (normal for English entries that don't exist yet)."
Write-Host "Upload index.html and the data folder to your static host."
