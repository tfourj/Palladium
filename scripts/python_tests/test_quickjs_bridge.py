import ctypes
import json
import pathlib
import tempfile
import unittest
from unittest import mock

from . import helpers  # noqa: F401
from palladium_ytdlp.quickjs_bridge import QuickJSBridge, quickjs_default_options


class QuickJSBridgeTests(unittest.TestCase):
    def bridge(self, response):
        bridge = QuickJSBridge.__new__(QuickJSBridge)
        bridge._invoke = mock.Mock(return_value=response)
        return bridge

    def test_native_cancellation_is_not_a_fallback_error(self):
        bridge = self.bridge({"ok": False, "status": "cancelled"})
        with self.assertRaises(KeyboardInterrupt):
            bridge.evaluate("for (;;) {}")

    def test_existing_cancel_marker_skips_native_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = pathlib.Path(directory) / "cancel"
            marker.touch()
            bridge = self.bridge({"ok": True, "output": "should not run"})
            with self.assertRaises(KeyboardInterrupt):
                bridge.evaluate("console.log(1)", str(marker))
            bridge._invoke.assert_not_called()

    def test_invalid_output_and_execution_errors_are_reported(self):
        for response in ({"ok": True, "output": None}, {"ok": False, "status": "timeout"}):
            with self.subTest(response=response), self.assertRaises(RuntimeError):
                self.bridge(response).evaluate("source")

    def test_native_response_is_freed_even_when_json_is_invalid(self):
        for payload in (b'{"ok":true}', b'not json', b'[]'):
            with self.subTest(payload=payload):
                buffer = ctypes.create_string_buffer(payload)
                pointer = ctypes.addressof(buffer)
                bridge = QuickJSBridge.__new__(QuickJSBridge)
                bridge._run = mock.Mock(return_value=pointer)
                bridge._free = mock.Mock()
                if payload == b'{"ok":true}':
                    self.assertEqual(bridge._invoke({"operation": "info"}), {"ok": True})
                else:
                    with self.assertRaises((RuntimeError, ValueError)):
                        bridge._invoke({"operation": "info"})
                bridge._free.assert_called_once_with(pointer)
                self.assertEqual(json.loads(bridge._run.call_args.args[0]), {"operation": "info"})

    def test_format_options_use_the_app_solver_cache(self):
        with mock.patch.dict("os.environ", {"PALLADIUM_CACHE_DIR": "/tmp/app-cache"}):
            options = quickjs_default_options()
        self.assertEqual(options["cachedir"], "/tmp/app-cache")
        self.assertEqual(options["js_runtimes"], {"quickjs": {}})
        self.assertEqual(options["remote_components"], {"ejs:github"})
