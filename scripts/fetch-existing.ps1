param([Parameter(Mandatory)][string]$SourceTag,[Parameter(Mandatory)][string]$PackageRevision)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if ($SourceTag -notmatch '^portable-v\d{4}\.\d+\.\d+-b\d+-r\d+$') { throw 'Only this builders completed portable-v...-bN-rN release tags are trusted sources.' }
if ($PackageRevision -notmatch '^[a-zA-Z0-9_-]{1,25}$') { throw 'Invalid package revision.' }
New-Item -Force -ItemType Directory 'work/release','dist' | Out-Null
& gh release download $SourceTag --repo $env:GITHUB_REPOSITORY --dir 'work/release' --pattern '*.zip' --pattern 'SHA256SUMS.txt'
if ($LASTEXITCODE -ne 0) { throw 'Cannot download trusted source release assets.' }
$zips=@(Get-ChildItem work/release -Filter '*.zip' -File)
if ($zips.Count -ne 1) { throw 'Source release must contain exactly one ZIP.' }
$zip = $zips[0]
if ($zip.Name -notmatch '^UniGetUIPortable_(\d{4}\.\d+\.\d+)_b\d+\.zip$') { throw 'Unrecognized PortableApps archive filename.' }
$version = $Matches[1]
$sumPath='work/release/SHA256SUMS.txt'
if (-not (Test-Path $sumPath)) { throw 'Source release SHA256SUMS missing.' }
$sums=Get-Content $sumPath
$found=@($sums | Where-Object { $_ -match '^[a-f0-9]{64}  UniGetUIPortable_\d{4}\.\d+\.\d+_b\d+\.zip$' -and $_.EndsWith('  ' + $zip.Name) })
if ($found.Count -ne 1) { throw 'No exact publisher SHA-256 entry for ZIP.' }
$expected=($found[0] -split '\s+')[0]
$actual=(Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -cne $expected) { throw 'Published ZIP checksum mismatch.' }
# Expand-Archive uses .NET safe extraction (rejects paths escaping destination).
Expand-Archive -LiteralPath $zip.FullName -DestinationPath 'work' -Force
if (-not (Test-Path 'work/UniGetUIPortable/UniGetUIPortable.exe')) { throw 'Wrong ZIP root.' }
if (Test-Path 'work/UniGetUIPortable/App/UniGetUI/Settings') { throw 'Refusing to package runtime Settings stored in App.' }
Copy-Item -LiteralPath $zip.FullName -Destination 'dist' -Force
$tag = "portable-repack-v$version-$PackageRevision-$env:GITHUB_RUN_NUMBER"
if ($env:GITHUB_OUTPUT) { @("version=$version", "release_tag=$tag") | Add-Content $env:GITHUB_OUTPUT -Encoding utf8 }
Write-Host "Verified prior publisher ZIP, SHA256=$expected; output tag=$tag"
