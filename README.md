> **r7 PowerShell TraceGuard fixture repair (2026-11-04):** r6 Windows Actions passed stable release resolution, downloaded the official ZIP, compiled the NativeAOT launcher, and passed the baseline TraceGuard test. The new PowerShell fixture failed because it used a future-dated file and then expected a later-created, older-dated file to replace it. r7 uses a deterministic increasing sequence of past timestamps and explicitly verifies that older conflicting host files remain protected. Production capture logic and both pinned shared actions are unchanged. See [docs/R7-POWERSHELL-TEST-FIX.md](docs/R7-POWERSHELL-TEST-FIX.md). **r7 Windows verification is pending.**

> **r5 Stage Data scope fix (2026-11-04):** The r4 Windows run passed upstream ZIP download, NativeAOT launcher compilation, GUI exit-code checks, and isolated TraceGuard recovery. It failed at stage validation because the validator mistakenly rejected an official UniGetUI resource in `App/UniGetUI/Assets/Data/Contributors.list`. r5 validates ONLY the portable root `Data` as empty, preserving upstream resources (including nested empty directories). A Windows offline regression fixture verifies this before downloading upstream ZIP files. See [docs/R5-STAGE-DATA-SCOPE-FIX.md](docs/R5-STAGE-DATA-SCOPE-FIX.md).

> **r4 WinExe self-test status fix (2026-11-04):** The r3 GitHub Actions run successfully resolved v2026.3.3, downloaded and staged the official portable ZIP, compiled the real NativeAOT GUI launcher, and printed the TraceGuard PASS message. The workflow nevertheless failed at `$LASTEXITCODE`. r4 explicitly waits for the GUI process and verifies `.ExitCode` using PowerShell `Start-Process -Wait -PassThru`. An independent nonzero exit probe checks the test harness. PASS now prints only after cleanup. See [docs/R4-WINEXE-EXIT-STATUS-FIX.md](docs/R4-WINEXE-EXIT-STATUS-FIX.md).

> **r3 workflow-test fix (2026-11-04):** The r2 GitHub Actions log showed YAML folding the Python and PowerShell test calls into one command; r3 makes them separate workflow steps, adds a regression check, and advances the builder revision to b3. The launch and TraceGuard implementation is unchanged. See [docs/R3-WORKFLOW-TEST-FIX.md](docs/R3-WORKFLOW-TEST-FIX.md).

> **r2 release-selection fix (2026-11-04):** A real GitHub Actions log revealed that the b1 resolver failed to select an upstream stable release because it filtered the complete `Invoke-RestMethod` array as one pipeline object. The earlier r2 kit introduced the GitHub `/releases/latest` API, with explicit safe history traversal when needed, plus a fixture-based PowerShell regression test. r2 was not yet verified by a complete Windows GitHub Actions build.

# UniGetUI PortableApps Builder — b7

Independent Windows x64 builder for [Devolutions UniGetUI](https://github.com/Devolutions/UniGetUI). This repository is **not** an official Devolutions release or PortableApps.com-certified build.

## What this ZIP contains

This ZIP is a **builder repository**, not the finished UniGetUI application. Commit it to your own new repository and manually run GitHub Actions. The workflow will:

1. Resolve the latest **stable** upstream `vYYYY.N.N` release (or the stable version you entered) and verify the corresponding Git commit.
2. Download the real upstream x64 portable ZIP and verify its SHA-256 against GitHub's asset digest or the official `checksums.txt`. Alternatively, explicitly choose **source-compile**, an experimental full upstream .NET 10 NativeAOT build from the tagged source.
3. Use the upstream Windows PE executable and genuine embedded upstream icon.
4. Compile `UniGetUIPortable.exe` from readable C# as a Windows x64 **NativeAOT** executable with the correct icon (not a batch file or script wrapper).
5. Assemble `UniGetUIPortable/App`, `Data`, `Other`, accurate AppInfo and MIT attribution.
6. Run synthetic Windows filesystem, crash-recovery, conflict and empty-folder tests **without launching the GUI**.
7. Create and validate `UniGetUIPortable_<version>_b7.zip` independently.
8. Hand the finished staging directory to `vhick/Portable-Package-Builder@v1.0.0` for an independent `custom-nsis` installer, validate its output and provenance JSON.
9. Run `vhick/portable-release-publisher@v1.1.1` in dry-run mode and then publish both final files in **the same repository**.

No GitHub Actions artifacts, PAT, scheduled build, application fork, source archive in Git, standalone NSIS generator or duplicate publisher are needed.

## Shared action integrations — pinned

| Action | Version | Verified interface |
| --- | --- | --- |
| [Portable-Package-Builder](https://github.com/vhick/Portable-Package-Builder) | `v1.0.0` | `source-dir`, `output-dir`, `engine`, `running-exe`, `package-revision`, `timeout-seconds`; output `installer-file`, `installer-sha256` |
| [portable-release-publisher](https://github.com/vhick/portable-release-publisher) | `v1.1.1` | `files`, `tag`, `release-title`, `keep-releases`, `prune`, `dry-run`; accepts ZIP + `.paf.exe` |

The workflow verifies those contracts and logs the tag reference SHA. We did **not** change the requested pinned tags. For stricter supply-chain security, replace the two `uses` tags with their audited immutable commit SHAs after an accepted Windows build.

**Installer identity:** the shared packager's default output is a `.paf.exe` generated by **independent NSIS** (`provenance=independent-nsis`), **not** by the official PortableApps.com Installer. No official certification is claimed.

## Expected release layout

```
UniGetUIPortable/
  UniGetUIPortable.exe             compiled root NativeAOT launcher
  App/
    AppInfo/
      appinfo.ini
      appicon.ico
      appicon_16.png
      appicon_32.png
      Launcher/UniGetUIPortable.ini
    UniGetUI/
      UniGetUI.exe                official upstream x64 binaries
      ForceUniGetUIPortable       native portable mode marker
      ...
  Data/                            persistent user state (empty in shipped ZIP)
    Settings/                      created automatically on first launch
    TraceGuard/
      session.json                interrupted-session recovery journal (when active)
      launcher.log
      instance-id.txt
      Conflicts/                  copies of conflicting files, never silently discarded
      External/                   recovered application-owned external paths and empty folders
  Other/
    Source/
      UPSTREAM-LICENSE.txt
      LAUNCHER-LICENSE.txt
      Build-Manifest.json
```

## First run and lifecycle

- Launch **only** the root `UniGetUIPortable.exe`. The raw `App/UniGetUI/UniGetUI.exe` does not coordinate `Data` persistence.
- UniGetUI itself determines portable operation using `ForceUniGetUIPortable` beside its executable. Its native `Settings` path is beside that EXE. The launcher mirrors saved `Data/Settings` into the upstream runtime location before process initialization.
- It snapshots exact UniGetUI/Pinget-owned external paths (including **empty directories**). Host paths already present are protected: only newly created children are eligible for recovery. Pre-existing files, even when modified, are not moved. The additional shared `PSResourceGet` and `PackageManagement` roots are protected specially: if pre-existing, they remain untouched; newly created roots may be recovered when safe, but installed PowerShell providers are never removed.
- While UniGetUI runs, the launcher checkpoints settings to `Data` every ~15 seconds when it can safely copy and verify them. Upon normal shutdown, it copies settings back to `Data`, removes only the captured runtime `Settings` tree after verification, captures eligible external files/directories (including empty nested trees), and clears the recovery journal.
- If the launcher is killed or Windows crashes, the next launch recovers any remaining `App/UniGetUI/Settings` and narrowly scoped external paths before starting UniGetUI. Conflicting files are preserved under `Data/TraceGuard/Conflicts`.
- A stable instance ID under `Data/TraceGuard` is forwarded through upstream's documented `UNIGETUI_GITHUB_TOKEN_NAMESPACE` so instances are separated on one computer. Credentials themselves remain in Windows Credential Manager and do **not** become portable.

### Critical limitation: crash followed by installer upgrade

On an interrupted run, an uncommitted `App/UniGetUI/Settings` folder may remain until the **next launcher start**. **Run `UniGetUIPortable.exe` once and close it normally before upgrading**. The shared installer preserves `Data`, but it cannot inspect this launcher-specific interrupted runtime folder before replacing `App`; upgrading immediately after a crash can discard changes newer than the most recent checkpoint. This builder does **not** claim transactional crash-to-upgrade protection in this situation.

For upgrades after an ordinary clean exit, the shared NSIS engine replaces obsolete `App`, `Other`, and launcher files and preserves `Data`. Never unpack a ZIP over an existing installation while the application is running. Use the shared installer for safer upgrades.

## Step-by-step: GitHub Desktop (Windows)

1. **Download the builder kit ZIP** from ChatGPT and extract it. In Windows Explorer, enable **View > Show > Hidden items** so you can see `.github`.
2. Open **GitHub Desktop** and sign in. Go to **File > New repository**.
3. Name the repository `UniGetUI-PortableApps-Builder` (or another independent name). Choose a local folder, then **Create repository**. **Do not clone or fork UniGetUI**.
4. In GitHub Desktop, use **Repository > Show in Explorer** to open that new repository folder.
5. Copy **all contents** from the extracted builder kit folder (including `.github`) into your repository folder, not into a nested folder. `README.md` must be at the repository root.
6. Return to GitHub Desktop. The **Changes** tab should show the workflows, `scripts`, `src`, documentation, and licenses. Enter summary `Update UniGetUI PortableApps Builder b7` and click **Commit to main**.
7. Click **Publish repository**. Choose public or private. Leave **Keep this code private** enabled if you want private binaries and private Releases. **Publishing does not change any existing repository visibility.**
8. Visit your repository on GitHub.com, click **Actions**. If prompted, enable Actions for this repository.
9. Select **Build UniGetUI PortableApps (x64)**, then **Run workflow**.
10. Leave `upstream_version` blank for the newest stable upstream release. Choose `release-zip` for the recommended first build. Click the green **Run workflow** button.
11. Read the job steps. The Windows workflow must complete the real launcher build, isolated recovery tests, ZIP and installer verification, publisher dry run, and actual publishing. If an installer step fails, the ZIP created earlier is **not automatically published** as a complete release; inspect the log before retrying.
12. When the workflow succeeds, open the builder repo's **Releases** page. The release contains the independent PortableApps ZIP, the shared packager's `.paf.exe`, and publisher-managed `SHA256SUMS.txt`.
13. **Installer method:** with UniGetUI closed, double-click the `.paf.exe`, select the destination `PortableApps/UniGetUIPortable` directory, and follow the prompts. This is an *independently generated* PortableApps-style installer.
14. **ZIP method:** extract the ZIP, then copy the single `UniGetUIPortable` folder into your PortableApps directory, e.g. `E:\PortableApps\UniGetUIPortable`. Do not create `UniGetUIPortable\UniGetUIPortable` nesting.
15. From PortableApps Platform choose **Apps > Refresh App Icons**, or restart the Platform. UniGetUI should appear as **UniGetUI Portable**. You can also run `UniGetUIPortable.exe` directly.
16. Use UniGetUI normally, close the app completely, and verify `Data\Settings` and `Data\TraceGuard` are populated. Move the entire `UniGetUIPortable` folder to another drive and launch again to test relocation.
17. **Update:** close the app and ensure no recovery is pending, then install a newer `.paf.exe` into the **same** existing destination. Keep `Data` untouched. Verify your saved settings after the update.
18. **Packaging-only:** run **Repackage existing PortableApps ZIP (no upstream rebuild)**. Enter a fully completed source release tag like `portable-v2026.3.3-b5-r1` and a revision like `repack1`. It downloads and checks the published ZIP, uses the shared packager, and publishes a *separate* repack release with both the original ZIP and new installer. No upstream or launcher compilation occurs.
19. **Recovered folders:** inspect `UniGetUIPortable\Data\TraceGuard\External\<location-name>\...`, including empty directories. Conflicts are under `Data\TraceGuard\Conflicts`. The journal and diagnostics are in `Data\TraceGuard`.

## Source compilation option

The normal path **retrieves verified upstream compiled release binaries** instead of wastefully compiling ~40 .NET projects. To explicitly compile UniGetUI from its actual source, select `source-compile` in the same workflow. It checks out the exact stable upstream tag, compares the source commit to the resolved tag, performs `.NET restore` and `dotnet publish` on the official Windows Avalonia project, runs the upstream integrity-tree generator, and compiles the separate root portable launcher. Upstream full source compilation is **experimental and not verified in this environment**; it may require additional dependencies or official service credentials. No silent fallback to a different version or binary is made if it fails.

## Security boundaries and nonportable parts

- The native portable mode stores application settings, installation preferences, caches, Pinget data and WebView2 scratch under the application's runtime `Settings` directory; the launcher persists this under `Data/Settings`.
- **Do not move** WinGet, Chocolatey, Scoop, npm, pip or other package-manager system data. Packages installed with those tools are **not portable** simply because the UniGetUI interface is portable.
- **Windows Credential Manager** holds UniGetUI's GitHub backup token; a new computer may need a new sign-in. `%ProgramFiles%\UniGetUI\SecureSettings` is protected system-level policy and must **not** be copied into user-writable `Data`.
- The portable release avoids protocol handler, file association, login autostart, PATH modification, Start menu and desktop shortcuts. Administrator rights may still be required to install or modify *system packages* through UniGetUI.
- TraceGuard only scans known, exact application-owned roots. A **new** external path not in the audited scope list cannot be promised as captured. Its external recovery is an additional defense around upstream native portability, **not** system-wide filesystem monitoring.
- Pre-existing host paths are never wholesale deleted. New files created inside a pre-existing scoped folder may be recovered; this is best-effort attribution, not proof of which process created them. Existing modified host files are left untouched.
- Files locked by third-party installers or still running in child processes may delay capture; a pending journal remains. The launcher waits for UniGetUI's **main process**, not every detached installer process.
- Writable removable or user folders are required. UniGetUI upstream explicitly falls back to `%LOCALAPPDATA%` if its `Settings` location cannot be written. Do **not** install under `Program Files` for portable use.
- Real UI operation, package-manager functionality, installer execution, Windows Defender behavior, crash-to-upgrade and genuine drive-letter relocation must be accepted on your Windows computer. CI does not start or close the desktop GUI unattended.

## Tests and actual validation status

This kit includes executable test routines and workflows. The isolated `--traceguard-self-test` exercises nested empty folders, file recovery, newer-file conflict protection, outside-folder copying and crash restoration. `validate-stage.ps1` checks metadata and real Windows x64 PE headers; `package_zip.py` tests the complete ZIP; `validate-installer.ps1` verifies shared packager checksum and provenance. Shared packager also performs its own archive integrity check.

**Validation to date:** The user confirmed r5 builds and its portable application runs. The supplied r6 GitHub Actions log confirms successful stable release resolution, upstream ZIP staging, NativeAOT compilation, original TraceGuard self-test, and 15 Python tests; the new PowerShell trace fixture failed due to conflicting test timestamps. r7 repairs only the fixture and its revision labels. r7 Windows launcher self-tests, package generation, and release publishing have not yet run. Actual GUI-level shared PowerShell behavior, relocation and upgrade acceptance remain manual tests.

## Costs and release discipline

The workflows run **manually**, on a standard Windows GitHub-hosted runner, each in a single job with concurrency limits. There is no `upload-artifact`, Git LFS, background schedule, or required PAT. Version tags contain the actual upstream version plus `b7` launcher-builder revision and `r1` installer revision. A complete already-published release is skipped; incomplete and draft tags stop with an error. The publisher preserves manually created releases, disables pruning by default and limits pruning to its managed, mutable releases if later enabled. GitHub Free quotas and release asset size restrictions still apply. Public repository releases are public, private repository releases are private.

## Main references

- [UniGetUI portability documentation](https://github.com/Devolutions/UniGetUI/blob/main/docs/PORTABLE.md)
- [UniGetUI CLI and environment variables](https://github.com/Devolutions/UniGetUI/blob/main/docs/CLI.md)
- [UniGetUI upstream Windows build notes](https://github.com/Devolutions/UniGetUI/blob/main/AGENTS.md)
- [Pinned packaging action contract](https://raw.githubusercontent.com/vhick/Portable-Package-Builder/v1.0.0/action.yml)
- [Pinned publisher action contract](https://raw.githubusercontent.com/vhick/portable-release-publisher/v1.1.1/action.yml)
- [Upstream MIT license](https://github.com/Devolutions/UniGetUI/blob/main/LICENSE)

See `docs/PORTABILITY-AUDIT.md`, `docs/TROUBLESHOOTING.md` and `docs/WINDOWS-ACCEPTANCE.md` for further details.

### PortableApps metadata identity

This independent builder uses PortableApps.com Format 3.9 and generates `AppID=UniGetUIPortable-<GitHub repository owner>` to avoid falsely claiming the identity of an official PortableApps.com or Devolutions package. The visible application folder and root launcher remain `UniGetUIPortable`. Keeping the builder under the same account preserves that package identity across updates; moving it to another owner changes the AppID and should be treated as a separate portable package.
