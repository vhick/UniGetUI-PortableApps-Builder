# Source-based UniGetUI Windows portability audit — 2026-11-04

## Identified upstream

- Project: Devolutions/UniGetUI, Windows C# / .NET 10 / Avalonia, x64 and ARM64 release architectures, self-contained Windows NativeAOT release publishing.
- Official build: `src/UniGetUI.Windows.slnx`; Avalonia project `src/UniGetUI.Avalonia/UniGetUI.Avalonia.csproj`; source uses NuGet packages and scripts for secrets and `IntegrityTree.json`.
- Latest release found during audit: **v2026.3.3** (2026-10-29); the builder re-resolves latest stable at runtime rather than hardcoding that release.
- Upstream main code license: MIT, copyright 2025 Martí Climent; preserve it when redistributing. Dependencies have their own terms.
- Native portability activated by `ForceUniGetUIPortable` alongside `UniGetUI.exe`; official `UniGetUI.x64.zip` already contains the marker in recent stable releases. The marker must stay in the app's original root.

## Storage and host effects

| Source-backed path/integration | Installed behavior | Portable upstream / this builder | Limit |
| --- | --- | --- | --- |
| `%LOCALAPPDATA%\UniGetUI` | Main profile | `<app>\Settings`; saved to `Data\Settings` by launcher | Native mode only when folder writable |
| `Configuration` | User preferences | `Data\Settings\Configuration` | Copied to app runtime before starting |
| `InstallationOptions` | Per-package choices | `Data\Settings\InstallationOptions` | Ditto |
| `CachedMetadata` | Package cache | `Data\Settings\CachedMetadata` | May be large |
| `CachedMedia`, `CachedLanguageFiles` | Icon/language media | `Data\Settings\...` | May be large |
| `%TEMP%\UniGetUI` | Logs, crash report, updater log, WebView2 | `<app>\Settings\Temp` → `Data\Settings\Temp` | Host path monitored only as extra defense |
| `Documents\UniGetUI` | Default backups | `Data\Settings\Backups` | Custom user-configured backup path can remain external |
| `%LOCALAPPDATA%\Devolutions\Pinget` | Bundled Pinget store | `Data\Settings\Pinget` using upstream `PINGET_APPROOT` | Do not touch pre-existing host cache wholesale |
| Windows Credential Manager | GitHub backup token | Stays encrypted to Windows user | Not portable across machines |
| `%ProgramFiles%\UniGetUI\SecureSettings` | Elevated secure policy | Remains outside portable folder | Security boundary; do not relocate |
| Registry protocol `unigetui://` | Installer registers handler | Not registered | Windows deep links unavailable |
| `.ubundle` association | Installer adds handler | Not registered | Open via command line |
| Autostart / PATH / shortcuts | Installer may register | None by default | No silent persistence or PATH edits |
| WinGet, Scoop, Chocolatey, pip, npm, .NET Tool, Cargo etc. | Use host data/registry/elevation | Still host-managed | Installed applications are not portable |
| Other possible app-created `%APPDATA%\UniGetUI`, `%PROGRAMDATA%\UniGetUI` | Not established as normal upstream portable locations | Narrow defensive TraceGuard scopes | Not proof of ownership; do not capture entire host trees |

## Launcher design rationale

1. No source patch or writable NTFS junction under `App` is necessary. A junction could accidentally lead an updater to delete `Data` or break on FAT/exFAT drives; the launcher instead performs verified file copying before startup, during checkpoints and after exit.
2. The original app remains unmodified. This reduces regressions in package-manager functionality, reduces unsigned patch risk and preserves the official integrity tree.
3. The root launcher is a genuine compiled Windows NativeAOT executable with its upstream original icon, separate from the actual upstream binary.
4. Empty directories are enumerated explicitly. Conflicting copies are saved to `Data\TraceGuard\Conflicts` with no silent overwrites.
5. Journal snapshots record *exact* application-owned scopes and their existing path names, not entire AppData or ProgramData parents. When an external root exists before launch, only newly created descendants are candidates for capture; existing files remain untouched.
6. Existing data in a host profile is never implicitly imported from a normal UniGetUI installation. Upstream may offer a one-time import from `%LOCALAPPDATA%\UniGetUI` instead.

## Host configuration details not established in source inspection

The audit did not conclusively enumerate every WinGet/Chocolatey/Scoop registry entry or every external path written by all their installers. Those are independent package managers and are explicitly **out of scope for data relocation**. The upstream app may still run executables elevated when the user requests system package installations.

## Known limitations

- Some files can be in use when the app's main process exits; recovery remains pending and the launcher reports failure rather than indiscriminately deleting them.
- The protected scope snapshot cannot distinguish concurrent unrelated host writes from UniGetUI writes; monitoring is therefore deliberately narrow and conservative.
- Runtime `Settings` must be staged next to the upstream EXE. A system crash followed immediately by an App-replacing installer can lose changes after the last checkpoint; relaunch and close before upgrade.
- Windows Credential Manager and protected policy files intentionally stay on the host.
- No official PortableApps.com Installer provenance or certification is claimed for custom NSIS.
- Source-compile branch is experimental and may not have complete Devolutions service credentials or upstream release-signing infrastructure.

## Evidence references

- https://github.com/Devolutions/UniGetUI/blob/main/docs/PORTABLE.md
- https://github.com/Devolutions/UniGetUI/blob/main/docs/CLI.md
- https://github.com/Devolutions/UniGetUI/blob/main/AGENTS.md
- https://github.com/Devolutions/UniGetUI/releases
- https://raw.githubusercontent.com/vhick/Portable-Package-Builder/v1.0.0/action.yml
- https://raw.githubusercontent.com/vhick/Portable-Package-Builder/v1.0.0/nsis/community-installer.nsi
- https://raw.githubusercontent.com/vhick/portable-release-publisher/v1.1.1/action.yml
- https://raw.githubusercontent.com/vhick/portable-release-publisher/v1.1.1/scripts/publish.py
