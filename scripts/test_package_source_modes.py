import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Palladium" / "Services" / "Python"))

from palladium_ytdlp.packages import (  # noqa: E402
    build_package_install_plan,
    build_pip_install_args,
    parse_package_source,
)


class PackageSourceModeTests(unittest.TestCase):
    def test_stable_install_plan_pins_latest_index_version(self):
        packages, cleanup = build_package_install_plan(
            {
                "yt-dlp": "1.0",
                "yt-dlp-apple-webkit-jsi": "1.0",
                "pip": "1.0",
            },
            {
                "yt-dlp": ["2.0"],
                "yt-dlp-apple-webkit-jsi": ["1.0"],
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

    def test_custom_specs_pass_through_without_rewriting(self):
        source = parse_package_source(json.dumps({
            "mode": "custom",
            "custom_specs": [
                "yt-dlp==2026.1",
                "yt-dlp-apple-webkit-jsi @ https://example.com/webkit.whl",
            ],
        }))
        packages, cleanup = build_package_install_plan({}, {}, package_source=source)

        self.assertEqual(packages, [
            "yt-dlp==2026.1",
            "yt-dlp-apple-webkit-jsi @ https://example.com/webkit.whl",
        ])
        self.assertEqual(cleanup, ["yt-dlp", "yt-dlp-apple-webkit-jsi"])

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


if __name__ == "__main__":
    unittest.main()
