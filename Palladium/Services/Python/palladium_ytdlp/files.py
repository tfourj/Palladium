import os
import re
import traceback
import urllib.parse


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
