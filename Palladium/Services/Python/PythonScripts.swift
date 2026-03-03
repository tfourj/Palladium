import Foundation

enum PythonScripts {
    static let ytDlpScript = #"""
import contextlib
import ctypes
import io
import json
import os
import re
import runpy
import shlex
import shutil
import subprocess
import sys
import traceback
import urllib.parse
import importlib.metadata as importlib_metadata
import time


def ensure_pip_entrypoint():
    pip_main = None
    try:
        from pip._internal.cli.main import main as pip_main
        return pip_main
    except Exception:
        print("[palladium] pip entrypoint unavailable")
        traceback.print_exc()
        print("[palladium] attempting ensurepip fallback")
        try:
            import ensurepip
            with ensurepip._get_pip_whl_path_ctx() as pip_wheel:
                pip_wheel_str = str(pip_wheel)
                if pip_wheel_str not in sys.path:
                    sys.path.insert(0, pip_wheel_str)
                from pip._internal.cli.main import main as pip_main
                print("[palladium] pip loaded from ensurepip bundled wheel")
                return pip_main
        except Exception:
            print("[palladium] ensurepip fallback failed")
            traceback.print_exc()
            return None


def collect_versions():
    versions = {}
    for package_name in ("yt-dlp", "yt-dlp-apple-webkit-jsi"):
        try:
            versions[package_name] = importlib_metadata.version(package_name)
        except Exception:
            versions[package_name] = "not installed"
    return versions


class SwiftFFmpegBridge:
    def __init__(self):
        lib = ctypes.CDLL(None)
        self._run = lib.palladium_ffmpeg_bridge_run
        self._run.argtypes = [ctypes.c_char_p]
        self._run.restype = ctypes.c_void_p

        self._free = lib.palladium_ffmpeg_bridge_free
        self._free.argtypes = [ctypes.c_void_p]
        self._free.restype = None

    def run(self, tool, args):
        payload = json.dumps({"tool": tool, "args": [str(a) for a in args]}).encode("utf-8")
        response_ptr = self._run(payload)
        if not response_ptr:
            raise RuntimeError("swift ffmpeg bridge returned null pointer")

        try:
            raw = ctypes.string_at(response_ptr).decode("utf-8", "replace")
        finally:
            self._free(response_ptr)

        response = json.loads(raw)
        ok = bool(response.get("ok", False))
        exit_code = int(response.get("exit_code", 1))
        output = response.get("output", "")
        error = response.get("error")

        if not ok:
            if output:
                raise RuntimeError((error or f"swift ffmpeg bridge failed with exit code {exit_code}") + "\\n" + output)
            raise RuntimeError(error or f"swift ffmpeg bridge failed with exit code {exit_code}")

        return exit_code, output


def normalize_ffmpeg_args(args):
    normalized = []
    for arg in args:
        value = str(arg)
        if value.startswith("file:/"):
            parsed = urllib.parse.urlparse(value)
            decoded_path = urllib.parse.unquote(parsed.path)
            if decoded_path:
                value = decoded_path
        normalized.append(value)
    return normalized


def prepare_bridge_ffmpeg_args(tool, args):
    prepared = normalize_ffmpeg_args(args)
    if tool == "ffmpeg":
        # ffmpeg_wrapper.c captures stdout/stderr via pipe and reads after execution.
        # High-volume ffmpeg logs can deadlock that pipe on iOS, so keep output minimal.
        i = 0
        while i < len(prepared):
            if prepared[i] == "-loglevel" and i + 1 < len(prepared):
                prepared[i + 1] = "error"
                i += 2
                continue
            i += 1
        if "-loglevel" not in prepared:
            prepared = ["-loglevel", "error", *prepared]
        if "-nostats" not in prepared:
            prepared = [*prepared, "-nostats"]
        if "-nostdin" not in prepared:
            prepared = ["-nostdin", *prepared]
    return prepared


def log_bridge_output(output):
    if not output:
        return
    text = str(output).strip()
    if not text:
        return
    for line in text.splitlines():
        print(f"[palladium][ffmpeg-bridge][log] {line}")


def extract_probable_youtube_id(url):
    try:
        parsed = urllib.parse.urlparse(url)
        host = (parsed.netloc or "").lower()
        path = (parsed.path or "").strip("/")

        if "youtu.be" in host and path:
            return path.split("/")[0]

        if "youtube.com" in host:
            if path == "watch":
                query = urllib.parse.parse_qs(parsed.query)
                video_id = (query.get("v") or [None])[0]
                if video_id:
                    return video_id
            if path.startswith("shorts/"):
                return path.split("/", 1)[1].split("/")[0]
            if path.startswith("embed/"):
                return path.split("/", 1)[1].split("/")[0]
    except Exception:
        return None
    return None


def cleanup_existing_downloads(downloads_dir, download_url):
    if not downloads_dir or not download_url:
        return

    video_id = extract_probable_youtube_id(download_url)
    if not video_id:
        return

    deleted = 0
    try:
        for name in os.listdir(downloads_dir):
            # Match yt-dlp output template files for this video id.
            if f"[{video_id}]" not in name:
                continue
            full_path = os.path.join(downloads_dir, name)
            if os.path.isfile(full_path):
                try:
                    os.remove(full_path)
                    deleted += 1
                except Exception:
                    pass
        print(f"[palladium] cleanup for video id {video_id}: removed {deleted} file(s)")
    except Exception:
        print("[palladium] cleanup before download failed")
        traceback.print_exc()


def cleanup_temp_download_files(downloads_dir):
    if not downloads_dir:
        return

    removed = 0
    try:
        for name in os.listdir(downloads_dir):
            full_path = os.path.join(downloads_dir, name)
            if not os.path.isfile(full_path):
                continue

            lower = name.lower()
            is_temp = (
                lower.endswith(".part")
                or lower.endswith(".ytdl")
                or lower.endswith(".tmp")
                or ".temp." in lower
                or re.search(r"\.f\d+\.[a-z0-9]+\.part$", lower) is not None
                or ".frag" in lower
            )
            if not is_temp:
                continue

            try:
                os.remove(full_path)
                removed += 1
            except Exception:
                pass
        print(f"[palladium] temp cleanup: removed {removed} file(s)")
    except Exception:
        print("[palladium] temp cleanup failed")
        traceback.print_exc()


def build_preset_args(preset):
    if preset == "audio":
        print("[palladium] preset: audio (mp3 template)")
        return ["-f", "ba[acodec^=mp3]/ba/b", "-x", "--audio-format", "mp3"]

    if preset == "mute":
        print("[palladium] preset: mute (mp4 no-audio)")
        return [
            "-f", "bv*/bestvideo",
            "--merge-output-format", "mp4",
            "--remux-video", "mp4",
            "-S", "vcodec:h264,lang,quality,res,fps,hdr:12",
        ]

    print("[palladium] preset: auto_video (mp4 template)")
    return [
        "--merge-output-format", "mp4",
        "--remux-video", "mp4",
        "-S", "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac",
    ]


def parse_custom_args(custom_args_value):
    if not custom_args_value:
        return []
    try:
        parsed = shlex.split(str(custom_args_value))
        print(f"[palladium] custom args parsed: {parsed}")
        return parsed
    except Exception:
        print("[palladium] failed to parse custom args")
        traceback.print_exc()
        return []


def parse_extra_args(extra_args_value):
    if not extra_args_value:
        return []
    try:
        parsed = shlex.split(str(extra_args_value))
        print(f"[palladium] extra args parsed: {parsed}")
        return parsed
    except Exception:
        print("[palladium] failed to parse extra args")
        traceback.print_exc()
        return []


def is_cancel_requested(cancel_file_path):
    return bool(cancel_file_path) and os.path.exists(cancel_file_path)


@contextlib.contextmanager
def patch_ytdlp_cancel(cancel_file_path):
    if not cancel_file_path:
        yield
        return

    try:
        from yt_dlp import YoutubeDL as YDLClass
        from yt_dlp.downloader.common import FileDownloader
    except Exception:
        yield
        return

    original_to_screen = YDLClass.to_screen
    original_report_progress = FileDownloader.report_progress

    def maybe_cancel():
        if is_cancel_requested(cancel_file_path):
            raise KeyboardInterrupt("cancel requested")

    def patched_to_screen(self, message, *args, **kwargs):
        maybe_cancel()
        return original_to_screen(self, message, *args, **kwargs)

    def patched_report_progress(self, s):
        maybe_cancel()
        return original_report_progress(self, s)

    YDLClass.to_screen = patched_to_screen
    FileDownloader.report_progress = patched_report_progress
    try:
        yield
    finally:
        YDLClass.to_screen = original_to_screen
        FileDownloader.report_progress = original_report_progress


@contextlib.contextmanager
def patch_subprocess_for_swiftffmpeg(bridge):
    original_popen = subprocess.Popen
    original_run = subprocess.run
    original_call = subprocess.call
    original_check_call = subprocess.check_call
    original_check_output = subprocess.check_output
    original_which = shutil.which

    def normalize_cmd(args):
        if isinstance(args, (list, tuple)):
            cmd = [str(a) for a in args]
        elif isinstance(args, str):
            cmd = shlex.split(args)
        else:
            cmd = [str(args)]

        if not cmd:
            return "", cmd

        exe_name = os.path.basename(cmd[0]).lower()
        if exe_name.endswith(".exe"):
            exe_name = exe_name[:-4]
        return exe_name, cmd

    def patched_which(cmd, *which_args, **which_kwargs):
        exe_name = os.path.basename(str(cmd)).lower()
        if exe_name in ("ffmpeg", "ffprobe"):
            return exe_name
        return original_which(cmd, *which_args, **which_kwargs)

    class SwiftFFmpegPopen:
        def __init__(self, args, *popen_args, **kwargs):
            exe_name, cmd = normalize_cmd(args)
            self._delegate = None
            self.args = args
            self.returncode = None
            self.stdout = None
            self.stderr = None
            self._stdout_value = None
            self._stderr_value = None

            if exe_name not in ("ffmpeg", "ffprobe"):
                self._delegate = original_popen(args, *popen_args, **kwargs)
                return

            print(f"[palladium][ffmpeg-bridge] intercepted: {' '.join(cmd)}")
            tool = "ffprobe" if exe_name == "ffprobe" else "ffmpeg"
            text_mode = bool(kwargs.get("text") or kwargs.get("universal_newlines"))
            encoding = kwargs.get("encoding") or "utf-8"
            errors = kwargs.get("errors") or "replace"

            try:
                bridged_args = prepare_bridge_ffmpeg_args(tool, cmd[1:])
                started_at = time.time()
                print(f"[palladium][ffmpeg-bridge] running {tool} with {len(bridged_args)} arg(s)")
                code, output = bridge.run(tool, bridged_args)
                self.returncode = int(code)
                log_bridge_output(output)
                elapsed = time.time() - started_at
                print(f"[palladium][ffmpeg-bridge] {tool} finished in {elapsed:.2f}s")
                if tool == "ffmpeg" and bridged_args:
                    target_path = bridged_args[-1]
                    if os.path.isfile(target_path):
                        try:
                            target_size = os.path.getsize(target_path)
                            print(f"[palladium][ffmpeg-bridge] output file ready: {target_path} ({target_size} bytes)")
                        except Exception:
                            print(f"[palladium][ffmpeg-bridge] output file ready: {target_path}")
                    else:
                        print(f"[palladium][ffmpeg-bridge] output file missing after run: {target_path}")
            except Exception as bridge_error:
                raise RuntimeError(f"swift ffmpeg bridge error: {bridge_error}") from bridge_error

            print(f"[palladium][ffmpeg-bridge] exit={self.returncode}")

            if text_mode:
                self._stdout_value = output
                self._stderr_value = output
                stdout_stream = io.StringIO(output)
                stderr_stream = io.StringIO(output)
            else:
                out_bytes = output.encode(encoding, errors=errors)
                self._stdout_value = out_bytes
                self._stderr_value = out_bytes
                stdout_stream = io.BytesIO(out_bytes)
                stderr_stream = io.BytesIO(out_bytes)

            if kwargs.get("stdout") == subprocess.PIPE:
                self.stdout = stdout_stream
            if kwargs.get("stderr") == subprocess.PIPE:
                self.stderr = stderr_stream

            stderr_target = kwargs.get("stderr")
            if stderr_target == subprocess.STDOUT:
                self._stderr_value = None
                if kwargs.get("stdout") == subprocess.PIPE:
                    self.stdout = stdout_stream

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

    subprocess.Popen = SwiftFFmpegPopen
    def patched_run(args, *run_args, **kwargs):
        proc = SwiftFFmpegPopen(args, **kwargs)
        completed = subprocess.CompletedProcess(
            args=args,
            returncode=proc.wait(),
            stdout=proc._stdout_value,
            stderr=proc._stderr_value,
        )
        if kwargs.get("check") and completed.returncode != 0:
            raise subprocess.CalledProcessError(
                completed.returncode,
                completed.args,
                output=completed.stdout,
                stderr=completed.stderr,
            )
        return completed

    def patched_call(args, *call_args, **kwargs):
        proc = SwiftFFmpegPopen(args, **kwargs)
        return proc.wait()

    def patched_check_call(args, *call_args, **kwargs):
        rc = patched_call(args, *call_args, **kwargs)
        if rc != 0:
            raise subprocess.CalledProcessError(rc, args)
        return 0

    def patched_check_output(args, *call_args, **kwargs):
        kwargs["stdout"] = subprocess.PIPE
        completed = patched_run(args, *call_args, **kwargs)
        if completed.returncode != 0:
            raise subprocess.CalledProcessError(
                completed.returncode,
                args,
                output=completed.stdout,
                stderr=completed.stderr,
            )
        return completed.stdout

    subprocess.run = patched_run
    subprocess.call = patched_call
    subprocess.check_call = patched_check_call
    subprocess.check_output = patched_check_output
    shutil.which = patched_which
    try:
        yield
    finally:
        subprocess.Popen = original_popen
        subprocess.run = original_run
        subprocess.call = original_call
        subprocess.check_call = original_check_call
        subprocess.check_output = original_check_output
        shutil.which = original_which


@contextlib.contextmanager
def patch_ytdlp_popen_for_swiftffmpeg(bridge):
    try:
        import yt_dlp.utils._utils as ydl_utils
        import yt_dlp.postprocessor.ffmpeg as ydl_ffmpeg_pp
    except Exception:
        yield
        return

    original_utils_popen = ydl_utils.Popen
    original_ffmpeg_popen = getattr(ydl_ffmpeg_pp, "Popen", None)

    def normalize_cmd(args):
        if isinstance(args, (list, tuple)):
            cmd = [str(a) for a in args]
        elif isinstance(args, str):
            cmd = shlex.split(args)
        else:
            cmd = [str(args)]
        exe_name = os.path.basename(cmd[0]).lower() if cmd else ""
        if exe_name.endswith(".exe"):
            exe_name = exe_name[:-4]
        return exe_name, cmd

    class BridgePopen:
        def __init__(self, args, *remaining, **kwargs):
            exe_name, cmd = normalize_cmd(args)
            self._delegate = None
            self.args = args
            self.returncode = None
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

            bridged_args = prepare_bridge_ffmpeg_args(tool, cmd[1:])
            started_at = time.time()
            print(f"[palladium][ffmpeg-bridge] yt-dlp Popen running {tool} with {len(bridged_args)} arg(s)")
            code, output = bridge.run(tool, bridged_args)
            self.returncode = int(code)
            log_bridge_output(output)
            elapsed = time.time() - started_at
            print(f"[palladium][ffmpeg-bridge] yt-dlp Popen {tool} finished in {elapsed:.2f}s")
            if tool == "ffmpeg" and bridged_args:
                target_path = bridged_args[-1]
                if os.path.isfile(target_path):
                    try:
                        target_size = os.path.getsize(target_path)
                        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file ready: {target_path} ({target_size} bytes)")
                    except Exception:
                        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file ready: {target_path}")
                else:
                    print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file missing after run: {target_path}")
            if text_mode:
                self._stdout_value = output
                self._stderr_value = output
            else:
                out_bytes = output.encode(encoding, errors=errors)
                self._stdout_value = out_bytes
                self._stderr_value = out_bytes
            print(f"[palladium][ffmpeg-bridge] yt-dlp Popen exit={self.returncode}")

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

    ydl_utils.Popen = BridgePopen
    if original_ffmpeg_popen is not None:
        ydl_ffmpeg_pp.Popen = BridgePopen
    try:
        print("[palladium][ffmpeg-bridge] yt-dlp internal Popen patch enabled")
        yield
    finally:
        ydl_utils.Popen = original_utils_popen
        if original_ffmpeg_popen is not None:
            ydl_ffmpeg_pp.Popen = original_ffmpeg_popen


@contextlib.contextmanager
def patch_ytdlp_ffmpeg_detection():
    original_determine = None
    original_check_version = None
    original_get_versions_and_features = None
    original_basename = None
    original_probe_basename = None
    ffmpeg_pp = None

    try:
        from yt_dlp.postprocessor.ffmpeg import FFmpegPostProcessor
        ffmpeg_pp = FFmpegPostProcessor
    except Exception:
        yield
        return

    if hasattr(ffmpeg_pp, "_determine_executables"):
        original_determine = ffmpeg_pp._determine_executables
        def patched_determine(self):
            return {
                "ffmpeg": "ffmpeg",
                "ffprobe": "ffprobe",
                "avconv": "avconv",
                "avprobe": "avprobe",
            }
        ffmpeg_pp._determine_executables = patched_determine

    if hasattr(ffmpeg_pp, "check_version"):
        original_check_version = ffmpeg_pp.check_version
        def patched_check_version(self):
            return True
        ffmpeg_pp.check_version = patched_check_version

    if hasattr(ffmpeg_pp, "get_versions_and_features"):
        original_get_versions_and_features = ffmpeg_pp.get_versions_and_features
        @classmethod
        def patched_get_versions_and_features(cls, ydl):
            return {"ffmpeg": "bridge", "ffprobe": "bridge"}, {}
        ffmpeg_pp.get_versions_and_features = patched_get_versions_and_features

    if hasattr(ffmpeg_pp, "basename"):
        original_basename = ffmpeg_pp.basename
        def get_basename(self):
            return "ffmpeg"
        def set_basename(self, value):
            self.__dict__["_palladium_basename"] = value
        ffmpeg_pp.basename = property(get_basename, set_basename)

    if hasattr(ffmpeg_pp, "probe_basename"):
        original_probe_basename = ffmpeg_pp.probe_basename
        def get_probe_basename(self):
            return "ffprobe"
        def set_probe_basename(self, value):
            self.__dict__["_palladium_probe_basename"] = value
        ffmpeg_pp.probe_basename = property(get_probe_basename, set_probe_basename)

    try:
        print("[palladium][ffmpeg-bridge] yt-dlp ffmpeg detection patch enabled")
        yield
    finally:
        if original_determine is not None:
            ffmpeg_pp._determine_executables = original_determine
        if original_check_version is not None:
            ffmpeg_pp.check_version = original_check_version
        if original_get_versions_and_features is not None:
            ffmpeg_pp.get_versions_and_features = original_get_versions_and_features
        if original_basename is not None:
            ffmpeg_pp.basename = original_basename
        if original_probe_basename is not None:
            ffmpeg_pp.probe_basename = original_probe_basename


def run_yt_dlp_flow(download_url_override=None, download_preset_override=None, custom_args_override=None, extra_args_override=None):
    output = io.StringIO()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    yt_exit_code = None
    downloaded_path = None
    cancelled = False
    success = False
    if download_url_override is None:
        download_url = os.environ.get("PALLADIUM_DOWNLOAD_URL", "").strip()
    else:
        download_url = str(download_url_override).strip()

    if download_preset_override is None:
        download_preset = os.environ.get("PALLADIUM_DOWNLOAD_PRESET", "auto_video").strip()
    else:
        download_preset = str(download_preset_override).strip()
    if custom_args_override is None:
        custom_args_text = os.environ.get("PALLADIUM_CUSTOM_ARGS", "").strip()
    else:
        custom_args_text = str(custom_args_override).strip()
    if extra_args_override is None:
        extra_args_text = os.environ.get("PALLADIUM_EXTRA_ARGS", "").strip()
    else:
        extra_args_text = str(extra_args_override).strip()
    downloads_dir = os.environ.get("PALLADIUM_DOWNLOADS", "").strip()
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    cancel_file_path = os.environ.get("PALLADIUM_CANCEL_FILE", "").strip()
    live_fd_value = os.environ.get("PALLADIUM_LOG_FD")
    live_log_stream = None
    if live_fd_value:
        try:
            live_fd = int(live_fd_value)
            live_log_stream = os.fdopen(live_fd, "w", buffering=1, encoding="utf-8", errors="replace", closefd=False)
        except Exception:
            live_log_stream = None

    class Tee:
        def __init__(self, *streams):
            self.streams = [s for s in streams if s is not None]
        def write(self, data):
            for stream in self.streams:
                try:
                    stream.write(data)
                except UnicodeEncodeError:
                    safe_data = data.encode("ascii", "replace").decode("ascii")
                    stream.write(safe_data)
                if hasattr(stream, "flush"):
                    stream.flush()
            return len(data)
        def flush(self):
            for stream in self.streams:
                if hasattr(stream, "flush"):
                    stream.flush()

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")
        if downloads_dir:
            os.makedirs(downloads_dir, exist_ok=True)
            print(f"[palladium] download target: {downloads_dir}")

        ffmpeg_bridge_dir = ""
        if downloads_dir:
            ffmpeg_bridge_dir = os.path.join(downloads_dir, ".palladium-ffmpeg")
            try:
                os.makedirs(ffmpeg_bridge_dir, exist_ok=True)
                ffmpeg_stub = os.path.join(ffmpeg_bridge_dir, "ffmpeg")
                ffprobe_stub = os.path.join(ffmpeg_bridge_dir, "ffprobe")
                for stub_path in (ffmpeg_stub, ffprobe_stub):
                    if not os.path.exists(stub_path):
                        with open(stub_path, "w", encoding="utf-8") as stub_file:
                            stub_file.write("#!/bin/sh\\n")
                            stub_file.write("echo 'palladium swiftffmpeg bridge stub'\\n")
                    try:
                        os.chmod(stub_path, 0o755)
                    except Exception:
                        pass
                print(f"[palladium][ffmpeg-bridge] stub location: {ffmpeg_bridge_dir}")
                os.environ["PATH"] = ffmpeg_bridge_dir + os.pathsep + os.environ.get("PATH", "")
            except Exception:
                ffmpeg_bridge_dir = ""
                print("[palladium][ffmpeg-bridge] unable to prepare ffmpeg-location stubs")
                traceback.print_exc()

        needs_yt_dlp_install = False
        needs_webkit_jsi_install = False

        print("[palladium] checking yt_dlp import")
        try:
            import yt_dlp  # noqa: F401
            print("[palladium] yt_dlp already installed")
        except Exception:
            needs_yt_dlp_install = True
            print("[palladium] yt_dlp module missing")

        print("[palladium] checking yt-dlp-apple-webkit-jsi package")
        try:
            importlib_metadata.version("yt-dlp-apple-webkit-jsi")
            print("[palladium] yt-dlp-apple-webkit-jsi already installed")
        except Exception:
            needs_webkit_jsi_install = True
            print("[palladium] yt-dlp-apple-webkit-jsi missing")

        if needs_yt_dlp_install or needs_webkit_jsi_install:
            pip_attempted = True
            pip_main = ensure_pip_entrypoint()
            if pip_main is not None:
                packages = []
                if needs_yt_dlp_install:
                    packages.append("yt-dlp")
                if needs_webkit_jsi_install:
                    packages.append("yt-dlp-apple-webkit-jsi")

                try:
                    pip_args = ["install", "--no-cache-dir", "--progress-bar", "off", "--no-color", *packages]
                    if install_target:
                        pip_args[1:1] = ["--target", install_target]
                    pip_result = pip_main(pip_args)
                    pip_exit_code = 0 if pip_result is None else int(pip_result)
                    print(f"[palladium] pip exit code: {pip_exit_code}")
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] pip install failed")
                    traceback.print_exc()
            else:
                pip_exit_code = 1

            try:
                if install_target and install_target not in sys.path:
                    sys.path.insert(0, install_target)
                import yt_dlp  # noqa: F401
                print("[palladium] yt_dlp import succeeded after install")
            except Exception:
                print("[palladium] yt_dlp still unavailable after install attempt")
                traceback.print_exc()

        if not download_url:
            print("[palladium] no URL provided")
            yt_exit_code = 1
        elif is_cancel_requested(cancel_file_path):
            print("[palladium] cancellation requested before run")
            cancelled = True
            yt_exit_code = 130
        else:
            print(f"[palladium] running yt-dlp -v {download_url}")

        argv_backup = sys.argv[:]
        cwd_backup = os.getcwd()
        run_started_at = time.time()

        try:
            if download_url:
                bridge = None
                try:
                    bridge = SwiftFFmpegBridge()
                    print("[palladium][ffmpeg-bridge] bridge loaded")
                    print("[palladium][ffmpeg-bridge] startup probes skipped")
                except Exception as bridge_error:
                    print(f"[palladium] swift ffmpeg bridge error: {bridge_error}")
                    traceback.print_exc()
                    yt_exit_code = 1

                if yt_exit_code != 1:
                    if downloads_dir:
                        os.chdir(downloads_dir)
                    cleanup_temp_download_files(downloads_dir)
                    cleanup_existing_downloads(downloads_dir, download_url)

                    if is_cancel_requested(cancel_file_path):
                        print("[palladium] cancellation requested before yt-dlp start")
                        cancelled = True
                        yt_exit_code = 130

                    if yt_exit_code is None:
                        if download_preset == "custom":
                            preset_args = parse_custom_args(custom_args_text)
                            print("[palladium] preset: custom")
                        else:
                            preset_args = build_preset_args(download_preset)
                        extra_args = parse_extra_args(extra_args_text)

                        sys.argv = [
                            "yt-dlp",
                            "-v",
                            "--no-check-certificate",
                            "--remote-components",
                            "ejs:github",
                            "--force-overwrites",
                            "--no-continue",
                            "--ffmpeg-location",
                            ffmpeg_bridge_dir if ffmpeg_bridge_dir else ".",
                            "-P",
                            downloads_dir if downloads_dir else ".",
                            "-o",
                            "%(title)s [%(id)s].%(ext)s",
                            *preset_args,
                            *extra_args,
                            download_url,
                        ]

                        try:
                            with (
                                patch_subprocess_for_swiftffmpeg(bridge),
                                patch_ytdlp_popen_for_swiftffmpeg(bridge),
                                patch_ytdlp_ffmpeg_detection(),
                                patch_ytdlp_cancel(cancel_file_path),
                            ):
                                runpy.run_module("yt_dlp", run_name="__main__", alter_sys=True)
                            yt_exit_code = 0
                        except KeyboardInterrupt:
                            cancelled = True
                            yt_exit_code = 130
                            print("[palladium] yt-dlp cancelled by user")
                        except SystemExit as exc:
                            if exc.code is None:
                                yt_exit_code = 0
                            elif isinstance(exc.code, int):
                                yt_exit_code = exc.code
                            else:
                                print(f"[palladium] unexpected SystemExit code: {exc.code}")
                                yt_exit_code = 1
                        except Exception:
                            print("[palladium] yt-dlp execution failed")
                            traceback.print_exc()
                            yt_exit_code = 1

                if yt_exit_code == 0:
                    try:
                        log_text = output.getvalue()
                        destination_matches = re.findall(r"^\\[download\\] Destination: (.+)$", log_text, flags=re.MULTILINE)
                        already_downloaded_matches = []
                        for line in log_text.splitlines():
                            if line.startswith("[download]") and "has already been downloaded" in line:
                                candidate_line = line[len("[download]"):].strip()
                                candidate_line = candidate_line.split(" has already been downloaded", 1)[0].strip()
                                if candidate_line:
                                    already_downloaded_matches.append(candidate_line)
                        if destination_matches:
                            candidate = destination_matches[-1].strip()
                            if candidate:
                                downloaded_path = candidate
                        elif already_downloaded_matches:
                            candidate = already_downloaded_matches[-1].strip()
                            if candidate:
                                downloaded_path = candidate

                        scan_dir = downloads_dir if downloads_dir else os.getcwd()
                        if downloaded_path:
                            if not os.path.isabs(downloaded_path):
                                downloaded_path = os.path.join(scan_dir, downloaded_path)
                            if not os.path.isfile(downloaded_path):
                                downloaded_path = None

                        if downloaded_path is None:
                            candidates = []
                            for filename in os.listdir(scan_dir):
                                full_path = os.path.join(scan_dir, filename)
                                if os.path.isfile(full_path) and not filename.endswith(".part"):
                                    mtime = os.path.getmtime(full_path)
                                    if mtime >= (run_started_at - 3600):
                                        candidates.append((mtime, full_path))
                            if candidates:
                                downloaded_path = max(candidates, key=lambda item: item[0])[1]

                        if downloaded_path:
                            print(f"[palladium] downloaded file: {downloaded_path}")
                        else:
                            print("[palladium] downloaded file path not detected")
                    except Exception:
                        print("[palladium] unable to detect downloaded file path")
                        traceback.print_exc()
        except Exception:
            print("[palladium] unable to execute yt_dlp as __main__")
            traceback.print_exc()
            yt_exit_code = 1
        finally:
            sys.argv = argv_backup
            try:
                os.chdir(cwd_backup)
            except Exception:
                pass
            if live_log_stream is not None:
                try:
                    live_log_stream.flush()
                except Exception:
                    pass

        success = (pip_exit_code in (None, 0)) and (yt_exit_code == 0) and not cancelled
        print(f"[palladium] flow success: {success}")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "yt_exit_code": yt_exit_code,
        "cancelled": cancelled,
        "success": success,
        "downloaded_path": downloaded_path,
        "output": output.getvalue(),
    })


def run_package_maintenance(action):
    output = io.StringIO()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    success = False
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    live_fd_value = os.environ.get("PALLADIUM_LOG_FD")
    live_log_stream = None
    if live_fd_value:
        try:
            live_fd = int(live_fd_value)
            live_log_stream = os.fdopen(live_fd, "w", buffering=1, encoding="utf-8", errors="replace", closefd=False)
        except Exception:
            live_log_stream = None

    class Tee:
        def __init__(self, *streams):
            self.streams = [s for s in streams if s is not None]
        def write(self, data):
            for stream in self.streams:
                try:
                    stream.write(data)
                except UnicodeEncodeError:
                    safe_data = data.encode("ascii", "replace").decode("ascii")
                    stream.write(safe_data)
                if hasattr(stream, "flush"):
                    stream.flush()
            return len(data)
        def flush(self):
            for stream in self.streams:
                if hasattr(stream, "flush"):
                    stream.flush()

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")

        print(f"[palladium] package action: {action}")
        if action == "update":
            pip_attempted = True
            pip_main = ensure_pip_entrypoint()
            if pip_main is not None:
                try:
                    packages = ["yt-dlp", "yt-dlp-apple-webkit-jsi"]
                    pip_args = ["install", "-U", "--no-cache-dir", "--progress-bar", "off", "--no-color", *packages]
                    if install_target:
                        pip_args[1:1] = ["--target", install_target]
                    pip_result = pip_main(pip_args)
                    pip_exit_code = 0 if pip_result is None else int(pip_result)
                    print(f"[palladium] pip exit code: {pip_exit_code}")
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] pip update failed")
                    traceback.print_exc()
            else:
                pip_exit_code = 1

        versions = collect_versions()
        print(f"[palladium] yt-dlp version: {versions.get('yt-dlp')}")
        print(f"[palladium] yt-dlp-apple-webkit-jsi version: {versions.get('yt-dlp-apple-webkit-jsi')}")

        success = (pip_exit_code in (None, 0))
        print(f"[palladium] package flow success: {success}")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "success": success,
        "versions": versions,
        "output": output.getvalue(),
    })
"""#
}
