import contextlib
import ctypes
import io
import json
import os
import re
import shlex
import subprocess
import time
import urllib.parse
from dataclasses import dataclass


@dataclass(frozen=True)
class BridgeCommandResult:
    exit_code: int
    stdout: str
    stderr: str

    @property
    def combined_output(self):
        return "\n".join(part for part in (self.stderr.strip(), self.stdout.strip()) if part)


def is_cancel_requested(cancel_file_path):
    return bool(cancel_file_path) and os.path.exists(cancel_file_path)


def normalize_ffmpeg_args(args):
    normalized = []
    for arg in args:
        value = str(arg)
        if value.startswith("file:/"):
            decoded_path = urllib.parse.unquote(value[5:])
            if decoded_path:
                value = decoded_path
        normalized.append(value)
    return normalized


def prepare_bridge_ffmpeg_args(tool, args):
    prepared = normalize_ffmpeg_args(args)
    if tool == "ffmpeg":
        if "-loglevel" not in prepared:
            prepared = ["-loglevel", "info", *prepared]
        if "-stats" not in prepared and "-nostats" not in prepared:
            prepared = ["-stats", *prepared]
        if "-nostdin" not in prepared:
            prepared = ["-nostdin", *prepared]
    return prepared


def bridge_ffmpeg_output_path(args):
    for arg in reversed(args):
        if arg in ("-nostats", "-nostdin"):
            continue
        return arg
    return None


def clean_bridge_version(raw_version):
    text = str(raw_version or "").strip()
    if not text:
        return None

    for pattern in (
        r"(?:\d+:)?([0-9.]+)-[0-9]+ubuntu[0-9.]+$",
        r"n([0-9.]+)$",
    ):
        match = re.match(pattern, text)
        if match:
            return match.group(1)

    numeric_match = re.search(r"([0-9]+(?:\.[0-9]+)+)", text)
    if numeric_match:
        return numeric_match.group(1)

    return text


def parse_bridge_executable_version(output_text, tool):
    for line in str(output_text or "").splitlines():
        stripped = line.strip()
        prefix = f"{tool} version "
        if stripped.lower().startswith(prefix):
            version_text = stripped[len(prefix):].split(None, 1)[0]
            return clean_bridge_version(version_text)
    return None


def bridge_lists_bsf(output_text, bsf_name):
    target = str(bsf_name or "").strip()
    if not target:
        return False

    for line in str(output_text or "").splitlines():
        if line.strip() == target:
            return True
    return False


def log_bridge_output(stderr_text):
    text = str(stderr_text or "").strip()
    if not text:
        return
    for line in text.splitlines():
        print(f"[palladium][ffmpeg-bridge][log] {line}")


def normalize_bridge_text_value(value, encoding="utf-8", errors="replace"):
    if isinstance(value, bytes):
        return value.decode(encoding, errors=errors)
    return str(value or "")


def normalize_bridge_binary_value(value, encoding="utf-8", errors="replace"):
    if isinstance(value, bytes):
        return value
    return str(value or "").encode(encoding, errors=errors)


def command_basename(args):
    if isinstance(args, (list, tuple)):
        cmd = [str(arg) for arg in args]
    elif isinstance(args, str):
        cmd = shlex.split(args)
    else:
        cmd = [str(args)]

    exe_name = os.path.basename(cmd[0]).lower() if cmd else ""
    if exe_name.endswith(".exe"):
        exe_name = exe_name[:-4]
    return exe_name, cmd


class SwiftFFmpegBridge:
    def __init__(self):
        self._run = None
        self._free = None
        self._capabilities = None
        self._load_bridge()

    def _candidate_library_specs(self):
        specs = [(None, "main executable (RTLD_DEFAULT)")]
        executable_path = os.environ.get("PALLADIUM_EXECUTABLE_PATH", "").strip()
        if executable_path:
            specs.append((executable_path, f"app executable at {executable_path}"))
        return specs

    def _load_bridge(self):
        last_error = None
        mode = getattr(ctypes, "RTLD_GLOBAL", 0)

        for library_path, label in self._candidate_library_specs():
            try:
                lib = ctypes.CDLL(library_path, mode=mode)
                run = lib.palladium_ffmpeg_bridge_run
                run.argtypes = [ctypes.c_char_p]
                run.restype = ctypes.c_void_p

                free = lib.palladium_ffmpeg_bridge_free
                free.argtypes = [ctypes.c_void_p]
                free.restype = None

                self._run = run
                self._free = free
                print(f"[palladium][ffmpeg-bridge] loaded symbols from {label}")
                return
            except Exception as error:
                last_error = error
                print(f"[palladium][ffmpeg-bridge] failed to load symbols from {label}: {error}")

        raise RuntimeError(f"unable to load swift ffmpeg bridge symbols: {last_error}")

    def _invoke(self, tool, args):
        payload = json.dumps({"tool": tool, "args": [str(arg) for arg in args]}).encode("utf-8")
        response_ptr = self._run(payload)
        if not response_ptr:
            raise RuntimeError("swift ffmpeg bridge returned null pointer")

        try:
            raw = ctypes.string_at(response_ptr).decode("utf-8", "replace")
        finally:
            self._free(response_ptr)

        response = json.loads(raw)
        result = BridgeCommandResult(
            exit_code=int(response.get("exit_code", 1)),
            stdout=str(response.get("output", "") or ""),
            stderr=str(response.get("stderr", "") or ""),
        )
        if bool(response.get("ok", False)):
            return result

        error = response.get("error") or f"swift ffmpeg bridge failed with exit code {result.exit_code}"
        if result.combined_output:
            raise RuntimeError(f"{error}\n{result.combined_output}")
        raise RuntimeError(error)

    def run_ffmpeg(self, args):
        return self._invoke("ffmpeg", prepare_bridge_ffmpeg_args("ffmpeg", args))

    def run_ffprobe(self, args):
        return self._invoke("ffprobe", prepare_bridge_ffmpeg_args("ffprobe", args))

    def probe_metadata(self, path, opts=None):
        command = [
            "-hide_banner",
            "-show_format",
            "-show_streams",
            "-print_format",
            "json",
            *(str(opt) for opt in (opts or [])),
            str(path),
        ]
        result = self.run_ffprobe(command)
        try:
            parsed = json.loads(result.stdout)
        except Exception as error:
            raise RuntimeError(f"ffprobe metadata parse failed for {path}: {error}") from error
        if not isinstance(parsed, dict):
            raise RuntimeError(f"ffprobe metadata probe returned unexpected payload for {path}")
        return parsed

    def probe_capabilities(self):
        if self._capabilities is not None:
            return self._capabilities

        versions = {"ffmpeg": None, "ffprobe": None}
        features = {}

        try:
            ffmpeg_result = self.run_ffmpeg(["-bsfs"])
            ffmpeg_text = ffmpeg_result.combined_output
            versions["ffmpeg"] = parse_bridge_executable_version(ffmpeg_text, "ffmpeg")
            features = {
                "fdk": "--enable-libfdk-aac" in ffmpeg_text,
                "setts": "setts" in ffmpeg_text.splitlines(),
                "needs_adtstoasc": bridge_lists_bsf(ffmpeg_text, "aac_adtstoasc"),
            }
        except Exception as error:
            print(f"[palladium][ffmpeg-bridge] ffmpeg capability probe failed: {error}")

        try:
            ffprobe_result = self.run_ffprobe(["-version"])
            ffprobe_text = ffprobe_result.combined_output or ffprobe_result.stdout
            versions["ffprobe"] = parse_bridge_executable_version(ffprobe_text, "ffprobe")
        except Exception as error:
            print(f"[palladium][ffmpeg-bridge] ffprobe version probe failed: {error}")

        self._capabilities = {
            "versions": versions,
            "features": features,
        }
        if versions["ffmpeg"] or versions["ffprobe"]:
            print(
                "[palladium][ffmpeg-bridge] probed versions:"
                f" ffmpeg={versions['ffmpeg'] or 'unknown'}"
                f" ffprobe={versions['ffprobe'] or 'unknown'}"
            )
        if features:
            print(f"[palladium][ffmpeg-bridge] probed features: {features}")
        return self._capabilities


class YTDLPFFmpegBridgeAdapter:
    def __init__(self, bridge, cancel_file_path=""):
        self.bridge = bridge
        self.cancel_file_path = str(cancel_file_path or "").strip()

    def maybe_cancel(self):
        if is_cancel_requested(self.cancel_file_path):
            raise KeyboardInterrupt("cancel requested")

    def probe_capabilities(self):
        return self.bridge.probe_capabilities()

    def probe_metadata(self, path, opts=None):
        return self.bridge.probe_metadata(path, opts=opts)

    def run_tool(self, tool, raw_args):
        self.maybe_cancel()
        args = [str(arg) for arg in raw_args]
        started_at = time.time()
        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen running {tool} with {len(args)} arg(s)")
        result = self.bridge.run_ffprobe(args) if tool == "ffprobe" else self.bridge.run_ffmpeg(args)
        elapsed = time.time() - started_at
        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen {tool} finished in {elapsed:.2f}s")
        log_bridge_output(result.stderr)
        if tool == "ffmpeg":
            target_path = bridge_ffmpeg_output_path(args)
            if target_path and os.path.isfile(target_path):
                try:
                    target_size = os.path.getsize(target_path)
                    print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file ready: {target_path} ({target_size} bytes)")
                except Exception:
                    print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file ready: {target_path}")
            else:
                print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file missing after run: {target_path or '<unknown>'}")
        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen exit={result.exit_code}")
        return result


@contextlib.contextmanager
def patch_ytdlp_for_swiftffmpeg(adapter):
    try:
        from yt_dlp import YoutubeDL as YDLClass
        from yt_dlp.downloader.common import FileDownloader
        import yt_dlp.downloader.external as ydl_external
        import yt_dlp.postprocessor.ffmpeg as ydl_ffmpeg_pp
        import yt_dlp.utils as ydl_utils_public
        import yt_dlp.utils._utils as ydl_utils
    except Exception:
        yield
        return

    original_to_screen = YDLClass.to_screen
    original_report_progress = FileDownloader.report_progress
    original_public_utils_popen = getattr(ydl_utils_public, "Popen", None)
    original_utils_popen = ydl_utils.Popen
    original_external_popen = getattr(ydl_external, "Popen", None)
    original_ffmpeg_popen = getattr(ydl_ffmpeg_pp, "Popen", None)
    original_get_ffmpeg_version = getattr(ydl_ffmpeg_pp.FFmpegPostProcessor, "_get_ffmpeg_version", None)
    original_get_metadata_object = getattr(ydl_ffmpeg_pp.FFmpegPostProcessor, "get_metadata_object", None)

    class BridgePopen:
        def __init__(self, args, *remaining, **kwargs):
            exe_name, cmd = command_basename(args)
            self._delegate = None
            self.args = args
            self.returncode = None
            self.stdout = None
            self.stderr = None
            self._stdout_value = None
            self._stderr_value = None

            if exe_name not in ("ffmpeg", "ffprobe"):
                self._delegate = original_utils_popen(args, *remaining, **kwargs)
                return

            print(f"[palladium][ffmpeg-bridge] yt-dlp Popen intercepted: {' '.join(cmd)}")
            tool = "ffprobe" if exe_name == "ffprobe" else "ffmpeg"
            text_mode = bool(kwargs.get("text") or kwargs.get("universal_newlines"))
            encoding = kwargs.get("encoding") or "utf-8"
            errors = kwargs.get("errors") or "replace"

            result = adapter.run_tool(tool, cmd[1:])
            self.returncode = int(result.exit_code)

            if text_mode:
                stdout_value = normalize_bridge_text_value(result.stdout, encoding=encoding, errors=errors)
                stderr_value = normalize_bridge_text_value(result.stderr, encoding=encoding, errors=errors)
                stdout_stream = io.StringIO(stdout_value)
                stderr_stream = io.StringIO(stderr_value)
            else:
                stdout_value = normalize_bridge_binary_value(result.stdout, encoding=encoding, errors=errors)
                stderr_value = normalize_bridge_binary_value(result.stderr, encoding=encoding, errors=errors)
                stdout_stream = io.BytesIO(stdout_value)
                stderr_stream = io.BytesIO(stderr_value)

            self._stdout_value = stdout_value
            self._stderr_value = stderr_value

            if kwargs.get("stdout") == subprocess.PIPE:
                self.stdout = stdout_stream
            if kwargs.get("stderr") == subprocess.PIPE:
                self.stderr = stderr_stream
            if kwargs.get("stderr") == subprocess.STDOUT:
                if text_mode:
                    self._stdout_value = f"{stdout_value}{stderr_value}"
                else:
                    self._stdout_value = stdout_value + stderr_value
                self._stderr_value = None
                if kwargs.get("stdout") == subprocess.PIPE:
                    self.stdout = io.StringIO(self._stdout_value) if text_mode else io.BytesIO(self._stdout_value)

        @classmethod
        def run(cls, *args, **kwargs):
            with cls(*args, **kwargs) as proc:
                stdout, stderr = proc.communicate(kwargs.get("input"))
                return stdout, stderr, proc.wait()

        def communicate(self, input=None, timeout=None):
            if self._delegate is not None:
                return self._delegate.communicate(input=input, timeout=timeout)
            return self._stdout_value, self._stderr_value

        def wait(self, timeout=None):
            if self._delegate is not None:
                return self._delegate.wait(timeout=timeout)
            return self.returncode

        def poll(self):
            if self._delegate is not None:
                return self._delegate.poll()
            return self.returncode

        def kill(self):
            if self._delegate is not None:
                return self._delegate.kill()
            return None

        def terminate(self):
            if self._delegate is not None:
                return self._delegate.terminate()
            return None

        def send_signal(self, sig):
            if self._delegate is not None:
                return self._delegate.send_signal(sig)
            return None

        def __enter__(self):
            if self._delegate is not None:
                self._delegate.__enter__()
            return self

        def __exit__(self, exc_type, exc, tb):
            if self._delegate is not None:
                return self._delegate.__exit__(exc_type, exc, tb)
            return False

        def __getattr__(self, name):
            if self._delegate is not None:
                return getattr(self._delegate, name)
            raise AttributeError(name)

    def patched_to_screen(self, message, *args, **kwargs):
        adapter.maybe_cancel()
        return original_to_screen(self, message, *args, **kwargs)

    def patched_report_progress(self, status):
        adapter.maybe_cancel()
        return original_report_progress(self, status)

    def patched_get_ffmpeg_version(self, prog):
        version = None
        features = {}
        if original_get_ffmpeg_version is not None:
            try:
                version, features = original_get_ffmpeg_version(self, prog)
            except Exception as error:
                print(f"[palladium][ffmpeg-bridge] yt-dlp {prog} probe failed; using bridge fallback: {error}")

        if version and (prog != "ffmpeg" or features):
            return version, features

        fallback = adapter.probe_capabilities()
        fallback_version = fallback["versions"].get(prog)
        fallback_features = dict(fallback["features"]) if prog == "ffmpeg" else {}
        if version and prog == "ffmpeg" and fallback_features:
            return version, fallback_features
        if fallback_version or fallback_features:
            print(f"[palladium][ffmpeg-bridge] using bridge-derived {prog} metadata")
            return fallback_version or version, fallback_features or features
        return version, features

    def patched_get_metadata_object(self, path, opts=None):
        probe_executable = getattr(self, "probe_executable", None)
        if probe_executable == "ffprobe":
            try:
                return adapter.probe_metadata(path, opts=opts)
            except Exception as error:
                raise ydl_utils.PostProcessingError(f"Unable to extract metadata with ffprobe: {error}") from error
        return original_get_metadata_object(self, path, opts or [])

    YDLClass.to_screen = patched_to_screen
    FileDownloader.report_progress = patched_report_progress
    if original_public_utils_popen is not None:
        ydl_utils_public.Popen = BridgePopen
    ydl_utils.Popen = BridgePopen
    if original_external_popen is not None:
        ydl_external.Popen = BridgePopen
    if original_ffmpeg_popen is not None:
        ydl_ffmpeg_pp.Popen = BridgePopen
    if original_get_ffmpeg_version is not None:
        ydl_ffmpeg_pp.FFmpegPostProcessor._get_ffmpeg_version = patched_get_ffmpeg_version
    if original_get_metadata_object is not None:
        ydl_ffmpeg_pp.FFmpegPostProcessor.get_metadata_object = patched_get_metadata_object

    try:
        print("[palladium][ffmpeg-bridge] yt-dlp bridge adapter enabled")
        yield
    finally:
        YDLClass.to_screen = original_to_screen
        FileDownloader.report_progress = original_report_progress
        if original_public_utils_popen is not None:
            ydl_utils_public.Popen = original_public_utils_popen
        ydl_utils.Popen = original_utils_popen
        if original_external_popen is not None:
            ydl_external.Popen = original_external_popen
        if original_ffmpeg_popen is not None:
            ydl_ffmpeg_pp.Popen = original_ffmpeg_popen
        if original_get_ffmpeg_version is not None:
            ydl_ffmpeg_pp.FFmpegPostProcessor._get_ffmpeg_version = original_get_ffmpeg_version
        if original_get_metadata_object is not None:
            ydl_ffmpeg_pp.FFmpegPostProcessor.get_metadata_object = original_get_metadata_object
