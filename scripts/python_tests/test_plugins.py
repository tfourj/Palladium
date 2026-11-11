import os
import pathlib
import sys
import tempfile
import types
import unittest
from unittest import mock

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp import plugins  # noqa: E402


class PluginFolderTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.plugin_dir = os.path.realpath(self.temp_dir.name)
        plugins._loaded_plugin_signature = None

    def tearDown(self):
        plugins._loaded_plugin_signature = None
        self.temp_dir.cleanup()

    def test_plugin_dir_args_require_an_existing_folder(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(plugins.plugin_dir_args(), ())
        missing = os.path.join(self.plugin_dir, "missing")
        with mock.patch.dict(os.environ, {plugins.PLUGINS_DIR_ENV: missing}):
            self.assertEqual(plugins.plugin_dir_args(), ())
        with mock.patch.dict(os.environ, {plugins.PLUGINS_DIR_ENV: self.plugin_dir}):
            self.assertEqual(plugins.plugin_dir_args(), ("--plugin-dirs", self.plugin_dir))
            self.assertEqual(plugins.plugin_dirs_value(), ["default", self.plugin_dir])

    def test_yt_dlp_reloads_only_when_plugin_folder_changes(self):
        with (
            mock.patch.dict(os.environ, {plugins.PLUGINS_DIR_ENV: self.plugin_dir}),
            mock.patch.object(plugins, "invalidate_runtime_package_modules") as invalidate,
        ):
            plugins.prepare_plugin_imports()
            plugins.prepare_plugin_imports()
            invalidate.assert_not_called()

            pathlib.Path(self.plugin_dir, "plugin.zip").write_bytes(b"zip")
            plugins.prepare_plugin_imports()
            invalidate.assert_called_once()

            pathlib.Path(self.plugin_dir, "plugin.zip").unlink()
            plugins.prepare_plugin_imports()
            self.assertEqual(invalidate.call_count, 2)

    def test_cache_reset_keeps_loaded_plugin_modules_and_other_importers(self):
        inside = os.path.join(self.plugin_dir, "plugin.zip")
        outside = os.path.join(os.path.dirname(self.plugin_dir), "other.zip")
        module_names = ("yt_dlp_plugins", "yt_dlp_plugins.extractor.example")
        originals = {name: sys.modules.get(name) for name in module_names}
        try:
            for name in module_names:
                sys.modules[name] = types.ModuleType(name)
            sys.path_importer_cache[inside] = object()
            sys.path_importer_cache[outside] = object()

            plugins.clear_plugin_import_caches(self.plugin_dir)

            self.assertNotIn("yt_dlp_plugins", sys.modules)
            self.assertIn("yt_dlp_plugins.extractor.example", sys.modules)
            self.assertNotIn(inside, sys.path_importer_cache)
            self.assertIn(outside, sys.path_importer_cache)
        finally:
            sys.path_importer_cache.pop(inside, None)
            sys.path_importer_cache.pop(outside, None)
            for name, module in originals.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module


if __name__ == "__main__":
    unittest.main()
