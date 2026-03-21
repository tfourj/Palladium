import contextlib
import ctypes
import io
import json
import os
import re
import shlex
import shutil
import subprocess
import time
import urllib.parse


class SwiftFFmpegBridge:
    def __init__(self):
        self._run = None
        self._free = None
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
            # yt-dlp sometimes passes local file inputs as `file:/...` without
            # percent-encoding reserved characters like `#`. Parsing those as a
            # URL truncates the real filename at the fragment delimiter, so keep
            # the raw file payload and only strip the scheme before decoding.
            decoded_path = urllib.parse.unquote(value[5:])
            if decoded_path:
                value = decoded_path
        normalized.append(value)
    return normalized


def bridge_ffmpeg_output_path(args):
    for arg in reversed(args):
        if arg in ("-nostats", "-nostdin"):
            continue
        return arg
    return None


def prepare_bridge_ffmpeg_args(tool, args):
    prepared = normalize_ffmpeg_args(args)
    if tool == "ffmpeg":
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
            prepared = ["-nostats", *prepared]
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


def extract_ffprobe_json_payload(output_text):
    text = str(output_text or "")
    stripped = text.strip()
    if not stripped:
        return "", ""

    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, dict):
            return stripped, ""
    except Exception:
        pass

    decoder = json.JSONDecoder()
    for idx, char in enumerate(text):
        if char != "{":
            continue
        snippet = text[idx:]
        try:
            parsed, end = decoder.raw_decode(snippet)
        except Exception:
            continue
        if not isinstance(parsed, dict):
            continue
        if not any(key in parsed for key in ("streams", "format", "programs", "chapters", "frames", "packets", "error")):
            continue
        json_payload = snippet[:end].strip()
        noise = (text[:idx] + snippet[end:]).strip()
        return json_payload, noise

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        candidate = text[start:end + 1].strip()
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                noise = (text[:start] + text[end + 1:]).strip()
                return candidate, noise
        except Exception:
            pass

    return None, stripped


def split_bridge_output(tool, output):
    text = str(output or "")
    if tool != "ffprobe":
        return text, text

    stdout_text, stderr_text = extract_ffprobe_json_payload(text)
    if stdout_text is None:
        return text, text
    return stdout_text, stderr_text


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
    text = str(output_text or "")
    for line in text.splitlines():
        stripped = line.strip()
        prefix = f"{tool} version "
        if stripped.lower().startswith(prefix):
            version_text = stripped[len(prefix):].split(None, 1)[0]
            return clean_bridge_version(version_text)
    return None


def parse_bridge_libavformat_version(output_text):
    text = str(output_text or "")
    match = re.search(r"(?m)^\s*libavformat\s+(?:[0-9. ]+)\s+/\s+([0-9. ]+)", text)
    if not match:
        return None
    return match.group(1).replace(" ", "")


def is_outdated_bridge_version(version_text, minimum_version_text):
    def to_parts(value):
        return [int(piece) for piece in re.findall(r"\d+", str(value or ""))]

    current = to_parts(version_text)
    minimum = to_parts(minimum_version_text)
    if not current or not minimum:
        return False

    size = max(len(current), len(minimum))
    current += [0] * (size - len(current))
    minimum += [0] * (size - len(minimum))
    return current < minimum


def probe_bridge_ffmpeg_capabilities(bridge):
    cached = getattr(bridge, "_palladium_ffmpeg_capabilities", None)
    if cached is not None:
        return cached

    result = {
        "versions": {"ffmpeg": None, "ffprobe": None},
        "features": {},
    }

    try:
        _, ffmpeg_output = bridge.run("ffmpeg", ["-bsfs"])
        ffmpeg_version = parse_bridge_executable_version(ffmpeg_output, "ffmpeg")
        libavformat_version = parse_bridge_libavformat_version(ffmpeg_output)
        result["versions"]["ffmpeg"] = ffmpeg_version
        result["features"] = {
            "fdk": "--enable-libfdk-aac" in ffmpeg_output,
            "setts": "setts" in ffmpeg_output.splitlines(),
            "needs_adtstoasc": is_outdated_bridge_version(libavformat_version, "57.56.100"),
        }
    except Exception as error:
        print(f"[palladium][ffmpeg-bridge] ffmpeg capability probe failed: {error}")

    try:
        _, ffprobe_output = bridge.run("ffprobe", ["-version"])
        result["versions"]["ffprobe"] = parse_bridge_executable_version(ffprobe_output, "ffprobe")
    except Exception as error:
        print(f"[palladium][ffmpeg-bridge] ffprobe version probe failed: {error}")

    bridge._palladium_ffmpeg_capabilities = result
    if result["versions"]["ffmpeg"] or result["versions"]["ffprobe"]:
        print(
            "[palladium][ffmpeg-bridge] probed versions:"
            f" ffmpeg={result['versions']['ffmpeg'] or 'unknown'}"
            f" ffprobe={result['versions']['ffprobe'] or 'unknown'}"
        )
    if result["features"]:
        print(f"[palladium][ffmpeg-bridge] probed features: {result['features']}")
    return result


@contextlib.contextmanager
def patch_ytdlp_ffprobe_metadata_fallback():
    try:
        from yt_dlp.postprocessor.ffmpeg import FFmpegPostProcessor
    except Exception:
        yield
        return

    original_get_metadata_object = getattr(FFmpegPostProcessor, "get_metadata_object", None)
    if original_get_metadata_object is None:
        yield
        return

    def patched_get_metadata_object(self, *args, **kwargs):
        try:
            return original_get_metadata_object(self, *args, **kwargs)
        except json.JSONDecodeError:
            target_path = args[0] if args else kwargs.get("path", "<unknown>")
            print(f"[palladium][ffmpeg-bridge] ffprobe metadata parse failed for {target_path}; using empty metadata fallback")
            return {"streams": [], "format": {}}

    FFmpegPostProcessor.get_metadata_object = patched_get_metadata_object
    try:
        yield
    finally:
        FFmpegPostProcessor.get_metadata_object = original_get_metadata_object


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
                stdout_output, stderr_output = split_bridge_output(tool, output)
                elapsed = time.time() - started_at
                print(f"[palladium][ffmpeg-bridge] {tool} finished in {elapsed:.2f}s")
                if tool == "ffmpeg" and bridged_args:
                    target_path = bridge_ffmpeg_output_path(bridged_args)
                    if target_path and os.path.isfile(target_path):
                        try:
                            target_size = os.path.getsize(target_path)
                            print(f"[palladium][ffmpeg-bridge] output file ready: {target_path} ({target_size} bytes)")
                        except Exception:
                            print(f"[palladium][ffmpeg-bridge] output file ready: {target_path}")
                    else:
                        print(f"[palladium][ffmpeg-bridge] output file missing after run: {target_path or '<unknown>'}")
            except Exception as bridge_error:
                raise RuntimeError(f"swift ffmpeg bridge error: {bridge_error}") from bridge_error

            print(f"[palladium][ffmpeg-bridge] exit={self.returncode}")

            if text_mode:
                self._stdout_value = stdout_output
                self._stderr_value = stderr_output
                stdout_stream = io.StringIO(stdout_output)
                stderr_stream = io.StringIO(stderr_output)
            else:
                out_bytes = stdout_output.encode(encoding, errors=errors)
                err_bytes = stderr_output.encode(encoding, errors=errors)
                self._stdout_value = out_bytes
                self._stderr_value = err_bytes
                stdout_stream = io.BytesIO(out_bytes)
                stderr_stream = io.BytesIO(err_bytes)

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
            stdout_output, stderr_output = split_bridge_output(tool, output)
            elapsed = time.time() - started_at
            print(f"[palladium][ffmpeg-bridge] yt-dlp Popen {tool} finished in {elapsed:.2f}s")
            if tool == "ffmpeg" and bridged_args:
                target_path = bridge_ffmpeg_output_path(bridged_args)
                if target_path and os.path.isfile(target_path):
                    try:
                        target_size = os.path.getsize(target_path)
                        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file ready: {target_path} ({target_size} bytes)")
                    except Exception:
                        print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file ready: {target_path}")
                else:
                    print(f"[palladium][ffmpeg-bridge] yt-dlp Popen output file missing after run: {target_path or '<unknown>'}")
            if text_mode:
                self._stdout_value = stdout_output
                self._stderr_value = stderr_output
            else:
                out_bytes = stdout_output.encode(encoding, errors=errors)
                err_bytes = stderr_output.encode(encoding, errors=errors)
                self._stdout_value = out_bytes
                self._stderr_value = err_bytes
            if kwargs.get("stderr") == subprocess.STDOUT:
                if text_mode:
                    self._stdout_value = f"{stdout_output}{stderr_output}"
                else:
                    self._stdout_value = out_bytes + err_bytes
                self._stderr_value = None
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
def patch_ytdlp_ffmpeg_detection(bridge):
    original_get_ffmpeg_version = None
    ffmpeg_pp = None

    try:
        from yt_dlp.postprocessor.ffmpeg import FFmpegPostProcessor
        ffmpeg_pp = FFmpegPostProcessor
    except Exception:
        yield
        return

    if hasattr(ffmpeg_pp, "_get_ffmpeg_version"):
        original_get_ffmpeg_version = ffmpeg_pp._get_ffmpeg_version

        def patched_get_ffmpeg_version(self, prog):
            version = None
            features = {}
            try:
                version, features = original_get_ffmpeg_version(self, prog)
            except Exception as error:
                print(f"[palladium][ffmpeg-bridge] yt-dlp {prog} probe failed; using bridge fallback: {error}")

            if version and (prog != "ffmpeg" or features):
                return version, features

            fallback = probe_bridge_ffmpeg_capabilities(bridge)
            fallback_version = fallback["versions"].get(prog)
            fallback_features = dict(fallback["features"]) if prog == "ffmpeg" else {}

            if version and prog == "ffmpeg" and fallback_features:
                return version, fallback_features
            if fallback_version or fallback_features:
                print(f"[palladium][ffmpeg-bridge] using bridge-derived {prog} metadata")
                return fallback_version or version, fallback_features or features
            return version, features

        ffmpeg_pp._get_ffmpeg_version = patched_get_ffmpeg_version

    try:
        print("[palladium][ffmpeg-bridge] yt-dlp ffmpeg detection fallback enabled")
        yield
    finally:
        if original_get_ffmpeg_version is not None:
            ffmpeg_pp._get_ffmpeg_version = original_get_ffmpeg_version
