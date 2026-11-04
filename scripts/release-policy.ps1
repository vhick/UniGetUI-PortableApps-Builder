# GitHub release responses sometimes arrive as one nested array object.
# Find a stable release without assuming pipeline enumeration semantics.
function Test-UniGetUIStableRelease {
  param([AllowNull()][object]$Candidate)
  if ($null -eq $Candidate -or $Candidate -is [array]) { return $false }
  if ($Candidate.PSObject.Properties['draft'] -and [bool]$Candidate.draft) { return $false }
  if ($Candidate.PSObject.Properties['prerelease'] -and [bool]$Candidate.prerelease) { return $false }
  if (-not $Candidate.PSObject.Properties['tag_name']) { return $false }
  if ([string]$Candidate.tag_name -cnotmatch '^v\d{4}\.\d+\.\d+$') { return $false }
  if (-not $Candidate.PSObject.Properties['assets']) { return $false }
  foreach ($asset in $Candidate.assets) {
    if ($null -ne $asset -and $asset.name -ceq 'UniGetUI.x64.zip') { return $true }
  }
  return $false
}
function Find-UniGetUIStableRelease {
  param([AllowNull()][object]$Candidates)
  if ($null -eq $Candidates) { return $null }
  if ($Candidates -is [array]) {
    foreach ($entry in $Candidates) {
      $result = Find-UniGetUIStableRelease -Candidates $entry
      if ($null -ne $result) { return $result }
    }
    return $null
  }
  if (Test-UniGetUIStableRelease -Candidate $Candidates) { return $Candidates }
  return $null
}
