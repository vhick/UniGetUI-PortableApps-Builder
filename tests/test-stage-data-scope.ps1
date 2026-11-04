# Regression test: nested upstream App/.../Data must not be confused with root portable Data.
# This test runs on a standard GitHub-hosted Windows x64 runner without launching a GUI.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("UniGetUI-stage-data-scope-" + [guid]::NewGuid().ToString('N'))
$root = Join-Path $fixture 'UniGetUIPortable'
$validator = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/validate-stage.ps1'
try {
  $app = Join-Path $root 'App/UniGetUI'
  $assets = Join-Path $app 'Assets/Data'
  $info = Join-Path $root 'App/AppInfo'
  $portableData = Join-Path $root 'Data'
  @($assets, $info, $portableData, (Join-Path $root 'Other')) | ForEach-Object {
    New-Item -Path $_ -ItemType Directory -Force | Out-Null
  }
  $windowsExe = Join-Path $env:WINDIR 'System32/where.exe'
  if (-not (Test-Path -LiteralPath $windowsExe -PathType Leaf)) {
    throw 'Cannot locate Windows System32 where.exe for the PE validation fixture.'
  }
  Copy-Item -LiteralPath $windowsExe -Destination (Join-Path $root 'UniGetUIPortable.exe')
  Copy-Item -LiteralPath $windowsExe -Destination (Join-Path $app 'UniGetUI.exe')
  [IO.File]::WriteAllText((Join-Path $app 'ForceUniGetUIPortable'), '')
  [IO.File]::WriteAllText((Join-Path $assets 'Contributors.list'), 'Upstream application resource')
  foreach ($icon in @('appicon.ico','appicon_16.png','appicon_32.png')) {
    [IO.File]::WriteAllText((Join-Path $info $icon), 'test icon exists')
  }
  @'
[Format]
Type=PortableApps.comFormat
Version=3.9
[Details]
AppID=UniGetUIPortable-test
[Version]
PackageVersion=2026.3.3.0
[Control]
Start=UniGetUIPortable.exe
'@ | Set-Content -LiteralPath (Join-Path $info 'appinfo.ini') -Encoding ascii

  # Accepted: the official application contains nested App/UniGetUI/Assets/Data.
  & $validator -Root $root
  if (-not (Test-Path -LiteralPath (Join-Path $assets 'Contributors.list'))) {
    throw 'Stage validation unexpectedly modified an official application resource.'
  }

  # Rejected: genuine user data accidentally staged for release.
  $privateFile = Join-Path $portableData 'private.txt'
  [IO.File]::WriteAllText($privateFile, 'Never include personal files in release')
  $rejected = $false
  try { & $validator -Root $root } catch {
    if ($_.Exception.Message -notmatch 'Shipping user Data is prohibited') { throw }
    $rejected = $true
  }
  if (-not $rejected) { throw 'Validator incorrectly accepted a root Data file.' }
  Remove-Item -LiteralPath $privateFile -Force

  # Rejected: new empty folders in the root Data directory are user data too.
  $emptyTree = Join-Path $portableData 'empty/inner'
  New-Item -Path $emptyTree -ItemType Directory -Force | Out-Null
  $rejected = $false
  try { & $validator -Root $root } catch {
    if ($_.Exception.Message -notmatch 'Shipping user Data is prohibited') { throw }
    $rejected = $true
  }
  if (-not $rejected) { throw 'Validator incorrectly accepted an empty root Data folder tree.' }
  Write-Host 'PASS: official Assets/Data preserved; root Data files and empty directory trees rejected.'
} finally {
  if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
