"""Developer diagnostics for the debug menu. Every probe returns a JSON object."""

import ast
import contextlib
import io
import json
import os
import platform
import sys
import tempfile
import time
import traceback

from .shared import TRACKED_PACKAGES

EXTRA_DIAGNOSTIC_PACKAGES = ("cffi", "certifi", "websockets", "brotli", "requests", "urllib3")
RESPONSE_PREVIEW_CHARS = 2000


def diagnostic_result(ok, output="", details=None, error=None):
    return {"ok": bool(ok), "output": str(output or ""), "details": details or {}, "error": error}


def diagnostic_error(error):
    return diagnostic_result(False, traceback.format_exc(), error=f"{type(error).__name__}: {error}")


def package_versions():
    from .packages import installed_version

    versions = {}
    for name in (*TRACKED_PACKAGES, *EXTRA_DIAGNOSTIC_PACKAGES):
        versions[name] = installed_version(name) or "not installed"
    return versions


def python_info(_argument):
    import ssl

    details = {
        "version": platform.python_version(),
        "implementation": platform.python_implementation(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "openssl": ssl.OPENSSL_VERSION,
        "prefix": sys.prefix,
        "sys_path": list(sys.path),
        "environment": {
            key: value for key, value in sorted(os.environ.items()) if key.startswith(("PALLADIUM_", "PYTHON"))
        },
        "packages": package_versions(),
    }
    return diagnostic_result(True, sys.version, details)


def run_python_source(source):
    tree = ast.parse(str(source or ""), "<debug>", "exec")
    trailing_expression = None
    if tree.body and isinstance(tree.body[-1], ast.Expr):
        trailing_expression = ast.Expression(tree.body.pop().value)

    namespace = {"__name__": "__palladium_debug__"}
    captured = io.StringIO()
    value = None
    with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
        exec(compile(tree, "<debug>", "exec"), namespace)
        if trailing_expression is not None:
            value = eval(compile(trailing_expression, "<debug>", "eval"), namespace)

    output = captured.getvalue()
    if value is not None:
        output += repr(value) + "\n"
    return output


def python_eval(argument):
    output = run_python_source(argument.get("source", ""))
    return diagnostic_result(True, output)


def curl_cffi_info(_argument):
    import cffi
    import curl_cffi

    targets = []
    browser_type = getattr(curl_cffi, "BrowserType", None)
    if browser_type is not None:
        targets = [member.value for member in browser_type]
    details = {
        "curl_cffi": getattr(curl_cffi, "__version__", "unknown"),
        "libcurl": getattr(curl_cffi, "__curl_version__", "unknown"),
        "cffi": getattr(cffi, "__version__", "unknown"),
        "module_path": getattr(curl_cffi, "__file__", ""),
        "impersonate_targets": targets,
        "ytdlp_impersonate_targets": ytdlp_impersonate_targets(),
    }
    output = f"curl_cffi {details['curl_cffi']} ({details['libcurl']})"
    return diagnostic_result(True, output, details)


def ytdlp_impersonate_targets():
    try:
        import yt_dlp

        with yt_dlp.YoutubeDL({"quiet": True, "no_warnings": True}) as ydl:
            available = ydl._get_available_impersonate_targets()
        return sorted({f"{target} via {handler}" for target, handler in available})
    except Exception as error:
        return [f"unavailable: {type(error).__name__}: {error}"]


def curl_cffi_request(argument):
    from curl_cffi import requests

    url = str(argument.get("url") or "https://tls.browserleaks.com/json")
    impersonate = str(argument.get("impersonate") or "").strip() or None
    started = time.monotonic()
    response = requests.get(url, impersonate=impersonate, timeout=20)
    details = {
        "url": str(response.url),
        "status_code": response.status_code,
        "http_version": str(getattr(response, "http_version", "")),
        "elapsed_ms": round((time.monotonic() - started) * 1000),
        "impersonate": impersonate or "none",
        "headers": dict(response.headers),
    }
    ok = 200 <= response.status_code < 400
    return diagnostic_result(ok, response.text[:RESPONSE_PREVIEW_CHARS], details)


def ffmpeg_bridge(_argument):
    from .ffmpeg_bridge import SwiftFFmpegBridge

    bridge = SwiftFFmpegBridge()
    capabilities = bridge.probe_capabilities()
    with tempfile.TemporaryDirectory(prefix="palladium-debug-") as directory:
        output_path = os.path.join(directory, "bridge-test.mp4")
        encode = bridge.run_ffmpeg([
            "-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=15",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "1",
            "-c:v", "mpeg4", "-c:a", "aac", output_path,
        ])
        if encode.exit_code != 0:
            error = f"ffmpeg exited with {encode.exit_code}"
            return diagnostic_result(False, encode.combined_output, capabilities, error)
        metadata = bridge.probe_metadata(output_path)

    streams = [stream.get("codec_name") for stream in metadata.get("streams", [])]
    details = {**capabilities, "encoded_streams": streams, "duration": metadata.get("format", {}).get("duration")}
    return diagnostic_result(streams == ["mpeg4", "aac"], json.dumps(details, indent=2), details)


def quickjs_bridge(argument):
    from .quickjs_bridge import QuickJSBridge

    bridge = QuickJSBridge()
    source = str(argument.get("source") or "console.log([1, 2, 3].map(value => value * 2).join(','))")
    output = bridge.evaluate(source)
    return diagnostic_result(True, output, {"version": bridge.version})


DIAGNOSTICS = {
    "python_info": python_info,
    "python_eval": python_eval,
    "curl_cffi_info": curl_cffi_info,
    "curl_cffi_request": curl_cffi_request,
    "ffmpeg_bridge": ffmpeg_bridge,
    "quickjs_bridge": quickjs_bridge,
}


def run_debug_diagnostic(name, argument_json=""):
    started = time.monotonic()
    try:
        diagnostic = DIAGNOSTICS.get(str(name))
        if diagnostic is None:
            raise ValueError(f"unknown diagnostic: {name}")
        argument = json.loads(argument_json) if argument_json else {}
        if not isinstance(argument, dict):
            raise ValueError("diagnostic argument must be a JSON object")
        result = diagnostic(argument)
    except (Exception, SystemExit) as error:
        result = diagnostic_error(error)
    result["duration_ms"] = round((time.monotonic() - started) * 1000)
    return json.dumps(result, default=str)
