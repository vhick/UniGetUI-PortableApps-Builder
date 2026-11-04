# r5 — Preserve upstream `App/UniGetUI/Assets/Data` resources

## Evidence from the r4 GitHub Actions run

The workflow passed stable release resolution, verified UniGetUI v2026.3.3, compiled `UniGetUIPortable.exe` with NativeAOT, and passed `--traceguard-exit-probe` plus `--traceguard-self-test`. It failed in `scripts/validate-stage.ps1` on:

```text
Unexpected Data payload ...\App\UniGetUI\Assets\Data\Contributors.list
```

The r4 validator searched **absolute paths** for the substring `\Data\`, confusing official application assets with PortableApps user storage.

## Repair

- Remove this overly broad recursive name-based rejection.
- Require only the real root `UniGetUIPortable/Data` directory to be empty before packaging. The existing ZIP packager still blocks **any** file or folder below that root, including empty directories.
- Keep recursive reparse-point rejection. Do not remove upstream application assets in `App/UniGetUI/Assets/Data`, even empty directories.
- Add `tests/test-stage-data-scope.ps1` running before the first upstream download. Its x64 PE fixture checks that official nested `App/UniGetUI/Assets/Data/Contributors.list` is accepted, while a root `Data/private.txt` and an empty nested root `Data/empty/inner` are rejected.
- Expand the Python independent ZIP fixture to preserve `App/UniGetUI/Assets/Data/Contributors.list` and nested empty folders.
- Update revision references to `b5`; keep the pinned packager v1.0.0 and publisher v1.1.1 and the functioning r4 launcher/TraceGuard unchanged.

## Status

The r4 CI log established that launcher compilation and TraceGuard self-tests passed. The r5 Windows fixture, stage validation, shared package builder, publishing, actual GUI usage and upgrade acceptance still require execution. Do not assume a successful installer release before the workflow finishes.
