import json
import pathlib
import sys
import types
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Palladium" / "Services" / "Python"))

from palladium_ytdlp.packages import (  # noqa: E402
    build_package_install_plan,
    build_package_update_lines,
    build_pip_install_args,
    parse_package_source,
)
from palladium_ytdlp.shared import YTDLP_RUNTIME_PACKAGES  # noqa: E402
from palladium_ytdlp.entrypoints import invalidate_runtime_package_modules  # noqa: E402
from palladium_ytdlp.gallery import gallery_item_media_type  # noqa: E402


class PackageSourceModeTests(unittest.TestCase):
    def test_stable_install_plan_pins_latest_index_version(self):
        packages, cleanup = build_package_install_plan(
            {
                "yt-dlp": "1.0",
                "yt-dlp-apple-webkit-jsi": "1.0",
                "curl-cffi": "1.0",
                "pip": "1.0",
            },
            {
                "yt-dlp": ["2.0"],
                "yt-dlp-apple-webkit-jsi": ["1.0"],
                "curl-cffi": ["1.0"],
                "pip": ["1.0"],
            },
            package_source=parse_package_source(json.dumps({"mode": "stable"})),
        )

        self.assertEqual(packages, ["yt-dlp==2.0"])
        self.assertEqual(cleanup, ["yt-dlp"])

    def test_nightly_install_args_include_prereleases(self):
        args = build_pip_install_args(
            ["yt-dlp==2.0.dev1"],
            install_target="/tmp/palladium-packages",
            allow_prereleases=True,
            upgrade=True,
        )

        self.assertIn("--pre", args)
        self.assertIn("--upgrade", args)
        self.assertIn("yt-dlp==2.0.dev1", args)

    def test_stable_install_args_do_not_include_prereleases(self):
        args = build_pip_install_args(["yt-dlp"], allow_prereleases=False)

        self.assertNotIn("--pre", args)
        self.assertIn("yt-dlp", args)

    def test_gallery_dl_is_managed_with_other_runtime_packages(self):
        packages, cleanup = build_package_install_plan(
            {"gallery-dl": "1.0"},
            {"gallery-dl": ["2.0"]},
            package_source=parse_package_source(json.dumps({"mode": "stable"})),
        )

        self.assertEqual(packages, ["gallery-dl==2.0"])
        self.assertEqual(cleanup, ["gallery-dl"])

    def test_curl_cffi_is_managed_with_other_runtime_packages(self):
        packages, cleanup = build_package_install_plan(
            {"curl-cffi": "1.0"},
            {"curl-cffi": ["2.0"]},
            package_source=parse_package_source(json.dumps({"mode": "stable"})),
        )

        self.assertEqual(packages, ["curl-cffi==2.0"])
        self.assertEqual(cleanup, ["curl-cffi"])

    def test_curl_cffi_is_required_for_yt_dlp_runtime(self):
        self.assertIn("curl-cffi", YTDLP_RUNTIME_PACKAGES)

    def test_missing_curl_cffi_is_installed_from_index(self):
        packages, cleanup = build_package_install_plan(
            {
                "yt-dlp": "1.0",
                "yt-dlp-apple-webkit-jsi": "1.0",
                "curl-cffi": "not installed",
            },
            {"curl-cffi": ["2.0"]},
            package_source=parse_package_source(json.dumps({"mode": "stable"})),
        )

        self.assertEqual(packages, ["curl-cffi==2.0"])
        self.assertEqual(cleanup, ["curl-cffi"])

    def test_missing_curl_cffi_is_reported_as_available_update(self):
        lines = build_package_update_lines(
            {"curl-cffi": "not installed"},
            {"curl-cffi": ["2.0"]},
        )

        self.assertEqual(lines, ["curl-cffi: not installed -> 2.0"])

    def test_gallery_audio_urls_with_tiktok_hints_are_classified_as_audio(self):
        self.assertEqual(
            gallery_item_media_type("https://sf16-ies-music-va.tiktokcdn.com/obj/tos-useast2a-v-2774/music-file"),
            "audio",
        )
        self.assertEqual(
            gallery_item_media_type("https://example.com/media?id=1&mime_type=audio_mpeg"),
            "audio",
        )

    def test_gallery_unknown_urls_without_media_hints_are_classified_as_file(self):
        self.assertEqual(gallery_item_media_type("https://example.com/download/opaque-token"), "file")

    def test_custom_specs_pass_through_without_rewriting(self):
        source = parse_package_source(json.dumps({
            "mode": "custom",
            "custom_specs": [
                "yt-dlp==2026.1",
                "yt-dlp-apple-webkit-jsi @ https://example.com/webkit.whl",
                "curl-cffi==1.0",
            ],
        }))
        packages, cleanup = build_package_install_plan({}, {}, package_source=source)

        self.assertEqual(packages, [
            "yt-dlp==2026.1",
            "yt-dlp-apple-webkit-jsi @ https://example.com/webkit.whl",
            "curl-cffi==1.0",
        ])
        self.assertEqual(cleanup, ["yt-dlp", "yt-dlp-apple-webkit-jsi", "curl-cffi", "gallery-dl"])

    def test_custom_source_skips_webkit_patch(self):
        custom_source = parse_package_source(json.dumps({"mode": "custom"}))
        stable_source = parse_package_source(json.dumps({"mode": "stable"}))

        self.assertTrue(custom_source["skip_webkit_patch"])
        self.assertFalse(stable_source["skip_webkit_patch"])

    def test_explicit_setting_skips_webkit_patch(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "disable_webkit_jsi_patch": True,
        }))

        self.assertTrue(source["skip_webkit_patch"])

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


if __name__ == "__main__":
    unittest.main()
