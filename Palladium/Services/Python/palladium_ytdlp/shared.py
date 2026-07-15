import os

MAX_CAPTURED_OUTPUT_CHARS = 250000
MANAGED_PIP_PACKAGES_FILE = "ManagedPipPackages.txt"


def parse_managed_package_lines(lines):
    packages = []
    locked_versions = {}
    seen_names = set()

    for line_number, raw_line in enumerate(lines, start=1):
        entry = str(raw_line).strip()
        if not entry or entry.startswith("#"):
            continue

        package_name = entry
        locked_version = ""
        if "[" in entry or "]" in entry:
            opening_bracket = entry.find("[")
            if opening_bracket <= 0 or not entry.endswith("]") or "[" in entry[opening_bracket + 1:-1]:
                raise ValueError(f"Invalid managed package entry on line {line_number}: {entry}")
            package_name = entry[:opening_bracket].strip()
            locked_version = entry[opening_bracket + 1:-1].strip()
            if not locked_version or "]" in locked_version:
                raise ValueError(f"Invalid managed package entry on line {line_number}: {entry}")

        if not package_name or any(character.isspace() for character in package_name):
            raise ValueError(f"Invalid managed package entry on line {line_number}: {entry}")

        normalized_name = package_name.lower()
        if normalized_name in seen_names:
            raise ValueError(f"Duplicate managed package on line {line_number}: {package_name}")

        seen_names.add(normalized_name)
        packages.append(package_name)
        if locked_version:
            locked_versions[package_name] = locked_version

    if not packages:
        raise ValueError("Managed pip package manifest is empty")

    return tuple(packages), locked_versions


def managed_package_manifest_path():
    configured_path = os.environ.get("PALLADIUM_MANAGED_PIP_PACKAGES", "").strip()
    if configured_path:
        return configured_path

    return os.path.abspath(os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "..",
        "Resources",
        MANAGED_PIP_PACKAGES_FILE,
    ))


def load_managed_packages():
    manifest_path = managed_package_manifest_path()
    try:
        with open(manifest_path, "r", encoding="utf-8") as manifest_file:
            return parse_managed_package_lines(manifest_file)
    except Exception as error:
        raise RuntimeError(f"Unable to load managed pip packages from {manifest_path}") from error


TRACKED_PACKAGES, MANAGED_PACKAGE_LOCKS = load_managed_packages()
YTDLP_RUNTIME_PACKAGES = tuple(name for name in TRACKED_PACKAGES if name.lower() != "pip")
BUNDLED_RUNTIME_PACKAGES = ("curl-cffi",)
DISPLAY_PACKAGES = TRACKED_PACKAGES
CLEANUP_PACKAGES = YTDLP_RUNTIME_PACKAGES
WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH = os.path.join(
    "yt_dlp_plugins", "webkit_jsi", "lib", "api.py"
)
EJS_MODULE_RELATIVE_PATH = os.path.join(
    "yt_dlp", "extractor", "youtube", "jsc", "_builtin", "ejs.py"
)


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


class Tee:
    def __init__(self, *streams):
        self.streams = [stream for stream in streams if stream is not None]

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

    def isatty(self):
        for stream in list(self.streams):
            checker = getattr(stream, "isatty", None)
            if checker is None:
                continue
            try:
                if checker():
                    return True
            except Exception:
                if stream in self.streams:
                    self.streams.remove(stream)
        return False

    def reconfigure(self, **_options):
        """Support tools that configure standard streams while output is being mirrored."""
        return None


def open_live_log_stream(live_fd_value):
    if live_fd_value in (None, "", False):
        return None

    try:
        live_fd = int(live_fd_value)
        if live_fd < 0:
            return None
        return os.fdopen(live_fd, "w", buffering=1, encoding="utf-8", errors="replace", closefd=False)
    except Exception:
        return None
