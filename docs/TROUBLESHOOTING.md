## r4 stage validator reports `Unexpected Data payload` on `Assets\Data\Contributors.list`

The official UniGetUI portable ZIP contains resources under `App\UniGetUI\Assets\Data`. r4 misclassified any directory named `Data` as personal user storage. r5 only requires `UniGetUIPortable\Data` to be empty in the staged release, retaining all official upstream resource files and empty folders. The Windows offline test `tests/test-stage-data-scope.ps1` prevents the same mistake from returning. Do not manually delete `Contributors.list` or other application assets.

# Troubleshooting

**Action does not show in GitHub:** Ensure `.github/workflows/build-portableapps.yml` is at the repository root, not inside an extra extracted directory. Commit and push with GitHub Desktop. Check Settings > Actions for repository policy.

**No stable release:** GitHub may be rate-limited or latest release may be a prerelease. Enter a verified stable `YYYY.N.N` upstream version manually. Do not switch to prerelease automatically.

**Source compilation fails:** `source-compile` is an experimental advanced option. Retry `release-zip` for official checksum-verified upstream x64 portable binaries. The *launcher* is always compiled in either method.

**NativeAOT launcher fails:** Review the .NET 10 setup and Windows C++ build tools from the hosted runner. Do not replace the EXE with a script or bypass antivirus. Check all compiler errors in the log.

**Shared packager fails:** Keep the valid ZIP locally in that Windows job but do not claim the release is complete. Investigate shared action logs; do not silently change engine or create a competing installer.

**PortableApps Menu does not show UniGetUI:** Correct path is `PortableApps/UniGetUIPortable/UniGetUIPortable.exe`. Refresh App Icons. Do not run `App/UniGetUI/UniGetUI.exe` as the main portable launcher.

**Settings are missing after migrating from normal UniGetUI:** New portable storage intentionally starts empty. Upstream can offer migration of `Configuration` and `InstallationOptions` from `%LOCALAPPDATA%\UniGetUI`. Back up both locations first. Never let TraceGuard move a previous installed user's whole profile.

**App stores data in LocalAppData:** Confirm the `ForceUniGetUIPortable` marker exists next to the actual UniGetUI.exe and the portable folder is writable. Upstream documents silent fallback when portable settings cannot be written.

**Launcher says another instance is running:** Close UniGetUI launched from this portable folder. The launcher uses a location-specific Windows mutex and upstream may also enforce its own single-instance limit.

**Crash / stuck files:** Do not immediately reinstall. Restart the root launcher so it can recover `App/UniGetUI/Settings` and the interrupted TraceGuard journal. Inspect `Data/TraceGuard/launcher.log` and `Conflicts`. Do not delete `session.json` or `App/UniGetUI/Settings` manually.

**New empty directories were not captured:** Only application-specific monitored scopes and portable settings are eligible. Other system-wide directories or pre-existing host paths are protected. See `docs/PORTABILITY-AUDIT.md`.

**Installer or antivirus flags unsigned software:** This custom NativeAOT launcher and independent NSIS installer may be unsigned. Verify release checksums, source and build logs. Do not disable Defender or add exclusions. False-positive resolution requires legitimate vendor review / signing.

**ZIP extraction upgrades leave obsolete files:** A ZIP copied over a working tree does not remove old App files. Prefer the shared NSIS installer for upgrades. Always retain the `Data` directory and check the old application is closed.

**Package-only workflow cannot find ZIP:** Enter the source release tag of a completed release from the full builder, with `SHA256SUMS.txt`, exactly one `UniGetUIPortable_...zip`, and no unpublished/draft releases. Package-only creates a separate new release tag because the shared publisher intentionally refuses conflicting existing assets.


## r2: GitHub reports no suitable stable release even though one exists

The original b1 resolver used `@(Invoke-RestMethod .../releases)` piped to `Where-Object`. PowerShell can pass the JSON release array as one object, causing the predicate to reject the entire set. r2 uses `.../releases/latest` and checks the release history with explicit array traversal. The Windows workflow now runs `tests/test-release-policy.ps1` before requesting release binaries. Leave `upstream_version` blank for latest stable, or specify `2026.3.3` to select that tag explicitly.


## r3 Windows TraceGuard step reports PASS but GitHub Actions still fails

The launcher uses Windows GUI subsystem (`OutputType=WinExe`), which does not reliably set PowerShell's `$LASTEXITCODE` after direct `&` invocation. The r3 runner therefore printed a self-test PASS and then threw `Native launcher TraceGuard tests failed.` The r4 workflow uses `Start-Process -Wait -PassThru`, checks the returned Process `.ExitCode`, and first checks a deliberate exit code `7` to catch test-runner mistakes. Keep the launcher as `WinExe` for PortableApps Menu compatibility; do not convert to a console app to work around this issue.

## PowerShell folders under LocalAppData

`PSResourceGet` and `PackageManagement` are shared Microsoft PowerShell storage, **not exclusive UniGetUI files**. In r6, a root that already exists at launcher startup is deliberately protected. New roots can be captured after app exit when their contents can be verified, except for installed PackageManagement provider assemblies. See `docs/R6-POWERSHELL-TRACEGUARD.md` and run `./scripts/report-powershell-state.ps1` for a read-only report. Never blindly delete a folder containing `ProviderAssemblies`, and do not redirect all of `%LOCALAPPDATA%` to PortableApps.


**r6 Windows failure: `Unverified PowerShell state` during `--traceguard-powershell-self-test`:** The r6 synthetic test set an updated file two seconds into the future and then expected the earlier-timestamped crash fixture to overwrite it. r7 corrects fixture timestamps instead of relaxing production data-safety checks. See `docs/R7-POWERSHELL-TEST-FIX.md`.
