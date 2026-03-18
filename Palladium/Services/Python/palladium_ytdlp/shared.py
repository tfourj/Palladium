import os

MAX_CAPTURED_OUTPUT_CHARS = 250000
TRACKED_PACKAGES = ("yt-dlp", "yt-dlp-apple-webkit-jsi", "pip")
DISPLAY_PACKAGES = TRACKED_PACKAGES
CLEANUP_PACKAGES = ("yt-dlp", "yt-dlp-apple-webkit-jsi")
WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH = os.path.join(
    "yt_dlp_plugins", "webkit_jsi", "lib", "api.py"
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


def open_live_log_stream(live_fd_value):
    if not live_fd_value:
        return None

    try:
        live_fd = int(live_fd_value)
        return os.fdopen(live_fd, "w", buffering=1, encoding="utf-8", errors="replace", closefd=False)
    except Exception:
        return None
