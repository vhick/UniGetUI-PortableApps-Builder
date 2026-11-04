$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/release-policy.ps1')
function Assert([bool]$pass, [string]$message) { if (-not $pass) { throw "Release policy regression: $message" } }
$stable = [pscustomobject]@{ tag_name='v2026.3.3'; draft=$false; prerelease=$false; assets=@([pscustomobject]@{name='UniGetUI.x64.zip'}) }
$preview = [pscustomobject]@{ tag_name='v2026.3.4'; draft=$false; prerelease=$true; assets=@([pscustomobject]@{name='UniGetUI.x64.zip'}) }
$nozip = [pscustomobject]@{ tag_name='v2026.3.5'; draft=$false; prerelease=$false; assets=@([pscustomobject]@{name='UniGetUI.Installer.x64.exe'}) }
$draft = [pscustomobject]@{ tag_name='v2026.3.6'; draft=$true; prerelease=$false; assets=@([pscustomobject]@{name='UniGetUI.x64.zip'}) }
$malformed = [pscustomobject]@{ tag_name='v2026.3.7-beta'; draft=$false; prerelease=$false; assets=@([pscustomobject]@{name='UniGetUI.x64.zip'}) }
Assert (Test-UniGetUIStableRelease -Candidate $stable) 'valid stable release rejected'
foreach ($bad in @($preview,$nozip,$draft,$malformed)) { Assert (-not (Test-UniGetUIStableRelease -Candidate $bad)) "invalid release accepted: $($bad.tag_name)" }
$history = @($preview,$nozip,$draft,$malformed,$stable)
$got = Find-UniGetUIStableRelease -Candidates $history
Assert ($null -ne $got -and $got.tag_name -eq 'v2026.3.3') 'normal collection selection failed'
$nested = ,$history  # reproduce Invoke-RestMethod returning array as one pipeline item
$got = Find-UniGetUIStableRelease -Candidates $nested
Assert ($null -ne $got -and $got.tag_name -eq 'v2026.3.3') 'nested API collection selection failed'
Assert ($null -eq (Find-UniGetUIStableRelease -Candidates @($preview,$draft,$nozip))) 'invalid history should have no match'
Write-Host 'PASS: stable release selection, prerelease rejection, absent ZIP, and nested GitHub API arrays.'
