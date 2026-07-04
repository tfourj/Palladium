import sys
import types
import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.entrypoints import invalidate_runtime_package_modules  # noqa: E402


class RuntimeModuleTests(unittest.TestCase):
    def test_runtime_package_module_cache_is_invalidated(self):
        module_names = ("yt_dlp", "yt_dlp.extractor")
        originals = {name: sys.modules.get(name) for name in module_names}
        try:
            for name in module_names:
                sys.modules[name] = types.ModuleType(name)

            restart_required = invalidate_runtime_package_modules()

            for name in module_names:
                self.assertNotIn(name, sys.modules)
            self.assertFalse(restart_required)
        finally:
            for name, module in originals.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module

    def test_loaded_webkit_jsi_runtime_requires_restart(self):
        module_names = ("yt_dlp", "yt_dlp_plugins.webkit_jsi")
        originals = {name: sys.modules.get(name) for name in module_names}
        try:
            for name in module_names:
                sys.modules[name] = types.ModuleType(name)

            restart_required = invalidate_runtime_package_modules()

            self.assertTrue(restart_required)
            for name in module_names:
                self.assertIn(name, sys.modules)
        finally:
            for name, module in originals.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module
