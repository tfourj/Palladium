import contextlib
import json
import os
import runpy
import sys
import traceback
import importlib.metadata as importlib_metadata

from .args import (
    build_preset_args,
    has_custom_output_template,
    parse_custom_args,
    parse_extra_args,
    parse_preset_args_map,
    strip_checkbox_owned_download_args,
)
from .ffmpeg_bridge import (
    SwiftFFmpegBridge,
    YTDLPFFmpegBridgeAdapter,
    is_cancel_requested,
    patch_ytdlp_for_swiftffmpeg,
)
from .files import cleanup_temp_download_files, detect_downloaded_files, has_primary_media_file
from .packages import (
    build_package_install_plan,
    check_package_updates,
    cleanup_target_package,
    collect_versions,
    ensure_pip_entrypoint,
    fetch_package_index_versions,
)
from .shared import TRACKED_PACKAGES, TailBuffer, Tee, open_live_log_stream
from .webkit_jsi import ensure_safe_webkit_jsi_runtime


def raise_if_cancel_requested(cancel_file_path, message):
    if is_cancel_requested(cancel_file_path):
        print(message)
        raise KeyboardInterrupt("cancel requested")


def run_yt_dlp_flow(
    download_url_override=None,
    download_preset_override=None,
    preset_args_json_override=None,
    extra_args_override=None,
    download_playlist_override=None,
    download_subtitles_override=None,
    embed_thumbnail_override=None,
    subtitle_language_pattern_override=None,
    run_output_dir_override=None,
):
    output = TailBuffer()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    yt_exit_code = None
    downloaded_paths = []
    primary_downloaded_path = None
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
    if download_playlist_override is None:
        download_playlist = os.environ.get("PALLADIUM_DOWNLOAD_PLAYLIST", "").strip().lower() in ("1", "true", "yes", "on")
    else:
        download_playlist = bool(download_playlist_override)
    if download_subtitles_override is None:
        download_subtitles = os.environ.get("PALLADIUM_DOWNLOAD_SUBTITLES", "").strip().lower() in ("1", "true", "yes", "on")
    else:
        download_subtitles = bool(download_subtitles_override)
    if embed_thumbnail_override is None:
        embed_thumbnail = os.environ.get("PALLADIUM_EMBED_THUMBNAIL", "").strip().lower() in ("1", "true", "yes", "on")
    else:
        embed_thumbnail = bool(embed_thumbnail_override)
    if subtitle_language_pattern_override is None:
        subtitle_language_pattern = os.environ.get("PALLADIUM_SUBTITLE_LANGUAGE_PATTERN", "en").strip() or "en"
    else:
        subtitle_language_pattern = str(subtitle_language_pattern_override).strip() or "en"
    if subtitle_language_pattern == "en.*":
        subtitle_language_pattern = "en"
    downloads_dir = os.environ.get("PALLADIUM_DOWNLOADS", "").strip()
    if run_output_dir_override is None:
        run_output_dir = os.environ.get("PALLADIUM_RUN_OUTPUT_DIR", "").strip() or downloads_dir
    else:
        run_output_dir = str(run_output_dir_override).strip() or downloads_dir
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    cache_dir = os.environ.get("PALLADIUM_CACHE_DIR", "").strip()
    cancel_file_path = os.environ.get("PALLADIUM_CANCEL_FILE", "").strip()
    live_log_stream = open_live_log_stream(os.environ.get("PALLADIUM_LOG_FD"))

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        argv_backup = sys.argv[:]
        cwd_backup = os.getcwd()
        try:
            os.environ["PYTHONIOENCODING"] = "utf-8"
            if install_target:
                os.makedirs(install_target, exist_ok=True)
                if install_target not in sys.path:
                    sys.path.insert(0, install_target)
                print(f"[palladium] package install target: {install_target}")
            if downloads_dir:
                os.makedirs(downloads_dir, exist_ok=True)
                print(f"[palladium] download target: {downloads_dir}")
            if run_output_dir:
                os.makedirs(run_output_dir, exist_ok=True)
                print(f"[palladium] run output target: {run_output_dir}")
            if cache_dir:
                os.makedirs(cache_dir, exist_ok=True)
                print(f"[palladium] cache target: {cache_dir}")

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
                raise_if_cancel_requested(cancel_file_path, "[palladium] cancellation requested before pip install")
                pip_attempted = True
                pip_main = ensure_pip_entrypoint(install_target)
                if pip_main is not None:
                    packages = []
                    if needs_yt_dlp_install:
                        packages.append("yt-dlp")
                    if needs_webkit_jsi_install:
                        packages.append("yt-dlp-apple-webkit-jsi")

                    try:
                        raise_if_cancel_requested(cancel_file_path, "[palladium] cancellation requested before pip install")
                        pip_args = ["install", "--no-cache-dir", "--progress-bar", "off", "--no-color", *packages]
                        if install_target:
                            pip_args[1:1] = ["--target", install_target]
                        pip_args[1:1] = ["--disable-pip-version-check"]
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

            raise_if_cancel_requested(cancel_file_path, "[palladium] cancellation requested before webkit patch")
            ensure_safe_webkit_jsi_runtime(install_target)

            if not download_url:
                print("[palladium] no URL provided")
                yt_exit_code = 1
            elif is_cancel_requested(cancel_file_path):
                print("[palladium] cancellation requested before run")
                cancelled = True
                yt_exit_code = 130
            else:
                print(f"[palladium] running yt-dlp -v {download_url}")

            if download_url:
                raise_if_cancel_requested(cancel_file_path, "[palladium] cancellation requested before bridge startup")
                bridge = None
                bridge_adapter = None
                try:
                    bridge = SwiftFFmpegBridge()
                    bridge_adapter = YTDLPFFmpegBridgeAdapter(bridge, cancel_file_path=cancel_file_path)
                    print("[palladium][ffmpeg-bridge] bridge loaded")
                    print("[palladium][ffmpeg-bridge] startup probes skipped")
                except Exception as bridge_error:
                    print(f"[palladium] swift ffmpeg bridge error: {bridge_error}")
                    traceback.print_exc()
                    yt_exit_code = 1

                if yt_exit_code != 1:
                    if run_output_dir:
                        os.chdir(run_output_dir)
                    raise_if_cancel_requested(cancel_file_path, "[palladium] cancellation requested before download cleanup")
                    cleanup_temp_download_files(run_output_dir)

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
                        preset_args = strip_checkbox_owned_download_args(preset_args)
                        extra_args = strip_checkbox_owned_download_args(parse_extra_args(extra_args_text))
                        raise_if_cancel_requested(cancel_file_path, "[palladium] cancellation requested before yt-dlp invocation")
                        output_args = []
                        download_behavior_args = []
                        if has_custom_output_template(preset_args) or has_custom_output_template(extra_args):
                            print("[palladium] custom output template detected")
                        else:
                            if download_playlist:
                                output_args = ["-o", "%(playlist_index)03d - %(title)s.%(ext)s"]
                            else:
                                output_args = ["-o", "%(title)s.%(ext)s"]

                        if not download_playlist:
                            download_behavior_args.append("--no-playlist")

                        if download_subtitles:
                            download_behavior_args.extend(["--write-subs", "--write-auto-subs"])
                            if subtitle_language_pattern == "all":
                                download_behavior_args.append("--all-subs")
                            else:
                                download_behavior_args.extend(["--sub-langs", subtitle_language_pattern])

                        if embed_thumbnail:
                            download_behavior_args.extend(["--convert-thumbnails", "png", "--embed-thumbnail"])

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
                            "-P",
                            run_output_dir if run_output_dir else ".",
                            *output_args,
                            *download_behavior_args,
                            *preset_args,
                            *extra_args,
                            download_url,
                        ]

                        try:
                            with patch_ytdlp_for_swiftffmpeg(bridge_adapter):
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
                    scan_dir = run_output_dir if run_output_dir else downloads_dir if downloads_dir else os.getcwd()
                    downloaded_paths, primary_downloaded_path = detect_downloaded_files(scan_dir)
                    if downloaded_paths:
                        print(f"[palladium] downloaded files detected: {len(downloaded_paths)}")
                        if primary_downloaded_path:
                            print(f"[palladium] primary downloaded file: {primary_downloaded_path}")
                        if yt_exit_code != 0:
                            if has_primary_media_file(downloaded_paths):
                                print(f"[palladium] overriding yt-dlp exit code {yt_exit_code} because a media file exists")
                                yt_exit_code = 0
                            else:
                                print(f"[palladium] keeping yt-dlp exit code {yt_exit_code} because only sidecar files were downloaded")
                    else:
                        print("[palladium] downloaded files not detected")
                except Exception:
                    print("[palladium] unable to detect downloaded files")
                    traceback.print_exc()
        except KeyboardInterrupt:
            cancelled = True
            if yt_exit_code is None:
                yt_exit_code = 130
            print("[palladium] download flow cancelled by user")
        except BaseException:
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
        "downloaded_paths": downloaded_paths,
        "primary_downloaded_path": primary_downloaded_path,
        "downloaded_path": primary_downloaded_path,
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
    versions = {}
    cancelled = False
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    cancel_file_path = os.environ.get("PALLADIUM_CANCEL_FILE", "").strip()
    live_log_stream = open_live_log_stream(os.environ.get("PALLADIUM_LOG_FD"))

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")

        try:
            raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before start")
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
                    raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before pip startup")
                    pip_main = ensure_pip_entrypoint(install_target)
                    if pip_main is not None:
                        try:
                            installed_versions = collect_versions(install_target=install_target, allow_cache_fallback=False)
                            indexed_versions = fetch_package_index_versions(install_target=install_target, pip_main=pip_main)
                            packages, cleanup_packages = build_package_install_plan(
                                installed_versions,
                                indexed_versions,
                                custom_versions=custom_versions,
                            )

                            if not packages:
                                print("[palladium] no package installs required")
                                pip_exit_code = 0
                            else:
                                pip_attempted = True
                                if install_target:
                                    stale_removed = 0
                                    for package_name in cleanup_packages:
                                        raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled during cleanup")
                                        stale_removed += cleanup_target_package(install_target, package_name)
                                    print(f"[palladium] removed stale target package entries: {stale_removed}")
                                raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before pip install")
                                pip_args = [
                                    "install",
                                    "--upgrade",
                                    "--disable-pip-version-check",
                                    "--no-cache-dir",
                                    "--progress-bar",
                                    "off",
                                    "--no-color",
                                    *packages,
                                ]
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

                raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before post-update check")
                updates_available, updates_summary = check_package_updates(install_target)
                print(f"[palladium] post-update updates available: {updates_available}")
                print(f"[palladium] post-update updates summary: {updates_summary}")

            raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before webkit patch")
            ensure_safe_webkit_jsi_runtime(install_target)

            raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before version collection")
            versions = collect_versions(install_target=install_target)
            print(f"[palladium] yt-dlp version: {versions.get('yt-dlp')}")
            print(f"[palladium] yt-dlp-apple-webkit-jsi version: {versions.get('yt-dlp-apple-webkit-jsi')}")
            print(f"[palladium] pip version: {versions.get('pip')}")

            success = (pip_exit_code in (None, 0))
            print(f"[palladium] package flow success: {success}")
        except KeyboardInterrupt:
            cancelled = True
            success = False
            print("[palladium] package action cancelled by user")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "success": success,
        "cancelled": cancelled,
        "updates_available": updates_available,
        "updates_summary": updates_summary,
        "versions": versions,
        "available_versions": available_versions,
        "output": output.getvalue(),
    })
