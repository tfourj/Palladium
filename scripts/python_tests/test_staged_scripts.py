import re
import unittest

from scripts.python_tests import helpers


class StagedPythonScriptsTests(unittest.TestCase):
    def test_every_package_module_is_staged(self):
        swift_source = (helpers.PYTHON_SERVICE_PATH / "PythonScripts.swift").read_text(encoding="utf-8")
        staged = set(re.findall(r'"(palladium_ytdlp/[^"]+\.py)"', swift_source))
        package_dir = helpers.PYTHON_SERVICE_PATH / "palladium_ytdlp"
        modules = {f"palladium_ytdlp/{path.name}" for path in package_dir.glob("*.py")}

        self.assertEqual(modules - staged, set(), "add new modules to PythonScripts.stagedPythonFiles")
        self.assertEqual(staged - modules, set())


if __name__ == "__main__":
    unittest.main()
