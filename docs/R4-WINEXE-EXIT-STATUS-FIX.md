# r4 — Windows GUI executable exit-code check

## Evidence from GitHub Actions `logs_113243878628.zip`

- `Fast independent ZIP safety fixture tests`: 6/6 passed.
- `Offline stable-release resolver regression tests`: passed.
- Stable release: `v2026.3.3`, source commit `2a9b4635e8e07b935bc9ce4982fcec13b8c9bc05`.
- The official x64 ZIP was verified and staged; `dotnet publish` successfully generated `work/launcher/UniGetUIPortable.exe` using NativeAOT.
- The compiled executable printed `TraceGuard self-test PASS: files, nested empty folders, conflicts, external recovery, crash recovery`.
- The next PowerShell instruction, `if ($LASTEXITCODE -ne 0)`, threw, stopping the job before archive creation and installer generation.

The compiled launcher uses `<OutputType>WinExe</OutputType>`. PowerShell can launch Windows GUI-subsystem applications without waiting; the automatic `$LASTEXITCODE` variable is not a reliable exit-status probe for this application type. `$null -ne 0` is true, making the previous check fragile even when the application completes normally.

## Changes

- Wait for the GUI-subsystem process with `Start-Process -NoNewWindow -PassThru -Wait`.
- Check the returned `.ExitCode` rather than `$LASTEXITCODE`.
- First run `--traceguard-exit-probe`, which deliberately returns `7`. Assert that the process reports `7`, so the harness cannot falsely accept an absent exit code.
- Then run `--traceguard-self-test`, expecting `0`.
- Add a 3-minute limit for the headless test step.
- Print the TraceGuard PASS message only after test fixture cleanup completes.
- Add Python regression checks for the tested workflow command shape.
- Increment builder revision to `b4`, preserving package revision `r1`, and retain pinned shared actions unchanged.

## Scope and status

These changes only affect launcher self-test instrumentation and the Windows CI test step; the live portable runtime, data relocation, TraceGuard behavior, upstream release retrieval, package engine and publisher remain unchanged.

This correction has been statically checked and its Python fixtures executed on Linux. Windows execution of r4, installer generation, real GUI operation, and on-device portability are **pending**. A future Windows GitHub Actions run is required to confirm the fix.

Microsoft reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process
