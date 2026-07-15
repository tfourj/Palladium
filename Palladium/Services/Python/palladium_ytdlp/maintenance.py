import contextlib
import json
import os
import sys
import traceback

from .packages import (
    build_package_install_plan,
    build_pip_install_args,
    check_package_updates,
    clear_payload_packages,
    cleanup_target_package,
    collect_versions,
    ensure_pip_entrypoint,
    fetch_package_index_versions,
    filter_installable_packages,
    install_payload_zip,
    managed_package_names,
    parse_package_source,
    runtime_package_names,
)
from .patching import apply_youtube_patches, youtube_patch_state_warning
from .runtime import invalidate_runtime_package_modules, raise_if_cancel_requested
from .shared import TailBuffer, Tee, open_live_log_stream


ACTION_CHECK = "check"
ACTION_VERSIONS = "versions"
ACTION_UPDATE = "update"
ACTION_REINSTALL = "reinstall"
ACTION_INDEX_VERSIONS = "index_versions"
ACTION_INSTALL_PAYLOAD_ZIP = "install_payload_zip"
ACTION_RESTORE_PIP_PACKAGES = "restore_pip_packages"
PACKAGE_INSTALL_ACTIONS = (ACTION_UPDATE, ACTION_REINSTALL)


def ensure_package_path(path, label):
    if not path:
        return

    os.makedirs(path, exist_ok=True)
    if path not in sys.path:
        sys.path.insert(0, path)
    print(f"[palladium] {label}: {path}")


def parse_custom_versions(custom_versions_json, package_source=None):
    custom_versions = {}
    if not custom_versions_json:
        return custom_versions

    try:
        parsed_versions = json.loads(custom_versions_json)
        if isinstance(parsed_versions, dict):
            for package_name in managed_package_names(package_source):
                raw_value = parsed_versions.get(package_name)
                if raw_value is None:
                    continue
                requested_version = str(raw_value).strip()
                if requested_version:
                    custom_versions[package_name] = requested_version
    except Exception:
        print("[palladium] failed to parse custom version payload")
        traceback.print_exc()

    return custom_versions


def check_or_fetch_package_updates(action, install_target, package_source):
    if action == ACTION_VERSIONS:
        print("[palladium] quick version refresh only")
        return False, "Skipped update check.", {}

    if action == ACTION_INSTALL_PAYLOAD_ZIP:
        print("[palladium] payload bundle install requested")
        return False, "Installing payload bundle.", {}

    if action == ACTION_RESTORE_PIP_PACKAGES:
        print("[palladium] pip package restore requested")
        return False, "Restoring pip packages.", {}

    if action == ACTION_INDEX_VERSIONS:
        available_versions = fetch_package_index_versions(
            install_target,
            allow_prereleases=bool(package_source.get("allow_prereleases")),
            package_source=package_source,
        )
        print("[palladium] fetched package index versions")
        return False, "Skipped update check.", available_versions

    updates_available, updates_summary = check_package_updates(
        install_target,
        package_source=package_source,
        include_missing=action in PACKAGE_INSTALL_ACTIONS,
    )
    print(f"[palladium] updates available: {updates_available}")
    print(f"[palladium] updates summary: {updates_summary}")
    return updates_available, updates_summary, {}


def reinstall_package_plan(package_source):
    if package_source.get("mode") == "custom":
        packages = list(package_source.get("custom_specs") or [])
    else:
        packages = filter_installable_packages(runtime_package_names(package_source))
    return packages, list(runtime_package_names(package_source))


def install_payload_action(payload_zip_path, manual_payload_target, cancel_file_path):
    raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before payload install")
    restart_required = invalidate_runtime_package_modules()
    installed_packages = install_payload_zip(payload_zip_path, manual_payload_target)
    return {
        "pip_exit_code": 0,
        "restart_required": restart_required,
        "updates_summary": f"Installed payload bundle for {', '.join(installed_packages)}.",
    }


def restore_pip_packages_action(
    install_target,
    manual_payload_target,
    package_source,
    custom_versions,
    cancel_file_path,
):
    raise_if_cancel_requested(
        cancel_file_path,
        "[palladium] package action cancelled before payload cleanup",
    )
    restart_required = invalidate_runtime_package_modules()
    removed_entries = clear_payload_packages(manual_payload_target)
    print(f"[palladium] removed manual payload entries: {removed_entries}")

    result = install_package_updates(
        ACTION_REINSTALL,
        install_target,
        package_source,
        custom_versions,
        cancel_file_path,
    )
    result["restart_required"] = result["restart_required"] or restart_required
    result["updates_summary"] = "Restored pip-managed packages."
    return result


def install_package_updates(action, install_target, package_source, custom_versions, cancel_file_path):
    raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before pip startup")
    pip_main = ensure_pip_entrypoint(install_target)
    if pip_main is None:
        return {
            "pip_attempted": False,
            "pip_exit_code": 1,
            "restart_required": False,
        }

    installed_versions = collect_versions(
        install_target=install_target,
        allow_cache_fallback=False,
        package_source=package_source,
    )
    indexed_versions = fetch_package_index_versions(
        install_target=install_target,
        pip_main=pip_main,
        allow_prereleases=bool(package_source.get("allow_prereleases")),
        package_source=package_source,
    )
    if action == ACTION_REINSTALL:
        packages, cleanup_packages = reinstall_package_plan(package_source)
    else:
        packages, cleanup_packages = build_package_install_plan(
            installed_versions,
            indexed_versions,
            custom_versions=custom_versions,
            package_source=package_source,
        )

    if not packages:
        print("[palladium] no package installs required")
        return {
            "pip_attempted": False,
            "pip_exit_code": 0,
            "restart_required": False,
        }

    restart_required = invalidate_runtime_package_modules()
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
        force_reinstall=action == ACTION_REINSTALL,
    )
    pip_result = pip_main(pip_args)
    pip_exit_code = 0 if pip_result is None else int(pip_result)
    print(f"[palladium] pip exit code: {pip_exit_code}")
    return {
        "pip_attempted": True,
        "pip_exit_code": pip_exit_code,
        "restart_required": restart_required,
    }


def run_package_maintenance(
    action,
    custom_versions_json=None,
    live_log_fd_override=None,
    package_source_json_override=None,
    payload_zip_path_override=None,
):
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
    patch_state_warning = False
    did_package_install_action = False
    allow_version_cache_fallback = True
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    manual_payload_target = os.environ.get("PALLADIUM_MANUAL_PAYLOAD_PACKAGES") or install_target
    cancel_file_path = os.environ.get("PALLADIUM_CANCEL_FILE", "").strip()
    live_log_stream = open_live_log_stream(live_log_fd_override)
    package_source = parse_package_source(package_source_json_override)

    with (
        contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)),
        contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)),
    ):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        ensure_package_path(install_target, "package install target")
        if manual_payload_target != install_target:
            ensure_package_path(manual_payload_target, "manual payload package target")

        try:
            raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before start")
            print(f"[palladium] package action: {action}")
            print(f"[palladium] package source: {package_source.get('mode')}")

            updates_available, updates_summary, available_versions = check_or_fetch_package_updates(
                action,
                install_target,
                package_source,
            )

            custom_versions = parse_custom_versions(custom_versions_json, package_source)
            if custom_versions:
                print(f"[palladium] custom package versions requested: {custom_versions}")

            if action == ACTION_RESTORE_PIP_PACKAGES:
                try:
                    result = restore_pip_packages_action(
                        install_target,
                        manual_payload_target,
                        package_source,
                        custom_versions,
                        cancel_file_path,
                    )
                    pip_attempted = result["pip_attempted"]
                    pip_exit_code = result["pip_exit_code"]
                    restart_required = result["restart_required"] or restart_required
                    updates_summary = result["updates_summary"]
                    did_package_install_action = True
                    allow_version_cache_fallback = False
                except Exception:
                    pip_exit_code = 1
                    updates_summary = "Pip package restore failed."
                    allow_version_cache_fallback = False
                    print("[palladium] pip package restore failed")
                    traceback.print_exc()

            if action == ACTION_INSTALL_PAYLOAD_ZIP:
                try:
                    result = install_payload_action(
                        payload_zip_path_override,
                        manual_payload_target,
                        cancel_file_path,
                    )
                    pip_exit_code = result["pip_exit_code"]
                    restart_required = result["restart_required"] or restart_required
                    updates_summary = result["updates_summary"]
                except Exception:
                    pip_exit_code = 1
                    updates_summary = "Payload bundle install failed."
                    print("[palladium] payload bundle install failed")
                    traceback.print_exc()

            if action in PACKAGE_INSTALL_ACTIONS:
                try:
                    result = install_package_updates(
                        action,
                        install_target,
                        package_source,
                        custom_versions,
                        cancel_file_path,
                    )
                    pip_attempted = result["pip_attempted"]
                    pip_exit_code = result["pip_exit_code"]
                    restart_required = result["restart_required"] or restart_required
                    did_package_install_action = True
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] pip update failed")
                    traceback.print_exc()

            if did_package_install_action:
                raise_if_cancel_requested(
                    cancel_file_path,
                    "[palladium] package action cancelled before post-update check",
                )
                updates_available, updates_summary = check_package_updates(
                    install_target,
                    package_source=package_source,
                    include_missing=True,
                )
                print(f"[palladium] post-update updates available: {updates_available}")
                print(f"[palladium] post-update updates summary: {updates_summary}")

            raise_if_cancel_requested(cancel_file_path, "[palladium] package action cancelled before youtube patches")
            apply_youtube_patches(install_target, package_source.get("patch_mode"))
            patch_state_warning = youtube_patch_state_warning(
                install_target,
                package_source.get("patch_mode"),
            )

            raise_if_cancel_requested(
                cancel_file_path,
                "[palladium] package action cancelled before version collection",
            )
            versions = collect_versions(
                install_target=install_target,
                allow_cache_fallback=allow_version_cache_fallback,
                package_source=package_source,
            )
            print(f"[palladium] yt-dlp version: {versions.get('yt-dlp')}")
            print(f"[palladium] yt-dlp-apple-webkit-jsi version: {versions.get('yt-dlp-apple-webkit-jsi')}")
            print(f"[palladium] curl-cffi version: {versions.get('curl-cffi')}")
            print(f"[palladium] gallery-dl version: {versions.get('gallery-dl')}")
            print(f"[palladium] mutagen version: {versions.get('mutagen')}")
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
        "patch_state_warning": patch_state_warning,
        "output": output.getvalue(),
    })
