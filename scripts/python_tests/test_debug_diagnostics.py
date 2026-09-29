import json
import unittest
from unittest import mock

from . import helpers  # noqa: F401
from palladium_ytdlp import diagnostics
from palladium_ytdlp.ffmpeg_bridge import BridgeCommandResult


def run(name, argument=None):
    return json.loads(diagnostics.run_debug_diagnostic(name, json.dumps(argument) if argument is not None else ""))


class DebugDiagnosticsTests(unittest.TestCase):
    def test_python_eval_captures_output_and_trailing_expression(self):
        result = run("python_eval", {"source": "value = 6\nprint('ready')\nvalue * 7"})
        self.assertTrue(result["ok"])
        self.assertEqual(result["output"], "ready\n42\n")
        self.assertIsInstance(result["duration_ms"], int)

    def test_python_eval_isolates_namespaces(self):
        run("python_eval", {"source": "saved = 1"})
        result = run("python_eval", {"source": "print('saved' in globals())"})
        self.assertEqual(result["output"], "False\n")

    def test_errors_and_system_exit_are_reported(self):
        for source, error in (("1/0", "ZeroDivisionError"), ("raise SystemExit(3)", "SystemExit")):
            with self.subTest(source=source):
                result = run("python_eval", {"source": source})
                self.assertFalse(result["ok"])
                self.assertTrue(result["error"].startswith(error))
                self.assertIn("Traceback", result["output"])

    def test_keyboard_interrupt_propagates_for_cancellation(self):
        with self.assertRaises(KeyboardInterrupt):
            run("python_eval", {"source": "raise KeyboardInterrupt"})

    def test_invalid_requests_are_reported(self):
        self.assertIn("unknown diagnostic", run("missing")["error"])
        self.assertIn("JSON object", run("python_eval", [1])["error"])

    def test_python_info_lists_managed_packages(self):
        with mock.patch("palladium_ytdlp.packages.installed_version", return_value=None):
            result = run("python_info")
        self.assertTrue(result["ok"])
        self.assertEqual(result["details"]["packages"]["yt-dlp"], "not installed")
        self.assertIn("cffi", result["details"]["packages"])

    def test_quickjs_bridge_evaluates_requested_source(self):
        bridge = mock.Mock(version="0.16.2")
        bridge.evaluate.return_value = "2\n"
        with mock.patch("palladium_ytdlp.quickjs_bridge.QuickJSBridge", return_value=bridge):
            result = run("quickjs_bridge", {"source": "console.log(1 + 1)"})
        bridge.evaluate.assert_called_once_with("console.log(1 + 1)")
        self.assertEqual(result["output"], "2\n")
        self.assertEqual(result["details"]["version"], "0.16.2")

    def test_ffmpeg_bridge_encodes_and_probes_test_media(self):
        bridge = mock.Mock()
        bridge.probe_capabilities.return_value = {"versions": {"ffmpeg": "8.0"}, "features": {}}
        bridge.run_ffmpeg.return_value = BridgeCommandResult(0, "", "")
        bridge.probe_metadata.return_value = {
            "streams": [{"codec_name": "mpeg4"}, {"codec_name": "aac"}],
            "format": {"duration": "1.000000"},
        }
        with mock.patch("palladium_ytdlp.ffmpeg_bridge.SwiftFFmpegBridge", return_value=bridge):
            result = run("ffmpeg_bridge")
        self.assertTrue(result["ok"])
        self.assertEqual(result["details"]["encoded_streams"], ["mpeg4", "aac"])
        self.assertIn("lavfi", bridge.run_ffmpeg.call_args.args[0])

    def test_ffmpeg_bridge_reports_failed_encode(self):
        bridge = mock.Mock()
        bridge.probe_capabilities.return_value = {}
        bridge.run_ffmpeg.return_value = BridgeCommandResult(1, "", "Unknown encoder")
        with mock.patch("palladium_ytdlp.ffmpeg_bridge.SwiftFFmpegBridge", return_value=bridge):
            result = run("ffmpeg_bridge")
        self.assertFalse(result["ok"])
        self.assertEqual(result["output"], "Unknown encoder")
        bridge.probe_metadata.assert_not_called()


if __name__ == "__main__":
    unittest.main()
