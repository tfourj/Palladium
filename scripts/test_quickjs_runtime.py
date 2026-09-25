"""Offline tests of the actual native bridge and yt-dlp's EJS integration.

Requires an Apple Silicon Mac, Xcode, Frameworks/QuickJS, and the same yt-dlp
and EJS versions as CI. Compiles the production sources into a temporary dylib.
"""

import contextlib
import ctypes
import importlib
import io
import json
import os
import pathlib
import platform
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

from scripts.python_tests import helpers
from palladium_ytdlp import quickjs_bridge

import yt_dlp
from yt_dlp.extractor.youtube import YoutubeIE
from yt_dlp.extractor.youtube.jsc._builtin.quickjs import QuickJSJCP
from yt_dlp.extractor.youtube.jsc._director import JsChallengeRequestDirector
from yt_dlp.extractor.youtube.jsc._registry import _jsc_preferences
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeRequest, JsChallengeType, NChallengeInput, SigChallengeInput,
    JsChallengeProviderResponse, JsChallengeResponse, NChallengeOutput, SigChallengeOutput,
)
from yt_dlp.utils._jsruntime import QuickJsRuntime


class NativeResult(ctypes.Structure):
    _fields_ = [
        ("status", ctypes.c_int), ("output", ctypes.c_void_p),
        ("output_length", ctypes.c_size_t), ("error", ctypes.c_void_p),
    ]


def setUpModule():
    global native
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("QuickJS native tests require an arm64 Mac")
    temporary = tempfile.TemporaryDirectory(prefix="palladium-quickjs-tests-")
    unittest.addModuleCleanup(temporary.cleanup)
    engine = helpers.ROOT / "Frameworks" / "QuickJS"
    bridge = helpers.ROOT / "Palladium" / "Services" / "QuickJS"
    library = pathlib.Path(temporary.name) / "libpalladium-quickjs.dylib"
    environment = os.environ.copy()
    environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    subprocess.run([
        "xcrun", "clang", "-arch", "arm64", "-dynamiclib", "-O2", "-std=c11", "-fobjc-arc",
        "-framework", "Foundation", "-D_GNU_SOURCE", "-DQUICKJS_NG_BUILD",
        "-I", str(engine), "-I", str(bridge),
        *(str(engine / name) for name in ("quickjs.c", "dtoa.c", "libregexp.c", "libunicode.c")),
        str(bridge / "evaluate.c"), str(bridge / "bridge.m"), "-o", str(library),
    ], check=True, env=environment)
    native = ctypes.CDLL(str(library), mode=ctypes.RTLD_GLOBAL)
    native.palladium_qjs_evaluate.argtypes = [
        ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_uint, ctypes.c_size_t,
    ]
    native.palladium_qjs_evaluate.restype = NativeResult
    native.palladium_qjs_result_free.argtypes = [ctypes.POINTER(NativeResult)]
    native.palladium_qjs_result_free.restype = None


class NativeExecutionTests(unittest.TestCase):
    def setUp(self):
        self.bridge = quickjs_bridge.QuickJSBridge()

    def test_version_unicode_and_console_arguments(self):
        self.assertEqual(self.bridge.version, "0.16.2")
        self.assertEqual(self.bridge.evaluate('console.log("živjo 🌍", 42, "\\u0000")'), "živjo 🌍 42 \x00\n")

    def test_promise_jobs_and_handled_rejection(self):
        self.assertEqual(self.bridge.evaluate('Promise.resolve().then(() => console.log("done"))'), "done\n")
        self.assertEqual(
            self.bridge.evaluate('Promise.reject("handled").catch(() => console.log("caught"))'), "caught\n")

    def test_exceptions_and_unhandled_rejections(self):
        for source in ('throw new Error("failure")', 'Promise.reject(new Error("failure"))'):
            with self.subTest(source=source), self.assertRaisesRegex(RuntimeError, "failure"):
                self.bridge.evaluate(source)

    def test_contexts_are_isolated_and_survive_errors(self):
        for _ in range(20):
            self.bridge.evaluate("globalThis.saved = 123")
            with self.assertRaises(RuntimeError):
                self.bridge.evaluate("throw 123")
            self.assertEqual(self.bridge.evaluate("console.log(typeof saved)"), "undefined\n")

    def test_no_process_or_filesystem_api(self):
        self.assertEqual(
            self.bridge.evaluate('console.log(typeof std, typeof os, typeof process, typeof require)'),
            "undefined undefined undefined undefined\n",
        )

    def test_output_is_bounded(self):
        with self.assertRaisesRegex(RuntimeError, "output_limit"):
            self.bridge.evaluate('const text = "x".repeat(1024 * 1024); for (let i = 0; i < 20; i++) console.log(text)')

    def test_timeout_and_memory_exhaustion(self):
        for source, timeout, memory, status in (
            ("for (;;) {}", 30, 256 * 1024 * 1024, 2),
            ('const a=[]; for (;;) a.push(new Array(10000).fill("memory"))', 2000, 1024 * 1024, 1),
            ("console.log(1)", 2000, 1, 5),
        ):
            with self.subTest(status=status):
                data = source.encode()
                started = time.monotonic()
                result = native.palladium_qjs_evaluate(data, len(data), b"", timeout, memory)
                try:
                    self.assertEqual(result.status, status)
                    self.assertLess(time.monotonic() - started, 3)
                finally:
                    native.palladium_qjs_result_free(ctypes.byref(result))

    def test_active_cancellation_interrupts_native_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = pathlib.Path(directory) / "cancel"
            timer = threading.Timer(0.05, marker.touch)
            timer.start()
            started = time.monotonic()
            try:
                with self.assertRaises(KeyboardInterrupt):
                    self.bridge.evaluate("for (;;) {}", str(marker))
            finally:
                timer.join()
            self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(self.bridge.evaluate("console.log(42)"), "42\n")

    def test_invalid_requests_return_errors(self):
        for request in (
            {}, {"operation": "evaluate", "source": 42},
            {"operation": "evaluate", "source": "", "cancel_file": None},
        ):
            with self.subTest(request=request):
                self.assertFalse(self.bridge._invoke(request)["ok"])


class ProviderIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.output))
        self.enterContext(quickjs_bridge.embedded_quickjs())
        self.downloader = self.enterContext(yt_dlp.YoutubeDL({
            **quickjs_bridge.quickjs_default_options(), "quiet": True, "cachedir": False,
        }))
        self.enterContext(mock.patch.object(
            self.downloader, "urlopen", side_effect=AssertionError("Offline tests must not use the network")
        ))
        self.logger = mock.Mock()
        self.logger.log_level = 100
        self.logger.LogLevel.TRACE = 0
        self.provider = QuickJSJCP(YoutubeIE(self.downloader), self.logger, {})
        self.requests = [
            JsChallengeRequest(JsChallengeType.N, NChallengeInput("https://example.com/player.js", ["abc"])),
            JsChallengeRequest(JsChallengeType.SIG, SigChallengeInput("https://example.com/player.js", ["123"])),
        ]

    def test_runtime_detection_never_launches_qjs(self):
        with mock.patch("yt_dlp.utils._jsruntime._get_exe_version_output", side_effect=AssertionError("subprocess")):
            self.assertTrue(self.provider.is_available())
            self.assertEqual(self.provider.runtime_info.name, "quickjs-ng")
            self.assertEqual(self.provider.runtime_info.path, "embedded")

    def test_actual_ejs_preprocesses_and_solves_both_challenges(self):
        player = (helpers.ROOT / "scripts/fixtures/quickjs_player.js").read_text()
        with mock.patch.object(self.provider, "_get_player", return_value=player):
            responses = list(self.provider.bulk_solve(self.requests))
        self.assertEqual(responses[0].response.output.results, {"abc": "cba"})
        self.assertEqual(responses[1].response.output.results, {"123": "23"})

    def test_actual_ejs_executes_preprocessed_player(self):
        script = self.provider._construct_stdin(
            '_result.n = x => x.split("").reverse().join(""); _result.sig = x => x.slice(1);',
            True, self.requests,
        )
        result = json.loads(self.provider._run_js_runtime(script))
        self.assertEqual(result["responses"][0]["data"], {"abc": "cba"})
        self.assertEqual(result["responses"][1]["data"], {"123": "23"})

    def director_with_webkit(self):
        # Use the real WebKit provider/registration, replacing only native browser
        # execution so this remains deterministic and never opens a web view.
        webkit_type = importlib.import_module("yt_dlp_plugins.extractor.ytjsc").AppleWebKitJCP
        webkit = mock.Mock(spec=webkit_type)
        webkit.PROVIDER_KEY = "AppleWebKit"
        webkit.PROVIDER_NAME = "apple-webkit-jsi"
        webkit.is_available.return_value = True

        def solve(requests):
            for request in requests:
                output_type = NChallengeOutput if request.type == JsChallengeType.N else SigChallengeOutput
                yield JsChallengeProviderResponse(request, JsChallengeResponse(
                    request.type, output_type({challenge: "fallback" for challenge in request.input.challenges})))

        webkit.bulk_solve.side_effect = solve
        director = JsChallengeRequestDirector(self.logger)
        director.register_provider(webkit)
        director.register_provider(self.provider)
        for preference in _jsc_preferences.value:
            director.register_preference(preference)
        return director, webkit

    def test_default_webkit_selection_skips_quickjs(self):
        with helpers.temporary_env(PALLADIUM_JS_RUNTIME=None), yt_dlp.YoutubeDL({
            **quickjs_bridge.runtime_default_options(), "quiet": True, "cachedir": False,
        }) as downloader:
            self.provider = QuickJSJCP(YoutubeIE(downloader), self.logger, {})
            self.assertFalse(self.provider.is_available())
            director, webkit = self.director_with_webkit()
            with mock.patch.object(quickjs_bridge.QuickJSBridge, "evaluate") as evaluate:
                responses = director.bulk_solve(self.requests)
            self.assertEqual(len(responses), 2)
            webkit.bulk_solve.assert_called_once()
            evaluate.assert_not_called()

    def test_quickjs_is_preferred_to_webkit(self):
        director, webkit = self.director_with_webkit()
        player = (helpers.ROOT / "scripts/fixtures/quickjs_player.js").read_text()
        with mock.patch.object(self.provider, "_get_player", return_value=player):
            responses = director.bulk_solve(self.requests)
        self.assertEqual(len(responses), 2)
        webkit.bulk_solve.assert_not_called()

    def test_runtime_error_falls_back_at_challenge_level(self):
        director, webkit = self.director_with_webkit()
        with mock.patch.object(self.provider, "_construct_stdin", return_value='throw new Error("failed")'), \
             mock.patch.object(self.provider, "_get_player", return_value="fixture"):
            responses = director.bulk_solve(self.requests)
        self.assertEqual(len(responses), 2)
        webkit.bulk_solve.assert_called_once()
        self.assertFalse(self.provider.is_available())
        self.assertIn("allowing WebKit fallback", self.output.getvalue())

    def test_only_unsolved_challenges_reach_webkit(self):
        director, webkit = self.director_with_webkit()
        partial_response = JsChallengeProviderResponse(
            self.requests[0], JsChallengeResponse(JsChallengeType.N, NChallengeOutput({"abc": "cba"})))
        with mock.patch.object(self.provider, "bulk_solve", return_value=iter([partial_response])):
            responses = director.bulk_solve(self.requests)
        self.assertEqual(len(responses), 2)
        webkit.bulk_solve.assert_called_once_with([self.requests[1]])

    def test_cancellation_does_not_fall_back(self):
        director, webkit = self.director_with_webkit()
        with mock.patch.object(self.provider, "_get_player", return_value="fixture"), \
             mock.patch.object(quickjs_bridge.QuickJSBridge, "evaluate", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                director.bulk_solve(self.requests)
        webkit.bulk_solve.assert_not_called()


class InvocationTests(unittest.TestCase):
    runtime = "quickjs"

    def setUp(self):
        self.flow = importlib.import_module("palladium_ytdlp.ytdlp")
        self.directory = self.enterContext(tempfile.TemporaryDirectory())
        self.enterContext(helpers.temporary_env(
            PALLADIUM_CACHE_DIR=self.directory, PALLADIUM_DOWNLOADS=self.directory,
            PALLADIUM_PYTHON_PACKAGES=None, PALLADIUM_CANCEL_FILE=None,
            PALLADIUM_JS_RUNTIME=self.runtime,
        ))
        self.enterContext(mock.patch.object(sys, "argv", ["palladium-test"]))
        self.enterContext(mock.patch.object(sys, "__stdout__", io.StringIO()))
        self.enterContext(mock.patch.object(sys, "__stderr__", io.StringIO()))
        self.enterContext(mock.patch.object(
            self.flow, "patch_ytdlp_for_swiftffmpeg", side_effect=lambda _: contextlib.nullcontext()))
        self.invocations = []

    def run_module(self, *args, **kwargs):
        options = yt_dlp.parse_options(["--ignore-config", *sys.argv[1:]]).ydl_opts
        self.assertEqual(options["js_runtimes"], {"quickjs": {"path": None}} if self.runtime == "quickjs" else {})
        self.assertIn("ejs:github", options["remote_components"])
        self.assertEqual(QuickJsRuntime().info.name, "quickjs-ng")
        self.invocations.append(options)

    def test_download_activates_embedded_runtime(self):
        with mock.patch.object(self.flow, "runtime_package_names", return_value=()), \
             mock.patch.object(self.flow, "apply_youtube_patches"), \
             mock.patch.object(self.flow, "SwiftFFmpegBridge"), \
             mock.patch.object(self.flow, "YTDLPFFmpegBridgeAdapter"), \
             mock.patch.object(self.flow.runpy, "run_module", side_effect=self.run_module):
            result = json.loads(self.flow.run_yt_dlp_flow(
                download_url_override="https://example.com/watch", run_output_dir_override=self.directory,
                download_preset_override="custom", extra_args_override="", download_playlist_override=False,
                auto_retry_failed_downloads_override=False,
            ))
        self.assertEqual(result["yt_exit_code"], 0, result["output"])
        self.assertEqual(len(self.invocations), 1)

    def test_thumbnail_retry_activates_embedded_runtime(self):
        with mock.patch.object(self.flow.runpy, "run_module", side_effect=self.run_module):
            success, error = self.flow.run_retry_without_thumbnails(
                retry_candidate={"index": 2}, download_url="https://example.com/playlist",
                run_output_dir=self.directory, cache_dir=self.directory, download_playlist=True,
                output_args=[], download_behavior_args=["--embed-thumbnail"],
                preset_args=[], extra_args=[], bridge_adapter=None,
            )
        self.assertTrue(success, error)
        self.assertEqual(len(self.invocations), 1)

    def test_format_discovery_activates_embedded_runtime(self):
        def extract(downloader, url, download):
            self.assertEqual(downloader.params["js_runtimes"], {"quickjs": {}} if self.runtime == "quickjs" else {})
            self.assertIn("ejs:github", downloader.params["remote_components"])
            if self.runtime == "quickjs":
                self.assertEqual(downloader._js_runtimes["quickjs"].info.name, "quickjs-ng")
            return {"id": "fixture", "title": "fixture", "formats": []}
        with mock.patch.object(yt_dlp.YoutubeDL, "extract_info", autospec=True, side_effect=extract):
            result = json.loads(self.flow.list_yt_dlp_formats("https://example.com/watch"))
        self.assertTrue(result["success"], result["output"])


class WebKitInvocationTests(InvocationTests):
    runtime = "webkit"


class AdapterLifecycleTests(unittest.TestCase):
    def test_restores_hooks_after_exceptions_and_nested_scopes(self):
        original_info = QuickJsRuntime._info
        original_run = QuickJSJCP._run_js_runtime
        original_preferences = set(_jsc_preferences.value)
        with self.assertRaisesRegex(ValueError, "operation failed"):
            with quickjs_bridge.embedded_quickjs():
                outer_info = QuickJsRuntime._info
                with quickjs_bridge.embedded_quickjs():
                    self.assertIsNot(QuickJsRuntime._info, outer_info)
                self.assertIs(QuickJsRuntime._info, outer_info)
                raise ValueError("operation failed")
        self.assertIs(QuickJsRuntime._info, original_info)
        self.assertIs(QuickJSJCP._run_js_runtime, original_run)
        self.assertEqual(_jsc_preferences.value, original_preferences)

    def test_missing_engine_does_not_probe_a_subprocess(self):
        with mock.patch.object(quickjs_bridge, "QuickJSBridge", side_effect=RuntimeError("missing")), \
             mock.patch("yt_dlp.utils._jsruntime._get_exe_version_output", side_effect=AssertionError("subprocess")), \
             quickjs_bridge.embedded_quickjs():
            self.assertIsNone(QuickJsRuntime().info)

    def test_incompatible_hooks_leave_modules_untouched(self):
        with mock.patch.object(QuickJSJCP, "_run_js_runtime", None), quickjs_bridge.embedded_quickjs():
            self.assertIsNone(QuickJSJCP._run_js_runtime)

    def test_package_reload_uses_fresh_runtime_classes(self):
        from palladium_ytdlp.runtime import invalidate_runtime_package_modules
        prefixes = ("yt_dlp", "yt_dlp_plugins")
        def matching(name):
            return any(name == prefix or name.startswith(prefix + ".") for prefix in prefixes)
        saved = {name: module for name, module in sys.modules.items() if matching(name)}
        try:
            invalidate_runtime_package_modules()
            with quickjs_bridge.embedded_quickjs():
                module = importlib.import_module("yt_dlp.utils._jsruntime")
                self.assertIsNot(module.QuickJsRuntime, QuickJsRuntime)
                self.assertEqual(module.QuickJsRuntime().info.name, "quickjs-ng")
        finally:
            for name in list(sys.modules):
                if matching(name):
                    sys.modules.pop(name)
            sys.modules.update(saved)

    def test_custom_runtime_arguments_override_defaults(self):
        options = yt_dlp.parse_options([
            "--ignore-config", *quickjs_bridge.QUICKJS_DEFAULT_ARGS, "--no-js-runtimes",
        ]).ydl_opts
        self.assertEqual(options["js_runtimes"], {})


if __name__ == "__main__":
    unittest.main()
