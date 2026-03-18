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

MAX_CAPTURED_OUTPUT_CHARS = 250000
TRACKED_PACKAGES = ("yt-dlp", "yt-dlp-apple-webkit-jsi", "pip")
DISPLAY_PACKAGES = TRACKED_PACKAGES
CLEANUP_PACKAGES = ("yt-dlp", "yt-dlp-apple-webkit-jsi")
DEFAULT_YOUTUBE_EXTRACTOR_ARGS = "youtube:webpage_client=web"


class TailBuffer:
    def __init__(self, max_chars=MAX_CAPTURED_OUTPUT_CHARS):
        self.max_chars = max_chars
        self.parts = []
        self.length = 0
        self.truncated = False

    def write(self, data):
        text = str(data)
        if not text:
            return 0
        self.parts.append(text)
        self.length += len(text)
        self._trim_left_if_needed()
        return len(text)

    def flush(self):
        return None

    def getvalue(self):
        value = "".join(self.parts)
        if self.truncated:
            return f"[palladium] output truncated to last {self.max_chars} chars\\n{value}"
        return value

    def _trim_left_if_needed(self):
        overflow = self.length - self.max_chars
        if overflow <= 0:
            return

        self.truncated = True
        while overflow > 0 and self.parts:
            head = self.parts[0]
            head_len = len(head)
            if head_len <= overflow:
                self.parts.pop(0)
                self.length -= head_len
                overflow -= head_len
                continue

            self.parts[0] = head[overflow:]
            self.length -= overflow
            overflow = 0


def has_pip_in_target(install_target):
    if not install_target or not os.path.isdir(install_target):
        return False

    try:
        for distribution in importlib_metadata.distributions(path=[install_target]):
            metadata_name = ""
            try:
                metadata_name = str(distribution.metadata.get("Name", ""))
            except Exception:
                metadata_name = str(getattr(distribution, "name", ""))
            if metadata_name.strip().lower() == "pip":
                return True
    except Exception:
        return False

    return False


def ensure_pip_entrypoint(install_target=None):
    pip_main = None
    try:
        from pip._internal.cli.main import main as pip_main
        return pip_main
    except ModuleNotFoundError:
        # Expected on our embedded Python runtime before bootstrapping pip.
        print("[palladium] pip module missing, loading ensurepip bundle")
    except Exception:
        print("[palladium] pip entrypoint failed, attempting ensurepip fallback")
        traceback.print_exc()

    try:
        import ensurepip
        with ensurepip._get_pip_whl_path_ctx() as pip_wheel:
            pip_wheel_str = str(pip_wheel)
            if pip_wheel_str not in sys.path:
                sys.path.insert(0, pip_wheel_str)
            from pip._internal.cli.main import main as pip_main
            print("[palladium] pip loaded from ensurepip bundled wheel")

            if install_target and not has_pip_in_target(install_target):
                try:
                    os.makedirs(install_target, exist_ok=True)
                    bootstrap_args = [
                        "install",
                        "--no-index",
                        "--no-color",
                        "--progress-bar",
                        "off",
                        "--no-input",
                        "--target",
                        install_target,
                        "--upgrade",
                        pip_wheel_str,
                    ]
                    pip_result = pip_main(bootstrap_args)
                    pip_exit = 0 if pip_result is None else int(pip_result)
                    if pip_exit == 0:
                        print(f"[palladium] pip installed into target: {install_target}")
                    else:
                        print(f"[palladium] pip target install failed (exit={pip_exit})")
                except Exception:
                    print("[palladium] pip target install failed")
                    traceback.print_exc()

                if install_target not in sys.path:
                    sys.path.insert(0, install_target)

            return pip_main
    except Exception:
        print("[palladium] ensurepip fallback failed")
        traceback.print_exc()
        return None


def package_versions_cache_path(install_target=None):
    base_dir = install_target or os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    if not base_dir:
        return None
    try:
        os.makedirs(base_dir, exist_ok=True)
    except Exception:
        return None
    return os.path.join(base_dir, ".palladium-package-versions.json")


def load_cached_versions(install_target=None):
    cache_path = package_versions_cache_path(install_target)
    if not cache_path or not os.path.isfile(cache_path):
        return {}

    try:
        with open(cache_path, "r", encoding="utf-8") as cache_file:
            parsed = json.load(cache_file)
        if not isinstance(parsed, dict):
            return {}
        resolved = {}
        for package_name in TRACKED_PACKAGES:
            value = parsed.get(package_name)
            if value is None:
                continue
            version_text = str(value).strip()
            if version_text:
                resolved[package_name] = version_text
        return resolved
    except Exception:
        return {}


def save_cached_versions(versions, install_target=None):
    cache_path = package_versions_cache_path(install_target)
    if not cache_path:
        return

    payload = {}
    for package_name in TRACKED_PACKAGES:
        version_value = str(versions.get(package_name, "")).strip()
        if version_value and version_value not in ("not installed", "unknown"):
            payload[package_name] = version_value

    if not payload:
        return

    temp_path = cache_path + ".tmp"
    try:
        with open(temp_path, "w", encoding="utf-8") as cache_file:
            json.dump(payload, cache_file)
        os.replace(temp_path, cache_path)
    except Exception:
        try:
            if os.path.exists(temp_path):
                os.remove(temp_path)
        except Exception:
            pass


def canonical_package_name(name):
    return re.sub(r"[-_.]+", "-", str(name or "").strip().lower())


def version_from_install_target(package_name, install_target):
    if not install_target or not os.path.isdir(install_target):
        return None

    wanted = canonical_package_name(package_name)
    candidates = []
    try:
        for distribution in importlib_metadata.distributions(path=[install_target]):
            metadata_name = ""
            try:
                metadata_name = str(distribution.metadata.get("Name", ""))
            except Exception:
                metadata_name = str(getattr(distribution, "name", ""))

            if canonical_package_name(metadata_name) != wanted:
                continue

            version_value = str(getattr(distribution, "version", "") or "").strip()
            if not version_value:
                continue

            mtime = 0.0
            try:
                dist_path = getattr(distribution, "_path", None)
                if dist_path is not None:
                    mtime = os.path.getmtime(str(dist_path))
            except Exception:
                mtime = 0.0
            candidates.append((mtime, version_value))
    except Exception:
        return None

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def cleanup_target_package(install_target, package_name):
    if not install_target or not os.path.isdir(install_target):
        return 0

    normalized_name = canonical_package_name(package_name)
    import_name = str(package_name).replace("-", "_").strip().lower()
    removed = 0

    try:
        for entry in os.listdir(install_target):
            full_path = os.path.join(install_target, entry)
            if not os.path.exists(full_path):
                continue

            lower_entry = entry.lower()
            should_remove = False

            if lower_entry in {import_name, f"{import_name}.py"}:
                should_remove = True
            elif lower_entry.endswith(".dist-info"):
                stem = lower_entry[:-10]
                normalized_stem = canonical_package_name(stem)
                should_remove = normalized_stem == normalized_name or normalized_stem.startswith(f"{normalized_name}-")
            elif lower_entry.endswith(".egg-info"):
                stem = lower_entry[:-9]
                normalized_stem = canonical_package_name(stem)
                should_remove = normalized_stem == normalized_name or normalized_stem.startswith(f"{normalized_name}-")

            if not should_remove:
                continue

            try:
                if os.path.isdir(full_path):
                    shutil.rmtree(full_path, ignore_errors=False)
                else:
                    os.remove(full_path)
                removed += 1
            except Exception:
                print(f"[palladium] failed to remove stale target entry: {entry}")
                traceback.print_exc()
    except Exception:
        print(f"[palladium] failed cleanup scan for {package_name}")
        traceback.print_exc()

    return removed


def collect_versions(install_target=None, allow_cache_fallback=True):
    cached_versions = load_cached_versions(install_target) if allow_cache_fallback else {}
    versions = {}
    for package_name in DISPLAY_PACKAGES:
        target_version = version_from_install_target(package_name, install_target)
        if target_version:
            versions[package_name] = target_version
            continue

        resolved_version = None
        try:
            resolved_version = importlib_metadata.version(package_name)
        except Exception:
            resolved_version = None

        if resolved_version:
            versions[package_name] = resolved_version
            continue

        if package_name in TRACKED_PACKAGES:
            cached_version = cached_versions.get(package_name, "").strip()
            if allow_cache_fallback and cached_version:
                versions[package_name] = cached_version
            else:
                versions[package_name] = "not installed"
        else:
            versions[package_name] = "not installed"

    save_cached_versions(versions, install_target)
    return versions


def check_package_updates(install_target=None):
    pip_main = ensure_pip_entrypoint(install_target)
    if pip_main is None:
        return False, "Unable to check updates (pip unavailable)."

    def normalized_version(value):
        return str(value or "").strip()

    def build_update_lines(installed_versions, indexed_versions):
        lines = []
        for package_name in TRACKED_PACKAGES:
            current_version = normalized_version(installed_versions.get(package_name))
            if not current_version or current_version in ("not installed", "unknown"):
                continue

            indexed = indexed_versions.get(package_name) or []
            latest_version = ""
            for candidate in indexed:
                latest_version = normalized_version(candidate)
                if latest_version:
                    break
            if not latest_version:
                continue

            if latest_version != current_version:
                lines.append(f"{package_name}: {current_version} -> {latest_version}")
        return lines

    try:
        installed_versions = collect_versions(install_target=install_target, allow_cache_fallback=False)
        indexed_versions = fetch_package_index_versions(install_target=install_target, pip_main=pip_main)
        update_lines = build_update_lines(installed_versions, indexed_versions)
        if update_lines:
            return True, "\\n".join(update_lines)
        if indexed_versions:
            return False, "All packages are up to date."

        # Fallback path if index query failed.
        pip_args = ["list", "--outdated", "--format=json"]
        if install_target:
            pip_args.extend(["--path", install_target])

        capture = io.StringIO()
        with contextlib.redirect_stdout(capture):
            pip_rc = pip_main(pip_args)

        if pip_rc not in (None, 0):
            return False, f"Unable to check updates (pip exit code {pip_rc})."

        raw = capture.getvalue().strip()
        if not raw:
            return False, "All packages are up to date."

        items = None
        try:
            items = json.loads(raw)
        except Exception:
            lines = [line.strip() for line in raw.splitlines() if line.strip()]
            for line in reversed(lines):
                if line.startswith("[") and line.endswith("]"):
                    try:
                        items = json.loads(line)
                        break
                    except Exception:
                        continue
        if items is None:
            return False, "All packages are up to date."
        if not isinstance(items, list):
            return False, "All packages are up to date."

        tracked = {name.lower() for name in TRACKED_PACKAGES}
        relevant = [item for item in items if str(item.get("name", "")).lower() in tracked]
        if not relevant:
            return False, "All packages are up to date."

        lines = []
        for item in relevant:
            name = str(item.get("name", "package"))
            package_key = name.lower()
            old_ver = normalized_version(item.get("version", "?")) or "?"
            new_ver = normalized_version(item.get("latest_version", "?")) or "?"

            installed_ver = normalized_version(installed_versions.get(package_key))
            if installed_ver and installed_ver not in ("not installed", "unknown"):
                old_ver = installed_ver

            if old_ver == new_ver:
                continue

            lines.append(f"{name}: {old_ver} -> {new_ver}")

        if not lines:
            return False, "All packages are up to date."

        return True, "\\n".join(lines)
    except Exception:
        traceback.print_exc()
        return False, "Unable to check updates."


def parse_index_versions_output(raw_output):
    text = str(raw_output or "")
    if not text:
        return []

    lines = [line.rstrip() for line in text.splitlines()]
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.lower().startswith("available versions:"):
            continue

        suffix = stripped.split(":", 1)[1].strip() if ":" in stripped else ""
        chunks = [suffix] if suffix else []

        for candidate in lines[index + 1:]:
            clean = candidate.strip()
            if not clean:
                break
            lower = clean.lower()
            if lower.startswith("installed:") or lower.startswith("latest:"):
                break
            if lower.startswith("[notice]") or lower.startswith("warning:") or lower.startswith("error:"):
                break
            chunks.append(clean)

        combined = " ".join(chunks)
        parsed_versions = []
        for piece in combined.split(","):
            version_text = piece.strip()
            if version_text:
                parsed_versions.append(version_text)
        if parsed_versions:
            return parsed_versions
    return []


def fetch_package_index_versions(install_target=None, pip_main=None):
    if pip_main is None:
        pip_main = ensure_pip_entrypoint(install_target)
    if pip_main is None:
        return {}

    resolved = {}
    for package_name in TRACKED_PACKAGES:
        try:
            capture = io.StringIO()
            pip_args = [
                "index",
                "versions",
                "--disable-pip-version-check",
                "--no-color",
                package_name,
            ]
            with contextlib.redirect_stdout(capture), contextlib.redirect_stderr(capture):
                pip_rc = pip_main(pip_args)
            if pip_rc not in (None, 0):
                print(f"[palladium] pip index failed for {package_name} (exit={pip_rc})")
                continue

            parsed_versions = parse_index_versions_output(capture.getvalue())
            if parsed_versions:
                resolved[package_name] = parsed_versions[:120]
                print(f"[palladium] fetched {len(resolved[package_name])} index versions for {package_name}")
            else:
                print(f"[palladium] no index versions parsed for {package_name}")
        except Exception:
            print(f"[palladium] failed to fetch index versions for {package_name}")
            traceback.print_exc()
    return resolved


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
            parsed = urllib.parse.urlparse(value)
            decoded_path = urllib.parse.unquote(parsed.path)
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

            if not is_temp_download_artifact(name):
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


def is_temp_download_artifact(name):
    lower = str(name).lower()
    return (
        lower.endswith(".part")
        or lower.endswith(".ytdl")
        or lower.endswith(".tmp")
        or ".temp." in lower
        or re.search(r"\.f\d+\.[a-z0-9]+\.part$", lower) is not None
        or ".frag" in lower
        or ".fhls-" in lower
    )


def detect_downloaded_file_path(log_text, scan_dir, run_started_at):
    downloaded_path = None
    destination_matches = re.findall(r"^\[download\] Destination: (.+)$", log_text, flags=re.MULTILINE)
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

    if downloaded_path:
        if not os.path.isabs(downloaded_path):
            downloaded_path = os.path.join(scan_dir, downloaded_path)
        if not os.path.isfile(downloaded_path):
            downloaded_path = None

    if downloaded_path is None:
        candidates = []
        for filename in os.listdir(scan_dir):
            full_path = os.path.join(scan_dir, filename)
            if not os.path.isfile(full_path) or is_temp_download_artifact(filename):
                continue
            mtime = os.path.getmtime(full_path)
            if mtime >= (run_started_at - 3600):
                candidates.append((mtime, full_path))
        if candidates:
            downloaded_path = max(candidates, key=lambda item: item[0])[1]

    if downloaded_path and os.path.getsize(downloaded_path) <= 0:
        return None
    return downloaded_path


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


CLI_DASHLIKE_PREFIX = "?\u2010\u2011\u2012\u2013\u2014\u2015\u2212\uFE58\uFE63\uFF0D"


def normalize_cli_arg_token(token):
    value = str(token)
    if not value:
        return value
    if value.startswith("--"):
        return value
    if value.startswith("-") and (len(value) == 1 or value[1] not in CLI_DASHLIKE_PREFIX):
        return value
    if value.startswith(("http://", "https://", "file:/", "/")):
        return value
    if value[0] not in CLI_DASHLIKE_PREFIX:
        return value

    match = re.match(rf"^[{re.escape(CLI_DASHLIKE_PREFIX)}-]+([A-Za-z][A-Za-z0-9_-]*)(.*)$", value)
    if not match:
        return value

    option_name = match.group(1)
    suffix = match.group(2)
    prefix = "-" if len(option_name) == 1 else "--"
    normalized = f"{prefix}{option_name}{suffix}"
    if normalized != value:
        print(f"[palladium] normalized arg token: {value!r} -> {normalized!r}")
    return normalized


def normalize_cli_args(tokens):
    return [normalize_cli_arg_token(token) for token in tokens]


def parse_custom_args(custom_args_value):
    if not custom_args_value:
        return []
    try:
        parsed = normalize_cli_args(shlex.split(str(custom_args_value)))
        print(f"[palladium] custom args parsed: {parsed}")
        return parsed
    except Exception:
        print("[palladium] failed to parse custom args")
        traceback.print_exc()
        return []


def parse_preset_args_map(preset_args_json_value):
    defaults = {
        "auto_video": "",
        "mute": "",
        "audio": "",
        "custom": "",
    }
    if not preset_args_json_value:
        return defaults

    try:
        parsed = json.loads(str(preset_args_json_value))
        if not isinstance(parsed, dict):
            return defaults
        output = defaults.copy()
        for key in output.keys():
            if key in parsed and isinstance(parsed[key], str):
                output[key] = parsed[key].strip()
        return output
    except Exception:
        print("[palladium] failed to parse preset args json")
        traceback.print_exc()
        return defaults


def parse_extra_args(extra_args_value):
    if not extra_args_value:
        return []
    try:
        parsed = normalize_cli_args(shlex.split(str(extra_args_value)))
        print(f"[palladium] extra args parsed: {parsed}")
        return parsed
    except Exception:
        print("[palladium] failed to parse extra args")
        traceback.print_exc()
        return []


def has_custom_output_template(args):
    normalized = [str(arg) for arg in (args or [])]
    for index, arg in enumerate(normalized):
        if arg == "-o":
            return index + 1 < len(normalized)
        if arg == "--output":
            return index + 1 < len(normalized)
        if arg.startswith("--output="):
            return True
    return False


def has_youtube_webpage_client_override(args):
    normalized = [str(arg) for arg in (args or [])]
    for index, arg in enumerate(normalized):
        value = None
        if arg == "--extractor-args" and index + 1 < len(normalized):
            value = normalized[index + 1]
        elif arg.startswith("--extractor-args="):
            value = arg.split("=", 1)[1]

        if not value:
            continue

        lowered = value.lower()
        if "youtube:" in lowered and "webpage_client=" in lowered:
            return True

    return False


def build_default_extractor_args(*arg_sets):
    for arg_set in arg_sets:
        if has_youtube_webpage_client_override(arg_set):
            print("[palladium] keeping user-provided youtube webpage_client extractor args")
            return []

    print(f"[palladium] using default extractor args: {DEFAULT_YOUTUBE_EXTRACTOR_ARGS}")
    return ["--extractor-args", DEFAULT_YOUTUBE_EXTRACTOR_ARGS]


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


def run_yt_dlp_flow(download_url_override=None, download_preset_override=None, preset_args_json_override=None, extra_args_override=None):
    output = TailBuffer()
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
    if preset_args_json_override is None:
        preset_args_json = os.environ.get("PALLADIUM_PRESET_ARGS_JSON", "").strip()
    else:
        preset_args_json = str(preset_args_json_override).strip()
    if extra_args_override is None:
        extra_args_text = os.environ.get("PALLADIUM_EXTRA_ARGS", "").strip()
    else:
        extra_args_text = str(extra_args_override).strip()
    downloads_dir = os.environ.get("PALLADIUM_DOWNLOADS", "").strip()
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    cache_dir = os.environ.get("PALLADIUM_CACHE_DIR", "").strip()
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
            for stream in list(self.streams):
                try:
                    stream.write(data)
                except UnicodeEncodeError:
                    safe_data = data.encode("ascii", "replace").decode("ascii")
                    try:
                        stream.write(safe_data)
                    except Exception:
                        if stream in self.streams:
                            self.streams.remove(stream)
                        continue
                except Exception:
                    if stream in self.streams:
                        self.streams.remove(stream)
                    continue
                if hasattr(stream, "flush"):
                    try:
                        stream.flush()
                    except Exception:
                        if stream in self.streams:
                            self.streams.remove(stream)
            return len(data)
        def flush(self):
            for stream in list(self.streams):
                if hasattr(stream, "flush"):
                    try:
                        stream.flush()
                    except Exception:
                        if stream in self.streams:
                            self.streams.remove(stream)

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
        if cache_dir:
            os.makedirs(cache_dir, exist_ok=True)
            print(f"[palladium] cache target: {cache_dir}")

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
            pip_main = ensure_pip_entrypoint(install_target)
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
                        preset_args_map = parse_preset_args_map(preset_args_json)
                        selected_args = preset_args_map.get(download_preset, "")
                        if selected_args:
                            preset_args = parse_custom_args(selected_args)
                            print(f"[palladium] preset args override: {download_preset}")
                        elif download_preset == "custom":
                            preset_args = []
                            print("[palladium] preset: custom (no args)")
                        else:
                            preset_args = build_preset_args(download_preset)
                        extra_args = parse_extra_args(extra_args_text)
                        default_extractor_args = build_default_extractor_args(preset_args, extra_args)
                        output_args = []
                        if has_custom_output_template(preset_args) or has_custom_output_template(extra_args):
                            print("[palladium] custom output template detected")
                        else:
                            output_args = ["-o", "%(title)s.%(ext)s"]

                        sys.argv = [
                            "yt-dlp",
                            "-v",
                            "--no-check-certificate",
                            "--remote-components",
                            "ejs:github",
                            "--cache-dir",
                            cache_dir if cache_dir else os.path.join(downloads_dir if downloads_dir else ".", ".cache"),
                            "--force-overwrites",
                            "--no-continue",
                            "--ffmpeg-location",
                            ffmpeg_bridge_dir if ffmpeg_bridge_dir else ".",
                            "-P",
                            downloads_dir if downloads_dir else ".",
                            *default_extractor_args,
                            *output_args,
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

                if not cancelled and yt_exit_code is not None:
                    try:
                        log_text = output.getvalue()
                        scan_dir = downloads_dir if downloads_dir else os.getcwd()
                        downloaded_path = detect_downloaded_file_path(log_text, scan_dir, run_started_at)
                        if downloaded_path:
                            print(f"[palladium] downloaded file: {downloaded_path}")
                            if yt_exit_code != 0:
                                print(f"[palladium] overriding yt-dlp exit code {yt_exit_code} because downloaded file exists")
                                yt_exit_code = 0
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


def run_package_maintenance(action, custom_versions_json=None):
    output = TailBuffer()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    success = False
    updates_available = False
    updates_summary = "Not checked yet."
    available_versions = {}
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
            for stream in list(self.streams):
                try:
                    stream.write(data)
                except UnicodeEncodeError:
                    safe_data = data.encode("ascii", "replace").decode("ascii")
                    try:
                        stream.write(safe_data)
                    except Exception:
                        if stream in self.streams:
                            self.streams.remove(stream)
                        continue
                except Exception:
                    if stream in self.streams:
                        self.streams.remove(stream)
                    continue
                if hasattr(stream, "flush"):
                    try:
                        stream.flush()
                    except Exception:
                        if stream in self.streams:
                            self.streams.remove(stream)
            return len(data)
        def flush(self):
            for stream in list(self.streams):
                if hasattr(stream, "flush"):
                    try:
                        stream.flush()
                    except Exception:
                        if stream in self.streams:
                            self.streams.remove(stream)

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")

        print(f"[palladium] package action: {action}")
        if action == "versions":
            updates_available = False
            updates_summary = "Skipped update check."
            print("[palladium] quick version refresh only")
        elif action == "index_versions":
            updates_available = False
            updates_summary = "Skipped update check."
            available_versions = fetch_package_index_versions(install_target)
            print("[palladium] fetched package index versions")
        else:
            updates_available, updates_summary = check_package_updates(install_target)
            print(f"[palladium] updates available: {updates_available}")
            print(f"[palladium] updates summary: {updates_summary}")

        custom_versions = {}
        if custom_versions_json:
            try:
                parsed_versions = json.loads(custom_versions_json)
                if isinstance(parsed_versions, dict):
                    for package_name in TRACKED_PACKAGES:
                        raw_value = parsed_versions.get(package_name)
                        if raw_value is None:
                            continue
                        requested_version = str(raw_value).strip()
                        if requested_version:
                            custom_versions[package_name] = requested_version
            except Exception:
                print("[palladium] failed to parse custom version payload")
                traceback.print_exc()
        if custom_versions:
            print(f"[palladium] custom package versions requested: {custom_versions}")

        if action == "update":
            if updates_available or bool(custom_versions):
                pip_attempted = True
                pip_main = ensure_pip_entrypoint(install_target)
                if pip_main is not None:
                    try:
                        if custom_versions:
                            if install_target:
                                stale_removed = 0
                                for package_name in CLEANUP_PACKAGES:
                                    stale_removed += cleanup_target_package(install_target, package_name)
                                print(f"[palladium] removed stale target package entries: {stale_removed}")
                            packages = []
                            for package_name in TRACKED_PACKAGES:
                                version = custom_versions.get(package_name)
                                if version:
                                    packages.append(f"{package_name}=={version}")
                                else:
                                    packages.append(package_name)
                            pip_args = [
                                "install",
                                "--upgrade",
                                "--force-reinstall",
                                "--no-cache-dir",
                                "--progress-bar",
                                "off",
                                "--no-color",
                                *packages,
                            ]
                        else:
                            packages = list(TRACKED_PACKAGES)
                            pip_args = ["install", "--upgrade", "--no-cache-dir", "--progress-bar", "off", "--no-color", *packages]
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
            else:
                print("[palladium] no updates available; skipping update")

            updates_available, updates_summary = check_package_updates(install_target)
            print(f"[palladium] post-update updates available: {updates_available}")
            print(f"[palladium] post-update updates summary: {updates_summary}")

        versions = collect_versions(install_target=install_target)
        print(f"[palladium] yt-dlp version: {versions.get('yt-dlp')}")
        print(f"[palladium] yt-dlp-apple-webkit-jsi version: {versions.get('yt-dlp-apple-webkit-jsi')}")
        print(f"[palladium] pip version: {versions.get('pip')}")

        success = (pip_exit_code in (None, 0))
        print(f"[palladium] package flow success: {success}")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "success": success,
        "updates_available": updates_available,
        "updates_summary": updates_summary,
        "versions": versions,
        "available_versions": available_versions,
        "output": output.getvalue(),
    })
