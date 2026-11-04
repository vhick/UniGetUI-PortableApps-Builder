param([string]$Version = '', [string]$BuilderRevision = 'b7', [string]$PackageRevision = 'r1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'release-policy.ps1')
$headers = @{ 'User-Agent' = 'UniGetUI-PortableApps-Builder'; 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
$api = 'https://api.github.com/repos/Devolutions/UniGetUI'
if ($Version -and $Version -notmatch '^v?\d{4}\.\d+\.\d+$') { throw 'Version must be a stable YYYY.N.N value, e.g. 2026.3.3' }
$release = $null
if ($Version) {
  $tag = 'v' + $Version.TrimStart('v')
  Write-Host "Resolving explicitly requested upstream stable tag: $tag"
  $release = Invoke-RestMethod -Uri "$api/releases/tags/$tag" -Headers $headers
} else {
  # A /releases collection is returned as an array object by Invoke-RestMethod;
  # piping that directly to Where-Object can filter the whole array as ONE item.
  # Use the dedicated latest stable release endpoint first instead.
  Write-Host 'Resolving latest stable UniGetUI release using GitHub /releases/latest.'
  try {
    $candidate = Invoke-RestMethod -Uri "$api/releases/latest" -Headers $headers
    if (Test-UniGetUIStableRelease -Candidate $candidate) { $release = $candidate }
    else { Write-Warning 'Latest release did not contain a suitable stable Windows x64 ZIP. Checking release history.' }
  }
  catch {
    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($status -ne 404) { throw }
    Write-Warning 'GitHub latest release endpoint returned 404. Checking release history.'
  }
  if ($null -eq $release) {
    # Keep the releases response intact and traverse explicitly; never filter
    # Invoke-RestMethod collection output as though it emitted one item at a time.
    $history = Invoke-RestMethod -Uri "$api/releases?per_page=100" -Headers $headers
    $release = Find-UniGetUIStableRelease -Candidates $history
  }
}
if (-not (Test-UniGetUIStableRelease -Candidate $release)) {
  throw 'No suitable stable upstream release with official UniGetUI.x64.zip. Check GitHub release assets or select a manually checked stable version.'
}
if ($release.tag_name -notmatch '^v(\d{4}\.\d+\.\d+)$') { throw 'Unexpected nonstable upstream tag.' }
$version = $Matches[1]
$asset = @($release.assets | Where-Object { $_.name -ceq 'UniGetUI.x64.zip' }) | Select-Object -First 1
if (-not $asset -or $asset.browser_download_url -notmatch '^https://github\.com/Devolutions/UniGetUI/releases/download/') { throw 'Official x64 portable ZIP missing.' }
$checksum = @($release.assets | Where-Object { $_.name -ceq 'checksums.txt' }) | Select-Object -First 1
$sha = ''
if ($asset.PSObject.Properties['digest'] -and $asset.digest -match '^sha256:([a-fA-F0-9]{64})$') { $sha = $Matches[1].ToLowerInvariant() }
if (-not $sha) {
  if (-not $checksum) { throw 'Release asset has no SHA256 digest and checksums.txt is unavailable.' }
  $tmp = Join-Path $env:RUNNER_TEMP 'unigetui-upstream-checksums.txt'
  Invoke-WebRequest -Uri $checksum.browser_download_url -OutFile $tmp -Headers $headers
  foreach ($line in Get-Content -LiteralPath $tmp) {
    if ($line -match [regex]::Escape($asset.name) -and $line -match '(?i)\b([a-f0-9]{64})\b') { $sha = $Matches[1].ToLowerInvariant(); break }
  }
  if (-not $sha) { throw 'Unable to find official ZIP SHA-256 in checksums.txt.' }
}
# Annotated tags may return both the tag object and the peeled commit. Choose the peeled SHA.
$refs = @(& git ls-remote --tags https://github.com/Devolutions/UniGetUI.git "refs/tags/$($release.tag_name)" "refs/tags/$($release.tag_name)^{}")
if ($LASTEXITCODE -ne 0 -or $refs.Count -eq 0) { throw 'Unable to resolve upstream tag to a Git commit.' }
$peeled = @($refs | Where-Object { $_ -match '\^\{\}$' }) | Select-Object -First 1
$ref = if ($peeled) { $peeled } else { $refs[0] }
$commit = ($ref -split '\s+')[0]
if ($commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid upstream tag commit.' }
$publishTag = "portable-v$version-$BuilderRevision-$PackageRevision"
$skip = $false
if ($env:GITHUB_REPOSITORY) {
  $url = "https://api.github.com/repos/$env:GITHUB_REPOSITORY/releases/tags/$publishTag"
  try {
    $prior = Invoke-RestMethod $url -Headers $headers
    $names = @($prior.assets | ForEach-Object { $_.name })
    if (-not $prior.draft -and @($names | Where-Object { $_ -like '*.zip' }).Count -gt 0 -and @($names | Where-Object { $_ -like '*.paf.exe' }).Count -gt 0) {
      Write-Host "A completed release already exists: $publishTag; no duplicate compilation needed."
      $skip = $true
    } else { throw "Tag $publishTag already exists but is incomplete/draft; stop and inspect it." }
  } catch {
    if (-not ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404)) { throw }
  }
}
$meta = [ordered]@{ version=$version; tag=$release.tag_name; commit=$commit; zip_url=$asset.browser_download_url; sha256=$sha; publish_tag=$publishTag; skip=$skip }
New-Item -ItemType Directory -Force work | Out-Null
$meta | ConvertTo-Json | Set-Content -LiteralPath 'work/resolved.json' -Encoding utf8
if ($env:GITHUB_OUTPUT) {
  @("version=$version", "tag=$($release.tag_name)", "commit=$commit", "release_tag=$publishTag", "skip=$($skip.ToString().ToLowerInvariant())") | Add-Content $env:GITHUB_OUTPUT -Encoding utf8
}
Write-Host "Upstream: $($release.tag_name) ($commit), SHA256: $sha"
