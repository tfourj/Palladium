import pathlib
import tempfile
import unittest
import zipfile

from scripts.python_tests.helpers import (
    bundled_curl_cffi,
    temporary_env,
    write_curl_cffi_package,
    write_wheel_package,
    zip_directory,
)

from palladium_ytdlp.packages import clear_payload_packages, collect_versions, install_payload_zip  # noqa: E402


class PayloadPackageTests(unittest.TestCase):
    def test_payload_imports_direct_wheel(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            target = root / "target"
            wheel_path = root / "example_pkg-1.0-py3-none-any.whl"
            write_wheel_package(wheel_path, "example-pkg", "1.0")

            installed = install_payload_zip(wheel_path, target)
            package_dir_exists = (target / "example_pkg").is_dir()
            metadata_exists = (target / "example_pkg-1.0.dist-info" / "METADATA").is_file()

        self.assertEqual(installed, ["example-pkg"])
        self.assertTrue(package_dir_exists)
        self.assertTrue(metadata_exists)

    def test_payload_zip_imports_nested_wheels(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            target = root / "target"
            zip_path = root / "payload.zip"
            write_wheel_package(source / "wheels" / "alpha_pkg-1.0-py3-none-any.whl", "alpha-pkg", "1.0")
            write_wheel_package(source / "wheels" / "beta_pkg-2.0-py3-none-any.whl", "beta-pkg", "2.0")
            zip_directory(source, zip_path)

            installed = install_payload_zip(zip_path, target)
            alpha_exists = (target / "alpha_pkg").is_dir()
            beta_exists = (target / "beta_pkg").is_dir()

        self.assertEqual(installed, ["alpha-pkg", "beta-pkg"])
        self.assertTrue(alpha_exists)
        self.assertTrue(beta_exists)

    def test_payload_wheel_installs_purelib_and_platlib_data(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            target = root / "target"
            wheel_path = root / "data_pkg-1.0-py3-none-any.whl"
            write_wheel_package(
                wheel_path,
                "data-pkg",
                "1.0",
                extra_files={
                    "data_pkg-1.0.data/purelib/pure_pkg/__init__.py": "",
                    "data_pkg-1.0.data/platlib/plat_pkg/__init__.py": "",
                    "data_pkg-1.0.data/scripts/data-tool": "",
                },
            )

            installed = install_payload_zip(wheel_path, target)
            purelib_exists = (target / "pure_pkg").is_dir()
            platlib_exists = (target / "plat_pkg").is_dir()
            skipped_script_exists = (target / "data_pkg-1.0.data" / "scripts" / "data-tool").exists()

        self.assertEqual(installed, ["data-pkg"])
        self.assertTrue(purelib_exists)
        self.assertTrue(platlib_exists)
        self.assertFalse(skipped_script_exists)

    def test_payload_wheel_for_tracked_package_is_labeled_as_payload(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            target = root / "target"
            wheel_path = root / "yt_dlp-99.0-py3-none-any.whl"
            write_wheel_package(wheel_path, "yt-dlp", "99.0", modules=["yt_dlp"])

            with temporary_env(PALLADIUM_MANUAL_PAYLOAD_PACKAGES=target):
                installed = install_payload_zip(wheel_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)

        self.assertEqual(installed, ["yt-dlp"])
        self.assertEqual(versions["yt-dlp"], "99.0 (payload)")

    def test_clear_payload_packages_removes_imported_packages(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            target = root / "target"
            wheel_path = root / "yt_dlp-99.0-py3-none-any.whl"
            write_wheel_package(wheel_path, "yt-dlp", "99.0", modules=["yt_dlp"])

            with temporary_env(PALLADIUM_MANUAL_PAYLOAD_PACKAGES=target):
                install_payload_zip(wheel_path, target)
                removed = clear_payload_packages(target)
                target_exists = target.is_dir()
                remaining_entries = list(target.iterdir())
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)

        self.assertGreater(removed, 0)
        self.assertTrue(target_exists)
        self.assertEqual(remaining_entries, [])
        self.assertEqual(versions["yt-dlp"], "not installed")

    def test_payload_zip_rejects_duplicate_wheel_packages(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            target = root / "target"
            zip_path = root / "payload.zip"
            write_wheel_package(source / "one" / "example_pkg-1.0-py3-none-any.whl", "example-pkg", "1.0")
            write_wheel_package(source / "two" / "example_pkg-2.0-py3-none-any.whl", "example_pkg", "2.0")
            zip_directory(source, zip_path)

            with self.assertRaises(ValueError):
                install_payload_zip(zip_path, target)
            target_exists = target.exists()

        self.assertFalse(target_exists)

    def test_payload_zip_rejects_unsafe_nested_wheel_entries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            source.mkdir()
            wheel_path = source / "unsafe_pkg-1.0-py3-none-any.whl"
            with zipfile.ZipFile(wheel_path, "w") as archive:
                archive.writestr("unsafe_pkg/__init__.py", "")
                archive.writestr("../escape.py", "")
                archive.writestr(
                    "unsafe_pkg-1.0.dist-info/METADATA",
                    "Metadata-Version: 2.1\nName: unsafe-pkg\nVersion: 1.0\n",
                )
                archive.writestr(
                    "unsafe_pkg-1.0.dist-info/WHEEL",
                    "Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
                )
            zip_path = root / "payload.zip"
            target = root / "target"
            zip_directory(source, zip_path)

            with self.assertRaises(ValueError):
                install_payload_zip(zip_path, target)
            escaped_file_exists = (root / "escape.py").exists()
            target_exists = target.exists()

        self.assertFalse(escaped_file_exists)
        self.assertFalse(target_exists)

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
