param([ValidateSet('release-zip','source-compile')][string]$Method = 'release-zip', [string]$BuilderRevision = 'b2')
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$meta = Get-Content -LiteralPath work/resolved.json -Raw | ConvertFrom-Json
$source = Join-Path (Get-Location) 'work/upstream'
$appDir = Join-Path (Get-Location) 'work/UniGetUIPortable/App/UniGetUI'
$root = Join-Path (Get-Location) 'work/UniGetUIPortable'
$dist = Join-Path (Get-Location) 'dist'
New-Item -ItemType Directory -Force $source,$appDir,$dist | Out-Null
if ($Method -eq 'release-zip') {
  $download = Join-Path (Get-Location) 'work/UniGetUI.x64.zip'
  Invoke-WebRequest -Uri $meta.zip_url -OutFile $download -Headers @{ 'User-Agent'='UniGetUI-PortableApps-Builder' }
  $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -cne $meta.sha256) { throw "Official portable ZIP checksum mismatch: expected $($meta.sha256), got $actual" }
  Expand-Archive -LiteralPath $download -DestinationPath $source -Force
  $exes = @(Get-ChildItem -LiteralPath $source -Recurse -Filter UniGetUI.exe -File)
  if ($exes.Count -ne 1) { throw "Expected exactly one upstream UniGetUI.exe; found $($exes.Count)" }
  $binaryRoot = $exes[0].Directory.FullName
  # -LiteralPath does not wildcard; copy each top-level item explicitly instead.
  Get-ChildItem -LiteralPath $binaryRoot -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $appDir -Recurse -Force }
} else {
  & git clone --depth 1 --branch $meta.tag https://github.com/Devolutions/UniGetUI.git 'work/upstream-source'
  if ($LASTEXITCODE -ne 0) { throw 'Upstream source clone failed.' }
  Push-Location 'work/upstream-source'
  try {
    $commit = (& git rev-parse HEAD).Trim()
    if ($commit -cne $meta.commit) { throw "Upstream source commit changed: $commit" }
    & dotnet restore src/UniGetUI.Windows.slnx /p:Platform=x64
    if ($LASTEXITCODE -ne 0) { throw 'Upstream NuGet restore failed.' }
    $outPath = Join-Path (Get-Location) '../upstream-compiled'
    & dotnet publish src/UniGetUI.Avalonia/UniGetUI.Avalonia.csproj -c Release -r win-x64 --self-contained true /p:Platform=x64 "/p:PublishDir=$outPath/"
    if ($LASTEXITCODE -ne 0) { throw 'Upstream source publish failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $outPath 'UniGetUI.exe'))) { throw 'Source-built UniGetUI.exe not found.' }
    & pwsh -NoProfile -File scripts/generate-integrity-tree.ps1 -Path $outPath -MinOutput
    if ($LASTEXITCODE -ne 0) { throw 'Upstream integrity tree creation failed.' }
    Get-ChildItem -LiteralPath $outPath -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $appDir -Recurse -Force }
  } finally { Pop-Location }
}
if (-not (Test-Path -LiteralPath (Join-Path $appDir 'UniGetUI.exe'))) { throw 'Missing real upstream executable.' }
# Do not include any persistent runtime Settings in App; no build-time personal data may ship.
$settings = Join-Path $appDir 'Settings'
if (Test-Path $settings) {
  if (@(Get-ChildItem -LiteralPath $settings -Force).Count -gt 0) { throw 'Upstream payload unexpectedly contains populated Settings. Refusing to package possible user data.' }
  Remove-Item -LiteralPath $settings -Force
}
$marker = Join-Path $appDir 'ForceUniGetUIPortable'
if (-not (Test-Path $marker)) { [IO.File]::WriteAllText($marker,'') }
# Inspect PE header and Windows architecture before copying its authentic branding.
$pe = [IO.File]::OpenRead((Join-Path $appDir 'UniGetUI.exe'))
try {
  $br=[IO.BinaryReader]::new($pe)
  if ($br.ReadUInt16() -ne 0x5A4D) { throw 'Upstream EXE is not a Windows PE.' }
  $pe.Position=0x3c; $off=$br.ReadInt32(); $pe.Position=$off
  if ($br.ReadUInt32() -ne 0x4550 -or $br.ReadUInt16() -ne 0x8664) { throw 'Upstream EXE is not an x64 Windows PE.' }
} finally { $pe.Dispose() }
Add-Type -AssemblyName System.Drawing.Common
$ico = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $appDir 'UniGetUI.exe'))
if (-not $ico) { throw 'Cannot extract official UniGetUI icon from upstream EXE.' }
$appInfo = Join-Path $root 'App/AppInfo'
New-Item -ItemType Directory -Force $appInfo,(Join-Path $appInfo 'Launcher'),(Join-Path $root 'Other/Source'),(Join-Path $root 'Data') | Out-Null
try {
  $icoPath = Join-Path $appInfo 'appicon.ico'
  $fs=[IO.File]::Create($icoPath); try { $ico.Save($fs) } finally { $fs.Dispose() }
  foreach($n in @(16,32)) {
    $iconSize=[System.Drawing.Icon]::new($ico, $n, $n)
    try { $bitmap=$iconSize.ToBitmap(); try { $bitmap.Save((Join-Path $appInfo "appicon_$n.png"), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() } } finally { $iconSize.Dispose() }
  }
} finally { $ico.Dispose() }
Copy-Item -LiteralPath (Join-Path $appInfo 'appicon.ico') -Destination 'src/UniGetUIPortable/brand.ico' -Force
& dotnet publish src/UniGetUIPortable/UniGetUIPortable.csproj -c Release -r win-x64 --self-contained true -o work/launcher /p:PublishAot=true
if ($LASTEXITCODE -ne 0) { throw 'NativeAOT launcher build failed.' }
$launcher = Join-Path (Get-Location) 'work/launcher/UniGetUIPortable.exe'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'No real compiled launcher output.' }
Copy-Item -LiteralPath $launcher -Destination (Join-Path $root 'UniGetUIPortable.exe')
$pv = @($meta.version.Split('.') + @('0')) -join '.'
# Distinguish independent builds from official publisher-owned AppIDs.
$owner = if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { 'independent' }
$owner = $owner -replace '[^a-zA-Z0-9_-]', ''
if (-not $owner) { throw 'Cannot derive unique package publisher ID.' }
$appId = "UniGetUIPortable-$owner"
$builderHomepage = if ($env:GITHUB_REPOSITORY) { "https://github.com/$env:GITHUB_REPOSITORY" } else { 'https://github.com/Devolutions/UniGetUI' }
$ini = @"
[Format]
Type=PortableApps.comFormat
Version=3.9

[Details]
Name=UniGetUI Portable
AppID=$appId
Publisher=Devolutions
Homepage=$builderHomepage
Category=Utilities
Description=GUI for Windows package managers; independently packaged portable distribution
Language=Multilingual
Requires64bitOS=yes

[License]
Shareable=true
OpenSource=true
Freeware=true
CommercialUse=true
EULAVersion=1

[Version]
PackageVersion=$pv
DisplayVersion=$($meta.version) ($BuilderRevision)

[Control]
Start=UniGetUIPortable.exe
"@
$ini | Set-Content -LiteralPath (Join-Path $appInfo 'appinfo.ini') -Encoding ascii
@'
; Documentation only. The genuine launcher is root UniGetUIPortable.exe
; compiled from src/UniGetUIPortable, not a PAL binary.
[Launch]
ProgramExecutable=UniGetUI\UniGetUI.exe
'@ | Set-Content -LiteralPath (Join-Path $appInfo 'Launcher/UniGetUIPortable.ini') -Encoding ascii
Copy-Item legal/LAUNCHER-LICENSE.txt (Join-Path $root 'Other/Source/LAUNCHER-LICENSE.txt')
Copy-Item legal/UPSTREAM-LICENSE.txt (Join-Path $root 'Other/Source/UPSTREAM-LICENSE.txt')
[ordered]@{ upstream_version=$meta.version; upstream_tag=$meta.tag; upstream_commit=$meta.commit; upstream_zip_sha256=$meta.sha256; method=$Method; launcher_revision=$BuilderRevision; packager='vhick/Portable-Package-Builder@v1.0.0'; publisher='vhick/portable-release-publisher@v1.1.1' } | ConvertTo-Json | Set-Content (Join-Path $root 'Other/Source/Build-Manifest.json') -Encoding utf8
Write-Host "Staged $root with upstream=$($meta.version); method=$Method"
