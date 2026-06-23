import contextlib
import json
import os
import re
import sys
import traceback
import urllib.parse

from .files import cleanup_temp_download_files, detect_downloaded_files
from .packages import (
    build_pip_install_args,
    ensure_pip_entrypoint,
    is_package_installed,
    parse_package_source,
)
from .runtime import GalleryDLOutputCapture, run_gallery_dl_module
from .shared import TailBuffer, Tee, open_live_log_stream


def ensure_gallery_dl_installed(install_target, package_source):
    installed, version, source = is_package_installed("gallery-dl", install_target=install_target)
    if installed:
        print(f"[palladium] gallery-dl already installed ({version} via {source})")
        return False, 0

    print("[palladium] gallery-dl package missing")
    pip_main = ensure_pip_entrypoint(install_target)
    if pip_main is None:
        return True, 1

    packages = ["gallery-dl"]
    pip_args = build_pip_install_args(
        packages,
        install_target=install_target,
        allow_prereleases=bool(package_source.get("allow_prereleases")),
    )
    result = pip_main(pip_args)
    exit_code = 0 if result is None else int(result)
    print(f"[palladium] gallery-dl pip exit code: {exit_code}")
    return True, exit_code


def gallery_dl_args(url, cookie_file_path=None, destination=None, selection_range=None, resolve=False):
    args = ["gallery-dl", "--config-ignore", "--no-colors", "--verbose"]
    if cookie_file_path:
        if os.path.isfile(cookie_file_path):
            args.extend(["--cookies", cookie_file_path])
        else:
            print(f"[palladium] cookie file missing, ignoring: {cookie_file_path}")
    if resolve:
        args.append("--resolve-urls")
    if destination:
        args.extend(["--destination", destination])
    if selection_range:
        args.extend(["--range", selection_range])
    args.append(url)
    return args


GALLERY_AUDIO_EXTENSIONS = {
    ".aac",
    ".aif",
    ".aiff",
    ".alac",
    ".flac",
    ".m4a",
    ".mp3",
    ".oga",
    ".ogg",
    ".opus",
    ".wav",
    ".weba",
    ".wma",
}

GALLERY_IMAGE_EXTENSIONS = {
    ".avif",
    ".bmp",
    ".gif",
    ".heic",
    ".heif",
    ".jpeg",
    ".jpg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
}

GALLERY_AUDIO_URL_HINTS = (
    "audio_mpeg",
    "audio/mp",
    "mime_type=audio",
    "mime_type%3daudio",
    "music",
)


def gallery_item_media_type(url):
    try:
        parsed = urllib.parse.urlparse(url)
        path = urllib.parse.unquote(parsed.path)
        extension = os.path.splitext(path)[1].lower()
        decoded_url = urllib.parse.unquote(url).lower()
    except Exception:
        extension = ""
        decoded_url = str(url).lower()
    if extension in GALLERY_AUDIO_EXTENSIONS:
        return "audio"
    if extension in GALLERY_IMAGE_EXTENSIONS:
        return "image"
    if any(hint in decoded_url for hint in GALLERY_AUDIO_URL_HINTS):
        return "audio"
    return "file"


def gallery_item_title(url, index, media_type="image"):
    try:
        path = urllib.parse.unquote(urllib.parse.urlparse(url).path)
        name = os.path.basename(path)
        if name:
            return name
    except Exception:
        pass
    if media_type == "audio":
        return f"Audio {index}"
    if media_type == "file":
        return f"File {index}"
    return f"Image {index}"


def gallery_resolution_error_message(output):
    """Return gallery-dl's last user-facing error line without diagnostic noise."""
    for line in reversed(output.splitlines()):
        match = re.match(r"^\[[^\]]+\]\[error\]\s+(.+)$", line.strip(), re.IGNORECASE)
        if match:
            return match.group(1)
    return None


def run_gallery_dl_resolver(download_url_override=None, cookie_file_path_override=None, live_log_fd_override=None, package_source_json_override=None):
    output = TailBuffer()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    live_log_stream = open_live_log_stream(live_log_fd_override)
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    package_source = parse_package_source(package_source_json_override)
    url = str(download_url_override or "").strip()
    cookie_file_path = str(cookie_file_path_override or "").strip()
    argv_backup = sys.argv[:]
    items = []
    pip_attempted = False
    pip_exit_code = None
    success = False
    captured_output = ""
    gallery_dl_exit_code = None

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        try:
            if install_target:
                os.makedirs(install_target, exist_ok=True)
                if install_target not in sys.path:
                    sys.path.insert(0, install_target)
            if not url:
                print("[palladium] gallery-dl resolver received no URL")
            else:
                pip_attempted, pip_exit_code = ensure_gallery_dl_installed(install_target, package_source)
                if pip_exit_code == 0:
                    captured = GalleryDLOutputCapture()
                    sys.argv = gallery_dl_args(url, cookie_file_path=cookie_file_path, resolve=True)
                    try:
                        with contextlib.redirect_stdout(captured):
                            run_gallery_dl_module()
                    except SystemExit as exc:
                        if exc.code not in (None, 0):
                            gallery_dl_exit_code = exc.code
                    finally:
                        captured_output = captured.getvalue()

                    if gallery_dl_exit_code is None:
                        seen = set()
                        for line in captured_output.splitlines():
                            candidate = line.strip()
                            if not candidate.startswith(("http://", "https://")) or candidate in seen:
                                continue
                            seen.add(candidate)
                            media_type = gallery_item_media_type(candidate)
                            items.append({
                                "index": len(items) + 1,
                                "url": candidate,
                                "title": gallery_item_title(candidate, len(items) + 1, media_type),
                                "media_type": media_type,
                            })
                        success = bool(items)
                        print(f"[palladium] gallery-dl resolved {len(items)} item(s)")
        except Exception:
            print("[palladium] gallery-dl resolution failed")
            traceback.print_exc()
        finally:
            sys.argv = argv_backup
            if live_log_stream is not None:
                live_log_stream.flush()

    error_message = None
    if not success:
        error_message = gallery_resolution_error_message("\n".join((captured_output, output.getvalue())))

    return json.dumps({
        "success": success,
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "items": items,
        "output": output.getvalue(),
        "error_message": error_message,
    })


def run_gallery_dl_flow(download_url_override=None, selection_range_override=None, cookie_file_path_override=None, run_output_dir_override=None, live_log_fd_override=None, package_source_json_override=None):
    output = TailBuffer()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    live_log_stream = open_live_log_stream(live_log_fd_override)
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    url = str(download_url_override or "").strip()
    selection_range = str(selection_range_override or "").strip()
    cookie_file_path = str(cookie_file_path_override or "").strip()
    run_output_dir = str(run_output_dir_override or "").strip()
    package_source = parse_package_source(package_source_json_override)
    argv_backup = sys.argv[:]
    pip_attempted = False
    pip_exit_code = None
    exit_code = 1
    cancelled = False
    downloaded_paths = []
    primary_downloaded_path = None

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        try:
            if install_target:
                os.makedirs(install_target, exist_ok=True)
                if install_target not in sys.path:
                    sys.path.insert(0, install_target)
            if run_output_dir:
                os.makedirs(run_output_dir, exist_ok=True)
                cleanup_temp_download_files(run_output_dir)
            pip_attempted, pip_exit_code = ensure_gallery_dl_installed(install_target, package_source)
            if pip_exit_code == 0 and url and selection_range:
                sys.argv = gallery_dl_args(
                    url,
                    cookie_file_path,
                    run_output_dir,
                    selection_range,
                )
                print(f"[palladium] running gallery-dl for selected range: {selection_range}")
                try:
                    run_gallery_dl_module()
                    exit_code = 0
                except KeyboardInterrupt:
                    cancelled = True
                    exit_code = 130
                except SystemExit as exc:
                    exit_code = 0 if exc.code in (None, 0) else int(exc.code)
            else:
                print("[palladium] gallery-dl download missing URL or selected images")

            if not cancelled and run_output_dir:
                downloaded_paths, primary_downloaded_path = detect_downloaded_files(run_output_dir)
                if downloaded_paths and exit_code != 0:
                    exit_code = 0
        except KeyboardInterrupt:
            cancelled = True
            exit_code = 130
        except Exception:
            print("[palladium] gallery-dl download failed")
            traceback.print_exc()
        finally:
            sys.argv = argv_backup
            if live_log_stream is not None:
                live_log_stream.flush()

    success = pip_exit_code in (None, 0) and exit_code == 0 and bool(downloaded_paths) and not cancelled
    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "yt_exit_code": exit_code,
        "cancelled": cancelled,
        "success": success,
        "downloaded_paths": downloaded_paths,
        "primary_downloaded_path": primary_downloaded_path,
        "downloaded_path": primary_downloaded_path,
        "output": output.getvalue(),
        "result_kind": "cancelled" if cancelled else ("success" if success else "error"),
    })
