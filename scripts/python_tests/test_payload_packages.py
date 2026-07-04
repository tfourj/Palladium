import pathlib
import tempfile
import unittest

from scripts.python_tests.helpers import (
    bundled_curl_cffi,
    temporary_env,
    write_curl_cffi_package,
    zip_directory,
)

from palladium_ytdlp.packages import collect_versions, install_payload_zip  # noqa: E402


class PayloadPackageTests(unittest.TestCase):
    def test_payload_zip_installs_bundled_layout_for_selected_platform(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            target = root / "target"
            zip_path = root / "payload.zip"
            device_packages = source / "curl_cffi_ios_payload" / "site-packages-iphoneos"
            simulator_packages = source / "curl_cffi_ios_payload" / "site-packages-iphonesimulator"
            write_curl_cffi_package(device_packages, "1.0")
            write_curl_cffi_package(simulator_packages, "2.0")
            zip_directory(source, zip_path)

            with temporary_env(
                PALLADIUM_MANUAL_PAYLOAD_PACKAGES=target,
                PALLADIUM_PAYLOAD_SITE_PACKAGES="site-packages-iphonesimulator",
            ):
                installed = install_payload_zip(zip_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)

        self.assertEqual(installed, ["curl-cffi"])
        self.assertEqual(versions["curl-cffi"], "2.0 (payload)")

    def test_payload_zip_installs_flat_site_packages_layout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            target = root / "target"
            zip_path = root / "payload.zip"
            write_curl_cffi_package(source, "3.0")
            zip_directory(source, zip_path)

            with temporary_env(PALLADIUM_MANUAL_PAYLOAD_PACKAGES=target):
                installed = install_payload_zip(zip_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)

        self.assertEqual(installed, ["curl-cffi"])
        self.assertEqual(versions["curl-cffi"], "3.0 (payload)")

    def test_payload_zip_rejects_unsupported_package_contents(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            source.mkdir()
            (source / "notes.txt").write_text("not a package", encoding="utf-8")
            zip_path = root / "payload.zip"
            zip_directory(source, zip_path)

            with self.assertRaises(ValueError):
                install_payload_zip(zip_path, root / "target")

    def test_payload_zip_replaces_stale_payload_entries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            target = root / "target"
            zip_path = root / "payload.zip"
            write_curl_cffi_package(target, "1.0")
            write_curl_cffi_package(source, "2.0")
            zip_directory(source, zip_path)

            with temporary_env(PALLADIUM_MANUAL_PAYLOAD_PACKAGES=target):
                install_payload_zip(zip_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)
                stale_dist_info = target / "curl_cffi-1.0.dist-info"
                stale_dist_info_exists = stale_dist_info.exists()

        self.assertFalse(stale_dist_info_exists)
        self.assertEqual(versions["curl-cffi"], "2.0 (payload)")

    def test_payload_curl_cffi_version_takes_precedence_over_bundled_version(self):
        with bundled_curl_cffi("1.0") as bundled, tempfile.TemporaryDirectory() as payload:
            write_curl_cffi_package(payload, "2.0")
            with temporary_env(
                PALLADIUM_BUNDLED_PYTHON_PACKAGES=bundled,
                PALLADIUM_MANUAL_PAYLOAD_PACKAGES=payload,
            ):
                versions = collect_versions(install_target=payload, allow_cache_fallback=False)

        self.assertEqual(versions["curl-cffi"], "2.0 (payload)")
