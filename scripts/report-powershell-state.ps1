# Read-only host state inspection. Does not delete, move, import or change files.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$local = [Environment]::GetFolderPath('LocalApplicationData')
$names = @('PSResourceGet', 'PackageManagement')
Write-Host 'UniGetUI portable trace inspection (read only)'
Write-Host 'Close UniGetUI and other PowerShell package-manager operations before interpreting the result.'
foreach ($name in $names) {
  $path = Join-Path $local $name
  Write-Host "`nPath: $path"
  if (-not (Test-Path -LiteralPath $path -PathType Container)) {
    Write-Host 'Status: Absent'; continue
  }
  Write-Host 'Status: Present (existing host PowerShell state; not safe to remove automatically)'
  $all = @(Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction Stop)
  $files = @($all | Where-Object { -not $_.PSIsContainer })
  $dirs = @($all | Where-Object { $_.PSIsContainer })
  Write-Host "File count: $($files.Count); folder count: $($dirs.Count)"
  if ($name -eq 'PSResourceGet') {
    $repo = Join-Path $path 'PSResourceRepository.xml'
    Write-Host "PowerShell repository settings file: $(Test-Path -LiteralPath $repo)"
  } else {
    $provider = Join-Path $path 'ProviderAssemblies'
    $installed = (Test-Path -LiteralPath $provider -PathType Container) -and (@(Get-ChildItem -LiteralPath $provider -File -Recurse -Force).Count -gt 0)
    Write-Host "Installed provider assemblies detected: $installed"
    if ($installed) { Write-Warning 'DO NOT move or delete installed provider assemblies; other PowerShell applications may require them.' }
  }
}
Write-Host "`nThis report does not attribute file creation to UniGetUI or authorize deleting these shared directories."
