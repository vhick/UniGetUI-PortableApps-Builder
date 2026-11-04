"""Fail early if the scoped PowerShell protections are accidentally removed."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = (ROOT / 'src/UniGetUIPortable/Program.cs').read_text(encoding='utf-8')
WORKFLOW = (ROOT / '.github/workflows/build-portableapps.yml').read_text(encoding='utf-8')


class PowerShellScopePolicyTests(unittest.TestCase):
    def test_exact_shared_paths_not_whole_appdata(self):
        self.assertIn('["LocalAppData_PSResourceGet"] = Path.Combine(local, "PSResourceGet")', SRC)
        self.assertIn('["LocalAppData_PackageManagement"] = Path.Combine(local, "PackageManagement")', SRC)
        self.assertIn('IsSharedPowerShellScope', SRC)
        self.assertNotIn('Path.Combine(local, "*"', SRC)

    def test_preexisting_scope_and_installed_providers_protected(self):
        self.assertIn('if (IsSharedPowerShellScope(key))', SRC)
        self.assertIn('return new ScopeState(key, path, true, new List<string>(), true);', SRC)
        self.assertIn('HasInstalledProviders(entry.Path)', SRC)
        self.assertIn('ProviderAssemblies', SRC)

    def test_reattach_requires_absence_and_cleanup_is_nonrecursive(self):
        self.assertIn('RestoreSharedPowerShellScopes(journal, statePath)', SRC)
        self.assertIn('CreateDirectoryW(entry.Path, 0)', SRC)
        self.assertIn('if (error != 183)', SRC)
        self.assertIn('RemoveCapturedTreeNonRecursive(entry.Path, dest)', SRC)
        self.assertIn('Directory.Delete(source, false)', SRC)
        self.assertIn('AssertTreeMatches(source, destination)', SRC)

    def test_isolated_windows_selftest_is_mandatory(self):
        self.assertIn('"--traceguard-powershell-self-test"', SRC)
        self.assertIn("$powershellTest = Start-Process -FilePath $exe -ArgumentList '--traceguard-powershell-self-test'", WORKFLOW)
        self.assertIn('if ($null -eq $powershellTest', WORKFLOW)
        self.assertIn('ExitCode -ne 0', WORKFLOW)


if __name__ == '__main__':
    unittest.main()
