"""Adapt yt-dlp's QuickJS provider to the engine linked into the iOS app."""

import contextlib
import ctypes
import json
import os


QUICKJS_DEFAULT_ARGS = ("--no-js-runtimes", "--js-runtimes", "quickjs")


def quickjs_default_options():
    options = {"js_runtimes": {"quickjs": {}}, "remote_components": {"ejs:github"}}
    cache_dir = os.environ.get("PALLADIUM_CACHE_DIR", "").strip()
    if cache_dir:
        options["cachedir"] = cache_dir
    return options


class QuickJSBridge:
    def __init__(self):
        candidates = [None]
        executable = os.environ.get("PALLADIUM_EXECUTABLE_PATH", "").strip()
        if executable:
            candidates.append(executable)
        last_error = None
        for path in candidates:
            try:
                self._library = ctypes.CDLL(path)
                self._run = self._library.palladium_quickjs_bridge_run
                self._run.argtypes = [ctypes.c_char_p]
                self._run.restype = ctypes.c_void_p
                self._free = self._library.palladium_quickjs_bridge_free
                self._free.argtypes = [ctypes.c_void_p]
                self._free.restype = None
                self.info = self._invoke({"operation": "info"})
                if not self.info.get("ok") or self.info.get("name") != "quickjs-ng":
                    raise RuntimeError("unexpected QuickJS bridge metadata")
                self.version = str(self.info["version"])
                self.version_tuple = tuple(int(part) for part in self.version.split("."))
                if self.version_tuple < (0, 12, 0):
                    raise RuntimeError("QuickJS-NG 0.12.0 or newer is required")
                return
            except Exception as error:
                last_error = error
        raise RuntimeError(f"unable to load embedded QuickJS: {last_error}")

    def _invoke(self, request):
        pointer = self._run(json.dumps(request, ensure_ascii=True).encode("utf-8"))
        if not pointer:
            raise RuntimeError("QuickJS bridge returned no response")
        try:
            response = json.loads(ctypes.string_at(pointer).decode("utf-8"))
        finally:
            self._free(pointer)
        if not isinstance(response, dict):
            raise RuntimeError("invalid QuickJS bridge response")
        return response

    def evaluate(self, source, cancel_file=""):
        if cancel_file and os.path.exists(cancel_file):
            raise KeyboardInterrupt("cancel requested before JavaScript evaluation")
        response = self._invoke({"operation": "evaluate", "source": source, "cancel_file": cancel_file})
        if response.get("status") == "cancelled" or (cancel_file and os.path.exists(cancel_file)):
            raise KeyboardInterrupt("cancel requested during JavaScript evaluation")
        if not response.get("ok"):
            raise RuntimeError(response.get("error") or response.get("status") or "QuickJS evaluation failed")
        output = response.get("output")
        if not isinstance(output, str):
            raise RuntimeError("QuickJS returned invalid output")
        return output


@contextlib.contextmanager
def embedded_quickjs(cancel_file=None):
    """Install reversible, per-invocation hooks against the current yt-dlp modules.

    The EJS/runtime hooks are private upstream APIs. If their shape changes, keep
    WebKit available and leave the original modules untouched. Do not catch errors
    from the operation inside this context as if they were setup failures.
    """
    if cancel_file is None:
        cancel_file = os.environ.get("PALLADIUM_CANCEL_FILE", "").strip()
    try:
        from yt_dlp.extractor.youtube.jsc._builtin.quickjs import QuickJSJCP
        from yt_dlp.extractor.youtube.jsc._registry import _jsc_preferences
        from yt_dlp.extractor.youtube.jsc.provider import JsChallengeProviderError, register_preference
        from yt_dlp.utils._jsruntime import JsRuntimeInfo, QuickJsRuntime

        original_info = QuickJsRuntime._info
        original_run = QuickJSJCP._run_js_runtime
        preferences = _jsc_preferences.value
        if not callable(original_info) or not callable(original_run) or not isinstance(preferences, set):
            raise RuntimeError("unsupported yt-dlp QuickJS provider API")
    except Exception as error:
        print(f"[palladium][quickjs] integration unavailable; retaining WebKit: {error}")
        yield
        return

    bridge = None
    runtime_info = None
    try:
        bridge = QuickJSBridge()
        runtime_info = JsRuntimeInfo(
            name="quickjs-ng", path="embedded", version=bridge.version,
            version_tuple=bridge.version_tuple, supported=True,
        )
        print(f"[palladium][quickjs] embedded QuickJS-NG {bridge.version}; WebKit fallback enabled")
    except Exception as error:
        print(f"[palladium][quickjs] engine unavailable; retaining WebKit: {error}")

    def embedded_info(runtime):
        # There is no external qjs executable on iOS, including when the native
        # bridge is missing. Never fall back to a subprocess version probe.
        if runtime._path not in (None, "", "qjs", "embedded"):
            print("[palladium][quickjs] external executable paths are unavailable on iOS")
            return None
        return runtime_info

    def run_script(provider, source):
        if bridge is None:
            raise JsChallengeProviderError("embedded QuickJS is unavailable", expected=True)
        try:
            return bridge.evaluate(source, cancel_file)
        except Exception as error:
            provider._available = False
            print(f"[palladium][quickjs] evaluation failed; allowing WebKit fallback: {error}")
            raise JsChallengeProviderError(str(error), expected=True) from error

    def prefer_quickjs(provider, requests):
        return 10000

    previous_preferences = set(preferences)
    added_preferences = set()
    try:
        register_preference(QuickJSJCP)(prefer_quickjs)
        added_preferences = preferences - previous_preferences
        QuickJsRuntime._info = embedded_info
        QuickJSJCP._run_js_runtime = run_script
    except Exception as error:
        preferences.difference_update(preferences - previous_preferences)
        QuickJsRuntime._info = original_info
        QuickJSJCP._run_js_runtime = original_run
        print(f"[palladium][quickjs] adapter setup failed; retaining WebKit: {error}")
        yield
        return

    try:
        yield
    finally:
        QuickJsRuntime._info = original_info
        QuickJSJCP._run_js_runtime = original_run
        preferences.difference_update(added_preferences)
