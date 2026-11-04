# r7 — PowerShell TraceGuard self-test timestamp regression fix

## Confirmed r6 failure

Uploaded log: `logs_113260346441.zip` (2026-11-04). The Windows run successfully resolved upstream `v2026.3.3`, built the GUI NativeAOT launcher, and passed the original `--traceguard-self-test`. The new `--traceguard-powershell-self-test` failed with exit code 3 and `Unverified PowerShell state` for `LocalAppData_PSResourceGet/PSResourceRepository.xml`.

## Cause

The r6 fixture writes `updated-repositories` and manually assigns it the timestamp `DateTime.UtcNow.AddSeconds(2)` (in the future). Later in the same quickly executing fixture, its crash-recovery test writes `after-crash` with a normal current timestamp, making the latter **older than the saved copy**, despite the sequence of writes. The production `CopyOne` code deliberately protects newer saved data and therefore refuses to replace it. Cleanup's `AssertTreeMatches` correctly detects the mismatch and refuses to delete the host source.

Microsoft confirms `.NET File.SetLastWriteTimeUtc` controls the UTC modification timestamp; comparison against the last-write time is therefore deliberate, not a packaging or publisher error: https://learn.microsoft.com/en-us/dotnet/api/system.io.file.setlastwritetimeutc?view=net-10.0

## Minimal repair

- Set consistent timestamp ordering, all relative to a captured fixture clock in the past: initial `-30 min`, updated `-20 min`, crash-recovery `-10 min`.
- Add a negative safety test with `-25 min` data to ensure the launcher still refuses to replace newer saved state, preserves the old host source, and signals an exception.
- Annotate failures with the test phase to make future logs actionable.
- Advance builder tag and ZIP filenames to `b7` to avoid r5/r6 asset collisions; keep package revision `r1`.

**No production TraceGuard logic, installation mechanism, shareable PowerShell profile policy, updater or shared action code was changed.**

## What is and is not verified

Linux-side Python static/ZIP tests and YAML parsing may pass before publishing the builder; real Windows NativeAOT execution and installer publishing are verified only after a GitHub-hosted Windows Actions run. Continue to preserve r5 as the last user-confirmed full-build working baseline; r6 and r7 are not yet accepted.
