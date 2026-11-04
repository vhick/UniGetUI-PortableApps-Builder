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

    def test_b3_revision_is_consistent(self):
        self.assertIn('-BuilderRevision b3 -PackageRevision r1', self.workflow)
        self.assertIn('_b3.zip', self.workflow)
        self.assertIn('builder b3, independent NSIS r1', self.workflow)
        self.assertNotIn('builder b2, independent', self.workflow)


if __name__ == '__main__':
    unittest.main()
