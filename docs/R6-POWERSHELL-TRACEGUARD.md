# r6 — Safe PowerShell LocalAppData scope handling

## Evidence and diagnosis

The user confirmed r5 builds and launches successfully, but its runtime leaves `%LOCALAPPDATA%\PSResourceGet` and `%LOCALAPPDATA%\PackageManagement`. These are **Microsoft PowerShell shared user directories**, not app-exclusive UniGetUI folders:

- `PSResourceGet\PSResourceRepository.xml` holds repository registrations; [Microsoft docs](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/supported-repositories?view=powershellget-3.x) document the exact location.
- `PackageManagement\ProviderAssemblies` may contain installed PowerShell providers; [Microsoft docs](https://learn.microsoft.com/en-us/powershell/module/packagemanagement/install-packageprovider?view=powershellget-2.x) document the exact location and CurrentUser scope.

Do not change `%LOCALAPPDATA%` globally. That would affect unrelated Windows applications and package-manager behavior. These paths are deliberately *not* classified as UniGetUI-owned data.

## r6 protection policy

1. **Already existed before launch:** Do not copy, overwrite, delete or relocate them. Do not import the host user's repositories or installed providers into the portable folder.
2. **Absent before launch and created during a monitored session:** Best-effort copy and verify into `Data\TraceGuard\External\LocalAppData_PSResourceGet` or `...\LocalAppData_PackageManagement`, then remove only the verified files and directories using *nonrecursive* deletion. Empty folders and nested empty trees are kept.
3. **PackageManagement root containing installed `ProviderAssemblies` files:** Leave it on the host even if created during the session. These are installed PowerShell-user components, not harmless disposable cache.
4. **Next launch:** If the host root is still absent and there is saved portable state, reconstruct it temporarily from `Data` before UniGetUI starts. If the host root already exists, leave it entirely untouched and do not inject portable settings.
5. **Crash recovery:** Existing `Data\TraceGuard\session.json` already journals the pre-launch state. The recovery path captures eligible new roots before beginning the next session. If copying or deletion fails (locked file, conflict, concurrent writer), the journal and source data remain for review/retry.
6. **Collision after snapshot, before restoration:** Win32 `CreateDirectoryW` claims an absent root atomically before copying saved settings. If another program created it in the meantime, skip that scope and keep the unexpected host directory. Do not overwrite it.
7. **Concurrent PowerShell processes:** Shared folder creation cannot be reliably attributed to UniGetUI at the filesystem level. If another PowerShell tool uses these roots during the same time, recovery may be skipped or fail conservatively. Avoid concurrent package-management operations when testing this launcher.

This is safer than simply adding both folder names to the normal application-owned TraceGuard scope list. It is not a guarantee that *all* PowerShell-related Windows traces can be eliminated.

## Existing folders from r5

**r6 will not automatically delete or adopt the two folders r5 already left behind.** At r6 startup they count as *pre-existing host state*. This is deliberate: a PowerShell repository registration or installed provider may be needed by other applications.

You can inspect them safely (without making changes) in PowerShell from your **builder repository**:

```powershell
./scripts/report-powershell-state.ps1
```

A non-destructive first test is to use a fresh disposable Windows user account or a Windows VM without those directories. Once no other PowerShell tools are running, launch the r6 portable app, close it, then inspect these saved copies (if any):

```
UniGetUIPortable\Data\TraceGuard\External\LocalAppData_PSResourceGet\
UniGetUIPortable\Data\TraceGuard\External\LocalAppData_PackageManagement\
```

To deal with old r5 remnants on an existing Windows user, first check whether either folder holds repository customizations or installed providers. Make a separate backup. **Do not delete or move the existing folders merely to make the portable app appear clean.** There is no safe automatic way to establish that no other applications depend on them.

## Validation

`--traceguard-powershell-self-test` uses *isolated temporary directories*, not the runner's real LocalAppData. It tests:

- new-root capture and deep empty-folder preservation;
- second-launch rehydration, changes preserved on exit;
- protection of pre-existing host settings;
- collision protection between snapshot and restore;
- preservation of installed PackageManagement providers;
- empty PackageManagement subtree capture;
- crash recovery and source cleanup.

The Windows GitHub Actions workflow must run this fixture after the original r5 TraceGuard self-test. Neither a static text test nor this synthetic test proves that real UniGetUI GUI activity has been validated. Manual post-build testing is still required.
