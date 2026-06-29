import contextlib
import json
import os
import sys
import traceback

from .packages import (
    build_package_install_plan,
    build_pip_install_args,
    check_package_updates,
    cleanup_target_package,
    collect_versions,
    ensure_pip_entrypoint,
    fetch_package_index_versions,
    filter_installable_packages,
    parse_package_source,
)
from .runtime import invalidate_runtime_package_modules, raise_if_cancel_requested
from .shared import TRACKED_PACKAGES, TailBuffer, Tee, YTDLP_RUNTIME_PACKAGES, open_live_log_stream
from .webkit_jsi import ensure_safe_webkit_jsi_runtime


def run_package_maintenance(action, custom_versions_json=None, live_log_fd_override=None, package_source_json_override=None):
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
    restart_required = False
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    cancel_file_path = os.environ.get("PALLADIUM_CANCEL_FILE", "").strip()
    live_log_stream = open_live_log_stream(live_log_fd_override)
    package_source = parse_package_source(package_source_json_override)

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
            print(f"[palladium] package source: {package_source.get('mode')}")
            if action == "versions":
                updates_available = False
                updates_summary = "Skipped update check."
                print("[palladium] quick version refresh only")
            elif action == "index_versions":
                updates_available = False
                updates_summary = "Skipped update check."
                available_versions = fetch_package_index_versions(
                    install_target,
                    allow_prereleases=bool(package_source.get("allow_prereleases")),
                )
                print("[palladium] fetched package index versions")
            else:
                updates_available, updates_summary = check_package_updates(
                    install_target,
                    package_source=package_source,
                    include_missing=action in ("update", "reinstall"),
                )
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

            if action in ("update", "reinstall"):
                should_install = True
                if should_install:
                    raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before pip startup")
                    pip_main = ensure_pip_entrypoint(install_target)
                    if pip_main is not None:
                        try:
                            installed_versions = collect_versions(install_target=install_target, allow_cache_fallback=False)
                            indexed_versions = fetch_package_index_versions(
                                install_target=install_target,
                                pip_main=pip_main,
                                allow_prereleases=bool(package_source.get("allow_prereleases")),
                            )
                            if action == "reinstall":
                                if package_source.get("mode") == "custom":
                                    packages = list(package_source.get("custom_specs") or [])
                                else:
                                    packages = filter_installable_packages(YTDLP_RUNTIME_PACKAGES)
                                cleanup_packages = list(YTDLP_RUNTIME_PACKAGES)
                            else:
                                packages, cleanup_packages = build_package_install_plan(
                                    installed_versions,
                                    indexed_versions,
                                    custom_versions=custom_versions,
                                    package_source=package_source,
                                )

                            if not packages:
                                print("[palladium] no package installs required")
                                pip_exit_code = 0
                            else:
                                pip_attempted = True
                                restart_required = invalidate_runtime_package_modules() or restart_required
                                if install_target:
                                    stale_removed = 0
                                    for package_name in cleanup_packages:
                                        raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled during cleanup")
                                        stale_removed += cleanup_target_package(install_target, package_name)
                                    print(f"[palladium] removed stale target package entries: {stale_removed}")
                                raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before pip install")
                                pip_args = build_pip_install_args(
                                    packages,
                                    install_target=install_target,
                                    allow_prereleases=bool(package_source.get("allow_prereleases")),
                                    upgrade=True,
                                )
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
                updates_available, updates_summary = check_package_updates(
                    install_target,
                    package_source=package_source,
                    include_missing=True,
                )
                print(f"[palladium] post-update updates available: {updates_available}")
                print(f"[palladium] post-update updates summary: {updates_summary}")

            if package_source.get("skip_webkit_patch"):
                print("[palladium] skipping webkit patch by configuration")
            else:
                raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before webkit patch")
                ensure_safe_webkit_jsi_runtime(install_target)

            raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before version collection")
            versions = collect_versions(install_target=install_target)
            print(f"[palladium] yt-dlp version: {versions.get('yt-dlp')}")
            print(f"[palladium] yt-dlp-apple-webkit-jsi version: {versions.get('yt-dlp-apple-webkit-jsi')}")
            print(f"[palladium] curl-cffi version: {versions.get('curl-cffi')}")
            print(f"[palladium] gallery-dl version: {versions.get('gallery-dl')}")
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
        "restart_required": restart_required,
        "output": output.getvalue(),
    })
