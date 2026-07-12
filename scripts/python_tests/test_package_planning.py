import json
import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.packages import (  # noqa: E402
    build_package_install_plan,
    build_package_update_lines,
    build_pip_install_args,
    parse_package_source,
)
from palladium_ytdlp.shared import YTDLP_RUNTIME_PACKAGES  # noqa: E402


class PackagePlanningTests(unittest.TestCase):
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

    def test_locked_version_prevents_latest_update(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "locked_versions": {
                "yt-dlp": "1.0",
            },
        }))
        packages, cleanup = build_package_install_plan(
            {"yt-dlp": "1.0"},
            {"yt-dlp": ["2.0"]},
            package_source=source,
        )
        lines = build_package_update_lines(
            {"yt-dlp": "1.0"},
            {"yt-dlp": ["2.0"]},
            package_source=source,
        )

        self.assertEqual(packages, [])
        self.assertEqual(cleanup, [])
        self.assertEqual(lines, [])

    def test_locked_version_downgrades_to_target(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "locked_versions": {
                "yt-dlp": "1.0",
            },
        }))
        packages, cleanup = build_package_install_plan(
            {"yt-dlp": "2.0"},
            {"yt-dlp": ["3.0"]},
            package_source=source,
        )
        lines = build_package_update_lines(
            {"yt-dlp": "2.0"},
            {"yt-dlp": ["3.0"]},
            package_source=source,
        )

        self.assertEqual(packages, ["yt-dlp==1.0"])
        self.assertEqual(cleanup, ["yt-dlp"])
        self.assertEqual(lines, ["yt-dlp: 2.0 -> 1.0"])

    def test_locked_missing_runtime_package_is_installed(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "locked_versions": {
                "gallery-dl": "1.0",
            },
        }))
        packages, cleanup = build_package_install_plan(
            {"gallery-dl": "not installed"},
            {"gallery-dl": ["2.0"]},
            package_source=source,
        )
        lines = build_package_update_lines(
            {"gallery-dl": "not installed"},
            {"gallery-dl": ["2.0"]},
            include_missing=True,
            package_source=source,
        )

        self.assertEqual(packages, ["gallery-dl==1.0"])
        self.assertEqual(cleanup, ["gallery-dl"])
        self.assertEqual(lines, ["gallery-dl: not installed -> 1.0"])

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

    def test_clean_reinstall_forces_fresh_package_install(self):
        args = build_pip_install_args(
            ["yt-dlp", "yt-dlp-apple-webkit-jsi"],
            install_target="/tmp/palladium-packages",
            upgrade=True,
            force_reinstall=True,
        )

        self.assertIn("--upgrade", args)
        self.assertIn("--force-reinstall", args)

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

    def test_gallery_dl_is_required_for_yt_dlp_runtime(self):
        self.assertIn("gallery-dl", YTDLP_RUNTIME_PACKAGES)

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

    def test_missing_gallery_dl_is_installed_from_index(self):
        packages, cleanup = build_package_install_plan(
            {
                "yt-dlp": "1.0",
                "yt-dlp-apple-webkit-jsi": "1.0",
                "curl-cffi": "1.0",
                "gallery-dl": "not installed",
            },
            {"gallery-dl": ["2.0"]},
            package_source=parse_package_source(json.dumps({"mode": "stable"})),
        )

        self.assertEqual(packages, ["gallery-dl==2.0"])
        self.assertEqual(cleanup, ["gallery-dl"])

    def test_missing_curl_cffi_is_not_reported_as_available_update_by_default(self):
        lines = build_package_update_lines(
            {"curl-cffi": "not installed"},
            {"curl-cffi": ["2.0"]},
        )

        self.assertEqual(lines, [])

    def test_missing_curl_cffi_can_be_reported_as_available_update(self):
        lines = build_package_update_lines(
            {"curl-cffi": "not installed"},
            {"curl-cffi": ["2.0"]},
            include_missing=True,
        )

        self.assertEqual(lines, ["curl-cffi: not installed -> 2.0"])

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

    def test_custom_source_disables_patches(self):
        custom_source = parse_package_source(json.dumps({"mode": "custom"}))
        stable_source = parse_package_source(json.dumps({"mode": "stable"}))

        self.assertEqual(custom_source["patch_mode"], "off")
        self.assertEqual(stable_source["patch_mode"], "webkit")

    def test_legacy_disable_setting_turns_patches_off(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "disable_webkit_jsi_patch": True,
        }))

        self.assertEqual(source["patch_mode"], "off")

    def test_parse_package_source_reads_locked_versions(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "locked_versions": {
                "yt-dlp": "1.0",
                "unknown-package": "2.0",
                "pip": "",
            },
        }))

        self.assertEqual(source["locked_versions"], {"yt-dlp": "1.0"})
