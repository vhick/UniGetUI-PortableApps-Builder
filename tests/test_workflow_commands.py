"""Guard against accidentally joining Python and PowerShell test commands in YAML."""
from pathlib import Path
import re
import unittest

WORKFLOW = Path(__file__).resolve().parents[1] / '.github' / 'workflows' / 'build-portableapps.yml'


class WorkflowCommandsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text(encoding='utf-8')

    def test_python_test_is_explicit_multiline_block(self):
        self.assertRegex(
            self.workflow,
            r'(?m)^      - name: Fast independent ZIP safety fixture tests\n'
            r'        shell: pwsh\n'
            r'        run: \|\n'
            r'          python -m unittest discover -s tests -v\n'
            r"          if \(\$LASTEXITCODE -ne 0\) \{ throw '[^']+' \}\n",
        )

    def test_powershell_regression_suite_is_separate_step(self):
        self.assertRegex(
            self.workflow,
            r'(?m)^      - name: Offline stable-release resolver regression tests\n'
            r'        shell: pwsh\n'
            r'        run: \./tests/test-release-policy\.ps1$',
        )

    def test_no_broken_folded_python_powershell_test_command(self):
        self.assertNotRegex(
            self.workflow,
            r'(?m)^\s*run: python -m unittest discover[^\n]*\n\s+\./tests/test-release-policy\.ps1',
        )

    def test_b7_revision_is_consistent(self):
        self.assertIn('-BuilderRevision b7 -PackageRevision r1', self.workflow)
        self.assertIn('_b7.zip', self.workflow)
        self.assertIn('builder b7, independent NSIS r1', self.workflow)
        self.assertNotIn('builder b2, independent', self.workflow)

    def test_root_data_scope_regression_is_run_before_upstream_download(self):
        fixture = self.workflow.index('      - name: Offline PortableApps root Data scope regression tests')
        resolve = self.workflow.index('      - name: Resolve stable release, upstream checksum')
        self.assertLess(fixture, resolve)
        self.assertIn('run: ./tests/test-stage-data-scope.ps1', self.workflow)

    def test_validator_only_checks_portable_root_data(self):
        code = (WORKFLOW.parents[2] / 'scripts' / 'validate-stage.ps1').read_text(encoding='utf-8')
        self.assertIn("$portableData = Join-Path (Resolve-Path -LiteralPath $Root).Path 'Data'", code)
        self.assertIn('Get-ChildItem -LiteralPath $portableData -Force', code)
        self.assertNotIn('Unexpected Data payload', code)
        self.assertNotIn('if($file.FullName -match', code)

    def test_gui_launcher_exit_code_is_checked_from_process_object(self):
        # NativeAOT GUI (WinExe) programs do not reliably set $LASTEXITCODE.
        block = self.workflow.split('      - name: Run isolated, non-GUI Windows TraceGuard tests', 1)[1].split('      - name:', 1)[0]
        self.assertIn('timeout-minutes: 3', block)
        self.assertEqual(block.count('Start-Process -FilePath $exe'), 3)
        self.assertEqual(block.count('-NoNewWindow -PassThru -Wait'), 3)
        self.assertIn("'--traceguard-exit-probe'", block)
        self.assertIn('ExitCode -ne 7', block)
        self.assertIn("'--traceguard-self-test'", block)
        self.assertIn("'--traceguard-powershell-self-test'", block)
        self.assertIn('ExitCode -ne 0', block)
        self.assertNotIn('if ($LASTEXITCODE -ne 0)', block)

    def test_winexe_exit_code_probe_and_truthful_selftest_reporting(self):
        src = (WORKFLOW.parents[2] / 'src' / 'UniGetUIPortable' / 'Program.cs').read_text(encoding='utf-8')
        self.assertIn('"--traceguard-exit-probe"', src)
        self.assertIn('return 7;', src)
        self.assertLess(src.find('finally { if (Directory.Exists(t)) Directory.Delete(t, true); }'), src.find('Console.WriteLine("TraceGuard self-test PASS:'))


if __name__ == '__main__':
    unittest.main()
