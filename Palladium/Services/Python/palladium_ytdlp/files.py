import os
import re
import traceback
import urllib.parse

PRIMARY_MEDIA_EXTENSIONS = {
    "3gp", "aac", "aiff", "avi", "flac", "m4a", "m4v", "mkv", "mov", "mp3",
    "mp4", "mpeg", "mpg", "ogg", "opus", "ts", "wav", "webm",
}
IMAGE_MEDIA_EXTENSIONS = {
    "gif", "heic", "heif", "jpeg", "jpg", "png", "webp",
}
SUBTITLE_SIDE_CAR_EXTENSIONS = {
    "ass", "lrc", "srt", "srv1", "srv2", "srv3", "ttml", "vtt",
}
AUXILIARY_SIDE_CAR_EXTENSIONS = {
    "description", "json", "nfo",
}


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


def collect_downloaded_file_paths(scan_dir):
    if not scan_dir or not os.path.isdir(scan_dir):
        return []

    collected = []
    try:
        for root, dirnames, filenames in os.walk(scan_dir):
            dirnames[:] = [
                name for name in dirnames
                if not name.startswith(".") and name not in {".palladium-ffmpeg", ".cache"}
            ]

            for filename in filenames:
                if filename.startswith(".") or is_temp_download_artifact(filename):
                    continue

                full_path = os.path.join(root, filename)
                if not os.path.isfile(full_path):
                    continue

                try:
                    if os.path.getsize(full_path) <= 0:
                        continue
                except Exception:
                    continue

                collected.append(os.path.abspath(full_path))
    except Exception:
        print("[palladium] failed to collect downloaded files")
        traceback.print_exc()
        return []

    return sorted(collected, key=lambda path: os.path.relpath(path, scan_dir).lower())


def choose_primary_downloaded_path(paths):
    if not paths:
        return None

    def path_priority(path):
        filename = os.path.basename(path).lower()
        extension = os.path.splitext(filename)[1].lstrip(".")
        if extension in PRIMARY_MEDIA_EXTENSIONS:
            return (0, path.lower())
        if extension in IMAGE_MEDIA_EXTENSIONS:
            return (1, path.lower())
        if extension in SUBTITLE_SIDE_CAR_EXTENSIONS or extension in AUXILIARY_SIDE_CAR_EXTENSIONS:
            return (3, path.lower())
        return (2, path.lower())

    return min(paths, key=path_priority)


def has_primary_media_file(paths):
    for path in paths or []:
        extension = os.path.splitext(os.path.basename(path).lower())[1].lstrip(".")
        if extension in PRIMARY_MEDIA_EXTENSIONS:
            return True
    return False


def filter_user_visible_downloaded_paths(paths, primary_path):
    if not paths:
        return []

    primary_extension = os.path.splitext(os.path.basename(primary_path).lower())[1].lstrip(".") if primary_path else ""
    visible_paths = []

    for path in paths:
        extension = os.path.splitext(os.path.basename(path).lower())[1].lstrip(".")

        if extension in AUXILIARY_SIDE_CAR_EXTENSIONS:
            continue
        if primary_extension in PRIMARY_MEDIA_EXTENSIONS and extension in IMAGE_MEDIA_EXTENSIONS:
            continue

        visible_paths.append(path)

    return visible_paths or paths


def detect_downloaded_files(scan_dir):
    all_downloaded_paths = collect_downloaded_file_paths(scan_dir)
    primary_path = choose_primary_downloaded_path(all_downloaded_paths)
    visible_paths = filter_user_visible_downloaded_paths(all_downloaded_paths, primary_path)
    return visible_paths, choose_primary_downloaded_path(visible_paths)
