# r2: Stable release resolver correction (2026-11-04)

## Failure observed

In GitHub Actions logs_113207756438.zip, script `scripts/resolve.ps1` line 14 failed with `No suitable stable upstream release` after shared action verification and two independent ZIP tests passed. The workflow never started app download or launcher compilation. GitHub lists a valid stable v2026.3.3 release.

## Root cause and correction

`Invoke-RestMethod` emits JSON arrays as a single object through the PowerShell pipeline. The original release-list filter applied `Where-Object` to this array instead of enumerating every release. See Microsoft PowerShell documentation on `Invoke-RestMethod` array behavior.

New logic: query GitHub `/releases/latest` first; validate stable release tag and availability of `UniGetUI.x64.zip`; if latest is not suitable (or GitHub returns 404), query release history and recursively check array elements. Reject drafts, prereleases, version suffixes, and releases without the official ZIP. Preserve the existing checksum, source commit, and publisher checks.

## Code changed

- `scripts/resolve.ps1`: stable API and explicit fallback.
- `scripts/release-policy.ps1`: source-independent release selection helper.
- `tests/test-release-policy.ps1`: simulated JSON release responses, including nested arrays, invalid tags, drafts and prereleases.
- `.github/workflows/build-portableapps.yml`: runs PowerShell regression tests, increments builder revision to b2.
- `scripts/build-stage.ps1`: matches b2 revision.
- `README.md` and `docs/TROUBLESHOOTING.md`: revision instructions.

## Test evidence

Local Linux environment: Python ZIP tests 2/2 passed; YAML parsed; revision and pinned action checks passed. PowerShell regression test is provided but has **not been executed locally**, since pwsh is not installed here. A full GitHub Actions Windows run and GUI portability acceptance are **still required**.

## User instructions

Copy all extracted files into the root of your *existing* builder repository, overwriting older builder source only. Commit to `main` in GitHub Desktop, push, and run `Build UniGetUI PortableApps (x64)` with `build_method=release-zip` and `upstream_version` blank. Review Actions output; a success is not claimed until the Windows run completes.
