param([Parameter(Mandatory)][string]$Installer,[Parameter(Mandatory)][string]$Sha256)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) { throw "Shared packager did not produce installer: $Installer" }
if (-not $Installer.EndsWith('.paf.exe', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected shared packager output format.' }
if ((Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash -ine $Sha256) { throw 'Installer SHA-256 does not match shared packager output.' }
$f = [IO.File]::OpenRead($Installer)
try {
  $r=[IO.BinaryReader]::new($f)
  if($r.ReadUInt16() -ne 0x5A4D) { throw 'Installer is not an EXE.' }
  $f.Position=0x3c; $offset=$r.ReadInt32()
  if($offset -lt 64 -or $offset -gt $f.Length-6) { throw 'Invalid installer PE offset.' }
  $f.Position=$offset
  if($r.ReadUInt32() -ne 0x4550) { throw 'Invalid installer PE signature.' }
} finally { $f.Dispose() }
$sidecar = "$Installer.json"
if (-not (Test-Path -LiteralPath $sidecar)) { throw 'Packager provenance JSON missing.' }
$detail = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json
if ($detail.engine -ne 'custom-nsis' -or $detail.provenance -ne 'independent-nsis') { throw 'Installer provenance/engine mismatch; no silent fallback allowed.' }
if ($detail.sha256 -ine $Sha256) { throw 'Installer provenance hash mismatch.' }
Write-Host "VALIDATED independent NSIS installer: $Installer"
