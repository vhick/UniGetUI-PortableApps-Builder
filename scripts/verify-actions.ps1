$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$actions = @(
  @{ Repo='Portable-Package-Builder'; Tag='v1.0.0'; Inputs=@('source-dir:','output-dir:','engine:','running-exe:','package-revision:'); Output='installer-file:' },
  @{ Repo='portable-release-publisher'; Tag='v1.1.1'; Inputs=@('files:','tag:','dry-run:','prune:'); Output='using: composite' }
)
foreach($a in $actions) {
  $url = "https://raw.githubusercontent.com/vhick/$($a.Repo)/$($a.Tag)/action.yml"
  $content = (Invoke-WebRequest -Uri $url -Headers @{'User-Agent'='UniGetUI-PortableApps-Builder'}).Content
  foreach($needle in @($a.Inputs)+@($a.Output)) {
    if (-not $content.Contains($needle)) { throw "Pinned shared action contract missing $needle at $url" }
  }
  $headers=@{'User-Agent'='UniGetUI-PortableApps-Builder';'Accept'='application/vnd.github+json'}
  if($env:GITHUB_TOKEN) { $headers.Authorization="Bearer $env:GITHUB_TOKEN" }
  $ref=Invoke-RestMethod "https://api.github.com/repos/vhick/$($a.Repo)/git/ref/tags/$($a.Tag)" -Headers $headers
  if ($ref.ref -ne "refs/tags/$($a.Tag)" -or $ref.object.sha -notmatch '^[a-fA-F0-9]{40}$') { throw "Invalid shared action tag $($a.Repo)" }
  Write-Host "Pinned action verified: vhick/$($a.Repo)@$($a.Tag) -> $($ref.object.sha)"
}
