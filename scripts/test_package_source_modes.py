import json
import os
import pathlib
import sys
import tempfile
import types
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Palladium" / "Services" / "Python"))

from palladium_ytdlp.packages import (  # noqa: E402
    build_package_install_plan,
    build_package_update_lines,
    collect_versions,
    install_payload_zip,
    parse_package_source,
)
from palladium_ytdlp.entrypoints import invalidate_runtime_package_modules  # noqa: E402
from palladium_ytdlp.gallery import gallery_item_media_type  # noqa: E402


class PackageSourceModeTests(unittest.TestCase):
    def write_curl_cffi_package(self, root, version):
        root = pathlib.Path(root)
        (root / "curl_cffi").mkdir(parents=True, exist_ok=True)
        dist_info = root / f"curl_cffi-{version}.dist-info"
        dist_info.mkdir()
        (dist_info / "METADATA").write_text(
            f"Metadata-Version: 2.1\nName: curl-cffi\nVersion: {version}\n",
            encoding="utf-8",
        )

    def zip_directory(self, source_dir, zip_path):
        source_dir = pathlib.Path(source_dir)
        with zipfile.ZipFile(zip_path, "w") as archive:
            for path in source_dir.rglob("*"):
                archive.write(path, path.relative_to(source_dir))

    def with_bundled_curl_cffi(self, version):
        temp_dir = tempfile.TemporaryDirectory()
        root = pathlib.Path(temp_dir.name)
        self.write_curl_cffi_package(root, version)
        return temp_dir

    def test_bundled_curl_cffi_is_not_updated_by_pip(self):
        previous = os.environ.get("PALLADIUM_BUNDLED_PYTHON_PACKAGES")
        try:
            with self.with_bundled_curl_cffi("0.15.1b2") as bundled:
                os.environ["PALLADIUM_BUNDLED_PYTHON_PACKAGES"] = bundled
                packages, cleanup = build_package_install_plan(
                    {"curl-cffi": "0.15.1b2"},
                    {"curl-cffi": ["0.16.0"]},
                    package_source=parse_package_source(json.dumps({"mode": "stable"})),
                )
                lines = build_package_update_lines(
                    {"curl-cffi": "0.15.1b2"},
                    {"curl-cffi": ["0.16.0"]},
                )
        finally:
            if previous is None:
                os.environ.pop("PALLADIUM_BUNDLED_PYTHON_PACKAGES", None)
            else:
                os.environ["PALLADIUM_BUNDLED_PYTHON_PACKAGES"] = previous

        self.assertEqual(packages, [])
        self.assertEqual(cleanup, [])
        self.assertEqual(lines, [])

    def test_bundled_curl_cffi_version_is_labeled(self):
        previous = os.environ.get("PALLADIUM_BUNDLED_PYTHON_PACKAGES")
        try:
            with self.with_bundled_curl_cffi("0.15.1b2") as bundled:
                os.environ["PALLADIUM_BUNDLED_PYTHON_PACKAGES"] = bundled
                versions = collect_versions(allow_cache_fallback=False)
        finally:
            if previous is None:
                os.environ.pop("PALLADIUM_BUNDLED_PYTHON_PACKAGES", None)
            else:
                os.environ["PALLADIUM_BUNDLED_PYTHON_PACKAGES"] = previous

        self.assertEqual(versions["curl-cffi"], "0.15.1b2 (bundled)")

    def test_payload_zip_installs_bundled_layout_for_selected_platform(self):
        previous_payload_target = os.environ.get("PALLADIUM_MANUAL_PAYLOAD_PACKAGES")
        previous_site_packages = os.environ.get("PALLADIUM_PAYLOAD_SITE_PACKAGES")
        try:
            with tempfile.TemporaryDirectory() as temp:
                root = pathlib.Path(temp)
                source = root / "source"
                target = root / "target"
                zip_path = root / "payload.zip"
                device_packages = source / "curl_cffi_ios_payload" / "site-packages-iphoneos"
                simulator_packages = source / "curl_cffi_ios_payload" / "site-packages-iphonesimulator"
                self.write_curl_cffi_package(device_packages, "1.0")
                self.write_curl_cffi_package(simulator_packages, "2.0")
                self.zip_directory(source, zip_path)

                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = str(target)
                os.environ["PALLADIUM_PAYLOAD_SITE_PACKAGES"] = "site-packages-iphonesimulator"
                installed = install_payload_zip(zip_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)
        finally:
            if previous_payload_target is None:
                os.environ.pop("PALLADIUM_MANUAL_PAYLOAD_PACKAGES", None)
            else:
                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = previous_payload_target
            if previous_site_packages is None:
                os.environ.pop("PALLADIUM_PAYLOAD_SITE_PACKAGES", None)
            else:
                os.environ["PALLADIUM_PAYLOAD_SITE_PACKAGES"] = previous_site_packages

        self.assertEqual(installed, ["curl-cffi"])
        self.assertEqual(versions["curl-cffi"], "2.0 (payload)")

    def test_payload_zip_installs_flat_site_packages_layout(self):
        previous = os.environ.get("PALLADIUM_MANUAL_PAYLOAD_PACKAGES")
        try:
            with tempfile.TemporaryDirectory() as temp:
                root = pathlib.Path(temp)
                source = root / "source"
                target = root / "target"
                zip_path = root / "payload.zip"
                self.write_curl_cffi_package(source, "3.0")
                self.zip_directory(source, zip_path)

                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = str(target)
                installed = install_payload_zip(zip_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)
        finally:
            if previous is None:
                os.environ.pop("PALLADIUM_MANUAL_PAYLOAD_PACKAGES", None)
            else:
                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = previous

        self.assertEqual(installed, ["curl-cffi"])
        self.assertEqual(versions["curl-cffi"], "3.0 (payload)")

    def test_payload_zip_rejects_unsupported_package_contents(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "source"
            source.mkdir()
            (source / "notes.txt").write_text("not a package", encoding="utf-8")
            zip_path = root / "payload.zip"
            self.zip_directory(source, zip_path)

            with self.assertRaises(ValueError):
                install_payload_zip(zip_path, root / "target")

    def test_payload_zip_replaces_stale_payload_entries(self):
        previous = os.environ.get("PALLADIUM_MANUAL_PAYLOAD_PACKAGES")
        try:
            with tempfile.TemporaryDirectory() as temp:
                root = pathlib.Path(temp)
                source = root / "source"
                target = root / "target"
                zip_path = root / "payload.zip"
                self.write_curl_cffi_package(target, "1.0")
                self.write_curl_cffi_package(source, "2.0")
                self.zip_directory(source, zip_path)

                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = str(target)
                install_payload_zip(zip_path, target)
                versions = collect_versions(install_target=str(target), allow_cache_fallback=False)
                stale_dist_info = target / "curl_cffi-1.0.dist-info"
                stale_dist_info_exists = stale_dist_info.exists()
        finally:
            if previous is None:
                os.environ.pop("PALLADIUM_MANUAL_PAYLOAD_PACKAGES", None)
            else:
                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = previous

        self.assertFalse(stale_dist_info_exists)
        self.assertEqual(versions["curl-cffi"], "2.0 (payload)")

    def test_payload_curl_cffi_version_takes_precedence_over_bundled_version(self):
        previous_payload = os.environ.get("PALLADIUM_MANUAL_PAYLOAD_PACKAGES")
        previous_bundled = os.environ.get("PALLADIUM_BUNDLED_PYTHON_PACKAGES")
        try:
            with self.with_bundled_curl_cffi("1.0") as bundled, tempfile.TemporaryDirectory() as payload:
                self.write_curl_cffi_package(payload, "2.0")
                os.environ["PALLADIUM_BUNDLED_PYTHON_PACKAGES"] = bundled
                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = payload
                versions = collect_versions(install_target=payload, allow_cache_fallback=False)
        finally:
            if previous_payload is None:
                os.environ.pop("PALLADIUM_MANUAL_PAYLOAD_PACKAGES", None)
            else:
                os.environ["PALLADIUM_MANUAL_PAYLOAD_PACKAGES"] = previous_payload
            if previous_bundled is None:
                os.environ.pop("PALLADIUM_BUNDLED_PYTHON_PACKAGES", None)
            else:
                os.environ["PALLADIUM_BUNDLED_PYTHON_PACKAGES"] = previous_bundled

        self.assertEqual(versions["curl-cffi"], "2.0 (payload)")

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


def load_tests(loader, tests, pattern):
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromTestCase(PackageSourceModeTests))
    suite.addTests(loader.discover(str(ROOT / "scripts" / "python_tests"), top_level_dir=str(ROOT)))
    return suite


if __name__ == "__main__":
    unittest.main()
