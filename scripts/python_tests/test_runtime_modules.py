import re
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

    def test_urllib3_percent_re_override_is_unwrapped_before_reload(self):
        class Urllib3PercentREOverride:
            def __init__(self, r):
                self.re = r

        pattern = re.compile("%[a-fA-F0-9]{2}")
        url_module = types.ModuleType("urllib3.util.url")
        url_module._PERCENT_RE = Urllib3PercentREOverride(Urllib3PercentREOverride(pattern))
        original = sys.modules.get("urllib3.util.url")
        try:
            sys.modules["urllib3.util.url"] = url_module

            invalidate_runtime_package_modules()

            self.assertIs(url_module._PERCENT_RE, pattern)
        finally:
            if original is None:
                sys.modules.pop("urllib3.util.url", None)
            else:
                sys.modules["urllib3.util.url"] = original

    def test_loaded_webkit_jsi_runtime_is_invalidated_without_restart(self):
        module_names = (
            "yt_dlp",
            "yt_dlp_plugins",
            "yt_dlp_plugins.webkit_jsi",
            "yt_dlp_plugins.webkit_jsi.lib.api",
        )
        originals = {name: sys.modules.get(name) for name in module_names}
        try:
            for name in module_names:
                sys.modules[name] = types.ModuleType(name)

            restart_required = invalidate_runtime_package_modules()

            self.assertFalse(restart_required)
            for name in module_names:
                self.assertNotIn(name, sys.modules)
        finally:
            for name, module in originals.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module
