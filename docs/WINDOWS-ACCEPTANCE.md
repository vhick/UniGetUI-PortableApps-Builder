# Manual Windows acceptance — check boxes only after actually performing them

- [ ] Full GitHub Actions run passes for a current stable upstream tag.
- [ ] Root `UniGetUIPortable.exe` has authentic UniGetUI icon; PE and architecture checks pass.
- [ ] Shared independent NSIS `.paf.exe` installs into an existing PortableApps Platform without an extra nested folder.
- [ ] PortableApps Menu discovers UniGetUI and launches via compiled root EXE.
- [ ] GUI loads, discovers available package managers and can search for packages.
- [ ] Close app; `Data/Settings/Configuration`, `InstallationOptions`, `CachedMetadata` persist.
- [ ] Close and restart twice; preferences remain and there is no duplicate or lost Data.
- [ ] `Data/Settings/Temp` retains relevant logs / WebView2 profile.
- [ ] Create harmless application-owned test files and a nested EMPTY folder under an eligible new scoped directory; after exit confirm copies under `Data/TraceGuard/External`.
- [ ] Pre-existing unrelated host profile and files remain untouched.
- [ ] Interrupt app/launcher in a controlled test and restart root launcher; verify recovery from interrupted Settings and journal.
- [ ] Test conflicting files; prior content survives in `Data/TraceGuard/Conflicts`.
- [ ] Relocate complete folder to a different directory and drive letter; settings and cache persist.
- [ ] Run app with a standard user from a writable PortableApps location; no privilege escalation to start the GUI.
- [ ] Verify installation of packages that need elevation prompts normally (do not silently elevate launcher).
- [ ] Reinstall same installer version over closed installation; existing Data stays intact.
- [ ] Upgrade to newer package version; only application files replaced; Data and empty directory trees remain.
- [ ] Roll back application binaries to an older package version; newer Data is still present and compatible or a documented migration is performed.
- [ ] Test abnormal shutdown followed by app **recovery** before any shared installer update.
- [ ] Verify actual Windows Defender / SmartScreen response; report warnings accurately.
- [ ] Confirm no unwanted process/file-association/PATH/autostart entries were created by the PortableApps package itself.

These are **manual outstanding tests** until someone checks them on a Windows machine. CI's structural ZIP tests and launcher self-test do not substitute for them.

## r6: Shared PowerShell traces (not verified by CI alone)

- [ ] Test in a **separate disposable Windows user account** or VM without `%LOCALAPPDATA%\PSResourceGet` and `%LOCALAPPDATA%\PackageManagement`.
- [ ] Launch `UniGetUIPortable.exe`, allow normal package manager discovery, and close it fully.
- [ ] If a new PSResourceGet directory was produced, confirm it has been copied to `Data\TraceGuard\External\LocalAppData_PSResourceGet` and removed from LocalAppData on clean exit.
- [ ] If a new PackageManagement directory was produced without installed providers, confirm it was safely captured; empty directories must survive.
- [ ] If any `ProviderAssemblies` files are installed, confirm PackageManagement remains on the host and `launcher.log` records why.
- [ ] Start again and verify PSResourceGet repository registrations are available during the session and re-captured after exit.
- [ ] Repeat with **pre-existing** PowerShell directories holding user settings/providers; verify they are **unchanged** after launch and close.
- [ ] Verify unrelated user PowerShell commands continue to work.
- [ ] Terminate the launcher abnormally during a test, then run it again to verify journal-based recovery.
- [ ] Run `scripts/report-powershell-state.ps1` as a read-only diagnostic when old r5 folders already exist.
