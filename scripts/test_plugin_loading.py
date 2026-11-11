import contextlib
import importlib
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile
from unittest import mock

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp import plugins  # noqa: E402
from palladium_ytdlp.ytdlp import list_yt_dlp_formats, preview_yt_dlp_link  # noqa: E402

PLUGIN_SOURCE = """
from yt_dlp.extractor.common import InfoExtractor


class {class_name}(InfoExtractor):
    _VALID_URL = r'palladiumplugin:(?P<id>\\w+)'

    def _real_extract(self, url):
        video_id = self._match_id(url)
        return {{
            'id': video_id,
            'title': '{title} ' + video_id,
            'formats': [{{'format_id': 'mp4', 'url': 'https://example.invalid/v.mp4', 'ext': 'mp4'}}],
        }}
"""


class PluginLoadingTests(unittest.TestCase):
    """Runs on its own because plugin changes reload yt-dlp modules."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.plugin_dir = os.path.realpath(self.temp_dir.name)
        self.environment = mock.patch.dict(os.environ, {plugins.PLUGINS_DIR_ENV: self.plugin_dir})
        self.environment.start()
        plugins._loaded_plugin_signature = None

    def tearDown(self):
        self.environment.stop()
        with contextlib.redirect_stdout(io.StringIO()):
            plugins.invalidate_runtime_package_modules()
        plugins.clear_plugin_import_caches(self.plugin_dir)
        plugins._loaded_plugin_signature = None
        self.temp_dir.cleanup()

    def write_zip_plugin(self, file_name="palladium-test.zip", class_name="PalladiumPluginIE", title="plugin"):
        source = PLUGIN_SOURCE.format(class_name=class_name, title=title)
        with zipfile.ZipFile(os.path.join(self.plugin_dir, file_name), "w") as archive:
            archive.writestr("yt_dlp_plugins/extractor/palladium_plugin.py", source)

    def preview(self, url="palladiumplugin:abc"):
        return json.loads(preview_yt_dlp_link(url))

    def test_plugin_added_after_first_run_is_used_for_previews_and_formats(self):
        self.assertFalse(self.preview()["success"])

        self.write_zip_plugin()

        self.assertEqual(self.preview()["title"], "plugin abc")
        formats = json.loads(list_yt_dlp_formats("palladiumplugin:abc"))
        self.assertTrue(formats["success"], formats)

    def test_removed_plugin_is_unloaded(self):
        self.write_zip_plugin()
        self.assertTrue(self.preview()["success"])

        os.remove(os.path.join(self.plugin_dir, "palladium-test.zip"))

        self.assertFalse(self.preview()["success"])

    def test_replaced_plugin_uses_new_code(self):
        self.write_zip_plugin()
        self.assertEqual(self.preview()["title"], "plugin abc")

        self.write_zip_plugin(class_name="PalladiumReplacedIE", title="replaced")

        self.assertEqual(self.preview()["title"], "replaced abc")

    def test_zip_plugin_survives_global_import_cache_reset(self):
        self.write_zip_plugin()
        self.assertTrue(self.preview()["success"])

        importlib.invalidate_caches()

        self.assertEqual(self.preview()["title"], "plugin abc")

    def test_command_line_run_loads_plugin_folder(self):
        self.write_zip_plugin()
        plugins.prepare_plugin_imports()
        import yt_dlp

        output = io.StringIO()
        argv = ["yt-dlp", "--ignore-config", "--simulate", "--print", "title", *plugins.plugin_dir_args()]
        with (
            mock.patch.object(sys, "argv", [*argv, "palladiumplugin:cli"]),
            contextlib.redirect_stdout(output),
            self.assertRaises(SystemExit) as exit_context,
        ):
            yt_dlp.main()

        self.assertIn(exit_context.exception.code, (None, 0))
        self.assertIn("plugin cli", output.getvalue())


if __name__ == "__main__":
    unittest.main()
