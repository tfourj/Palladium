import json
import os
import pathlib
import tempfile
import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.packages import parse_package_source  # noqa: E402
from palladium_ytdlp.patching import (  # noqa: E402
    ensure_safe_ejs_runtime,
    normalize_youtube_patch_mode,
    patch_ejs_module_source,
)
from palladium_ytdlp.shared import EJS_MODULE_RELATIVE_PATH  # noqa: E402

UPSTREAM_EJS_SNIPPET = '''\
class EJSBaseJCP(JsChallengeProvider):
    JS_RUNTIME_NAME: str

    def _construct_stdin(self, player, preprocessed, requests, /):
        data = {}
        return f\'\'\'\\
        {self._lib_script.code}
        Object.assign(globalThis, lib);
        {self._core_script.code}
        console.log(JSON.stringify(jsc({json.dumps(data)})));
        \'\'\'
'''


def extract_guard_helper(patched_source):
    start = patched_source.index("def _palladium_guard_location_assignment")
    end = patched_source.index("class EJSBaseJCP")
    namespace = {}
    exec(patched_source[start:end], namespace)
    return namespace["_palladium_guard_location_assignment"]


class PatchEJSModuleSourceTests(unittest.TestCase):
    def test_patches_upstream_snippet(self):
        updated, changed, is_safe = patch_ejs_module_source(UPSTREAM_EJS_SNIPPET)

        self.assertTrue(changed)
        self.assertTrue(is_safe)
        self.assertIn("{_palladium_guard_location_assignment(self._lib_script.code)}", updated)
        self.assertIn("{_palladium_guard_location_assignment(self._core_script.code)}", updated)

    def test_patch_is_idempotent(self):
        first, _, _ = patch_ejs_module_source(UPSTREAM_EJS_SNIPPET)
        second, changed, is_safe = patch_ejs_module_source(first)

        self.assertEqual(first, second)
        self.assertFalse(changed)
        self.assertTrue(is_safe)

    def test_unknown_source_reports_unsafe(self):
        updated, changed, is_safe = patch_ejs_module_source("print('unrelated module')")

        self.assertFalse(changed)
        self.assertFalse(is_safe)
        self.assertEqual(updated, "print('unrelated module')")

    def test_guard_diverts_location_assignments(self):
        patched, _, _ = patch_ejs_module_source(UPSTREAM_EJS_SNIPPET)
        guard = extract_guard_helper(patched)

        shim = (
            'globalThis.location = new URL("https://www.youtube.com/watch?v=yt-dlp-wins");\n'
            'globalThis.location = {\n    hash: "",\n};\n'
        )
        guarded = guard(shim)
        self.assertNotIn("globalThis.location =", guarded)
        self.assertEqual(
            guarded.count('globalThis[typeof location === "undefined" ? "location" : "__palladium_location"] ='),
            2,
        )

    def test_guard_keeps_comparisons_and_reads(self):
        patched, _, _ = patch_ejs_module_source(UPSTREAM_EJS_SNIPPET)
        guard = extract_guard_helper(patched)

        untouched = 'if (globalThis.location === undefined) { use(globalThis.location.href); }'
        self.assertEqual(guard(untouched), untouched)


class EnsureSafeEJSRuntimeTests(unittest.TestCase):
    def test_patches_module_in_install_target(self):
        with tempfile.TemporaryDirectory() as target:
            module_path = pathlib.Path(target) / EJS_MODULE_RELATIVE_PATH
            module_path.parent.mkdir(parents=True)
            module_path.write_text(UPSTREAM_EJS_SNIPPET, encoding="utf-8")

            self.assertTrue(ensure_safe_ejs_runtime(target))

            patched = module_path.read_text(encoding="utf-8")
            self.assertIn("def _palladium_guard_location_assignment(", patched)
            self.assertFalse(os.path.exists(str(module_path) + ".tmp"))

            self.assertTrue(ensure_safe_ejs_runtime(target))
            self.assertEqual(module_path.read_text(encoding="utf-8"), patched)

    def test_missing_module_returns_false(self):
        with tempfile.TemporaryDirectory() as target:
            self.assertFalse(ensure_safe_ejs_runtime(target))


class YouTubePatchModeParsingTests(unittest.TestCase):
    def test_normalize_falls_back_to_default(self):
        self.assertEqual(normalize_youtube_patch_mode(None), "webkit")
        self.assertEqual(normalize_youtube_patch_mode(""), "webkit")
        self.assertEqual(normalize_youtube_patch_mode("bogus"), "webkit")
        self.assertEqual(normalize_youtube_patch_mode("both"), "webkit")
        self.assertEqual(normalize_youtube_patch_mode(" EJS "), "ejs")

    def test_parse_package_source_reads_patch_mode(self):
        for mode in ("webkit", "ejs", "off"):
            source = parse_package_source(json.dumps({
                "mode": "stable",
                "youtube_patch_mode": mode,
            }))
            self.assertEqual(source["patch_mode"], mode)

    def test_explicit_patch_mode_wins_over_legacy_flag(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "youtube_patch_mode": "webkit",
            "disable_webkit_jsi_patch": True,
        }))

        self.assertEqual(source["patch_mode"], "webkit")


if __name__ == "__main__":
    unittest.main()
