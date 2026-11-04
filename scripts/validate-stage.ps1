param([string]$Root = 'work/UniGetUIPortable')
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function Must([bool]$value,[string]$message) { if (-not $value) { throw $message } }
Must (Test-Path "$Root/UniGetUIPortable.exe" -PathType Leaf) 'Missing compiled root launcher'
Must (Test-Path "$Root/App/UniGetUI/UniGetUI.exe" -PathType Leaf) 'Missing upstream application'
Must (Test-Path "$Root/App/UniGetUI/ForceUniGetUIPortable" -PathType Leaf) 'Missing portable marker'
Must (Test-Path "$Root/App/AppInfo/appicon.ico" -PathType Leaf) 'Missing official icon'
Must (Test-Path "$Root/App/AppInfo/appicon_16.png" -PathType Leaf) 'Missing 16px icon'
Must (Test-Path "$Root/App/AppInfo/appicon_32.png" -PathType Leaf) 'Missing 32px icon'
Must (Test-Path "$Root/App/AppInfo/appinfo.ini" -PathType Leaf) 'Missing metadata'
Must (Test-Path "$Root/Other" -PathType Container) 'Missing Other'
Must (Test-Path "$Root/Data" -PathType Container) 'Missing Data'
Must (-not (Test-Path "$Root/App/UniGetUI/Settings")) 'Application runtime settings must not be shipped'
# Only the PortableApps root Data directory is user-owned runtime storage.
# Upstream resources such as App/UniGetUI/Assets/Data/Contributors.list
# are legitimate application binaries/assets and MUST be packaged.
$portableData = Join-Path (Resolve-Path -LiteralPath $Root).Path 'Data'
Must (@(Get-ChildItem -LiteralPath $portableData -Force).Count -eq 0) 'Shipping user Data is prohibited'
$ini = Get-Content "$Root/App/AppInfo/appinfo.ini" -Raw
Must ($ini -match '(?m)^AppID=UniGetUIPortable-[a-zA-Z0-9_-]+\s*$') 'Wrong AppID'
Must ($ini -match '(?m)^Start=UniGetUIPortable\.exe\s*$') 'Wrong start EXE'
Must ($ini -match '(?m)^PackageVersion=\d+\.\d+\.\d+\.\d+\s*$') 'Invalid 4-component version'
Must ($ini -match '(?m)^Type=PortableApps\.comFormat\s*$') 'Wrong portable format type'
Must ($ini -match '(?m)^Version=3\.9\s*$') 'Wrong portable format version'
foreach($file in @(Get-Item $Root) + @(Get-ChildItem $Root -Recurse -Force)) {
  if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Unsafe reparse point $($file.FullName)" }
}
foreach($exe in @("$Root/UniGetUIPortable.exe", "$Root/App/UniGetUI/UniGetUI.exe")) {
  $f=[IO.File]::OpenRead((Resolve-Path $exe).Path)
  try {
    $r=[IO.BinaryReader]::new($f)
    Must ($r.ReadUInt16() -eq 0x5A4D) "Not a PE: $exe"
    $f.Position=0x3c; $off=$r.ReadInt32()
    Must ($off -gt 63 -and $off -lt $f.Length-6) "Bad PE offset: $exe"
    $f.Position=$off
    Must ($r.ReadUInt32() -eq 0x4550) "Bad PE signature: $exe"
    Must ($r.ReadUInt16() -eq 0x8664) "Not an x64 EXE: $exe"
  } finally { $f.Dispose() }
}
Write-Host 'PASS: root Win64 PE launcher, upstream Win64 PE, icon, marker, metadata, pristine Data, no reparse points.'
