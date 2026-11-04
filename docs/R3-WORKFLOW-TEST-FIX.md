# r3 — Correct separate Python and PowerShell tests

## Evidence

The `logs_113226057573.zip` Windows runner log failed at `Fast independent ZIP safety fixture tests` on November 4, 2026. The expanded command was:

```text
python -m unittest discover -s tests -v ./tests/test-release-policy.ps1
ImportError: Start directory is not importable: './tests/test-release-policy.ps1'
```

This was caused by a folded YAML scalar, not by the upstream GitHub release or either pinned shared action.

## Correction

The Python test command now has an explicit multiline `run: |` block and an explicit `$LASTEXITCODE` check. The PowerShell stable-release regression is a separate named workflow step. A dependency-free Python regression test checks the critical workflow command layout and builder-revision values.

Builder revision increments to `b3`. The launcher, TraceGuard runtime, `custom-nsis` packaging integration, and shared publisher remain unchanged from r2. `Portable-Package-Builder@v1.0.0` and `portable-release-publisher@v1.1.1` are still pinned.

## Testing

At kit creation, the Python unit suite, YAML parsing, and package-archive validation were executed locally. Windows PowerShell regression execution, NativeAOT compilation, actual GUI launch, installer run, and release publishing still require a full Windows Actions run. Do not treat static checks as a successful Windows build.

## First run

In GitHub Desktop, replace r2 builder files with this r3 kit, commit, push, and run **Build UniGetUI PortableApps (x64)** with `build_method=release-zip` and an empty `upstream_version`.
