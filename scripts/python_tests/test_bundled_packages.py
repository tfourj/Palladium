import json
import unittest

from scripts.python_tests.helpers import bundled_curl_cffi, temporary_env

from palladium_ytdlp.packages import (  # noqa: E402
    build_package_install_plan,
    build_package_update_lines,
    collect_versions,
    parse_package_source,
)


class BundledPackageTests(unittest.TestCase):
    def test_bundled_curl_cffi_is_not_updated_by_pip(self):
        with bundled_curl_cffi("0.15.1b2") as bundled, temporary_env(
            PALLADIUM_BUNDLED_PYTHON_PACKAGES=bundled,
        ):
            packages, cleanup = build_package_install_plan(
                {"curl-cffi": "0.15.1b2"},
                {"curl-cffi": ["0.16.0"]},
                package_source=parse_package_source(json.dumps({"mode": "stable"})),
            )
            lines = build_package_update_lines(
                {"curl-cffi": "0.15.1b2"},
                {"curl-cffi": ["0.16.0"]},
            )

        self.assertEqual(packages, [])
        self.assertEqual(cleanup, [])
        self.assertEqual(lines, [])

    def test_bundled_curl_cffi_version_is_labeled(self):
        with bundled_curl_cffi("0.15.1b2") as bundled, temporary_env(
            PALLADIUM_BUNDLED_PYTHON_PACKAGES=bundled,
        ):
            versions = collect_versions(allow_cache_fallback=False)

        self.assertEqual(versions["curl-cffi"], "0.15.1b2 (bundled)")
