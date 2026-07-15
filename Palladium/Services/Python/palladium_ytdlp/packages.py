import contextlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import traceback
import zipfile
import importlib.metadata as importlib_metadata
from email.parser import Parser

from .patching import DEFAULT_YOUTUBE_PATCH_MODE, normalize_youtube_patch_mode
from .shared import (
    BUNDLED_RUNTIME_PACKAGES,
    MANAGED_PACKAGE_LOCKS,
    TRACKED_PACKAGES,
    WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH,
)


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


def disable_pip_import_audit_hook():
    """Stop pip from installing its post-install import-audit hook.

    pip 26.1 installs a permanent, process-global audit hook during `pip install`
    that warns (and, from pip 26.3, raises) on the first import of any non-stdlib
    module once an install has started. That check assumes pip's normal
    one-command-per-process CLI usage. Palladium drives pip inside a single
    long-lived interpreter and deliberately imports freshly installed packages
    (yt-dlp and its dependencies, pip's own index command) right after installing
    them, so the hook only ever produces false positives here. Setting pip's own
    idempotency flag makes `_prevent_further_imports` treat the hook as already
    installed and skip adding it. Must run before any pip install in the process.
    """
    try:
        import pip._internal.commands.install as pip_install
        pip_install._IMPORT_AUDIT_HOOK_INSTALLED = True
    except Exception:
        pass


def ensure_pip_entrypoint(install_target=None, install_target_pip=True):
    pip_main = None
    try:
        from pip._internal.cli.main import main as pip_main
        disable_pip_import_audit_hook()
        return pip_main
    except ModuleNotFoundError:
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
            disable_pip_import_audit_hook()
            print("[palladium] pip loaded from ensurepip bundled wheel")

            if install_target and install_target_pip and not has_pip_in_target(install_target):
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


def load_cached_versions(install_target=None, package_names=None):
    cache_path = package_versions_cache_path(install_target)
    if not cache_path or not os.path.isfile(cache_path):
        return {}

    try:
        with open(cache_path, "r", encoding="utf-8") as cache_file:
            parsed = json.load(cache_file)
        if not isinstance(parsed, dict):
            return {}
        resolved = {}
        for package_name in package_names or TRACKED_PACKAGES:
            value = parsed.get(package_name)
            if value is None:
                continue
            version_text = str(value).strip()
            if version_text:
                resolved[package_name] = version_text
        return resolved
    except Exception:
        return {}


def save_cached_versions(versions, install_target=None, package_names=None):
    cache_path = package_versions_cache_path(install_target)
    if not cache_path:
        return

    payload = {}
    for package_name in package_names or TRACKED_PACKAGES:
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


def normalized_additional_package_name(value):
    package_name = str(value or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?", package_name):
        return ""
    return canonical_package_name(package_name)


def managed_package_names(package_source=None):
    package_source = package_source or {}
    names = list(TRACKED_PACKAGES)
    names.extend(package_source.get("additional_packages") or [])

    resolved = []
    seen = set()
    for name in names:
        normalized_name = canonical_package_name(name)
        if not normalized_name or normalized_name in seen:
            continue
        seen.add(normalized_name)
        resolved.append(str(name))
    return tuple(resolved)


def runtime_package_names(package_source=None):
    return tuple(
        name for name in managed_package_names(package_source)
        if canonical_package_name(name) != "pip"
    )


def wheel_safe_package_name(name):
    return re.sub(r"[-_.]+", "_", str(name or "").strip().lower())


def package_marker_paths(package_name):
    normalized_name = canonical_package_name(package_name)
    import_name = str(package_name or "").replace("-", "_").strip().lower()
    candidates = [import_name, f"{import_name}.py"]
    if normalized_name == "yt-dlp-apple-webkit-jsi":
        candidates.append(WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH)
    if normalized_name == "gallery-dl":
        candidates.append("gallery_dl")
    return tuple(candidates)


def package_owned_paths(package_name):
    normalized_name = canonical_package_name(package_name)
    if normalized_name == "yt-dlp-apple-webkit-jsi":
        return (os.path.join("yt_dlp_plugins", "webkit_jsi"),)
    return package_marker_paths(package_name)


def has_target_package_marker(package_name, install_target):
    if not install_target or not os.path.isdir(install_target):
        return False

    for relative_path in package_marker_paths(package_name):
        if not relative_path:
            continue
        candidate_path = os.path.join(install_target, relative_path)
        if os.path.exists(candidate_path):
            return True

    return False


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

    if not has_target_package_marker(package_name, install_target):
        return None

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def bundled_packages_path():
    path = os.environ.get("PALLADIUM_BUNDLED_PYTHON_PACKAGES", "").strip()
    if path and os.path.isdir(path):
        return path
    return None


def manual_payload_packages_path():
    path = os.environ.get("PALLADIUM_MANUAL_PAYLOAD_PACKAGES", "").strip()
    if path and os.path.isdir(path):
        return path
    return None


def manual_payload_package_version(package_name):
    if canonical_package_name(package_name) not in {
        canonical_package_name(name) for name in TRACKED_PACKAGES
    }:
        return None

    return version_from_install_target(package_name, manual_payload_packages_path())


def bundled_package_version(package_name):
    if canonical_package_name(package_name) not in {
        canonical_package_name(name) for name in BUNDLED_RUNTIME_PACKAGES
    }:
        return None

    return version_from_install_target(package_name, bundled_packages_path())


def bundled_runtime_package_source(package_name):
    if manual_payload_package_version(package_name) is not None:
        return "payload"
    if bundled_package_version(package_name) is not None:
        return "bundled"
    return None


def is_bundled_runtime_package(package_name):
    return bundled_runtime_package_source(package_name) is not None


def filter_installable_packages(package_names):
    return [
        package_name for package_name in package_names
        if not is_bundled_runtime_package(package_name)
    ]


def display_version(package_name, version):
    version_text = str(version or "").strip()
    package_source = bundled_runtime_package_source(package_name)
    if version_text and package_source == "payload":
        return f"{version_text} (payload)"
    if version_text and package_source == "bundled":
        return f"{version_text} (bundled)"
    return version_text


def installed_version(package_name, install_target=None):
    manual_payload_version = manual_payload_package_version(package_name)
    if manual_payload_version:
        return manual_payload_version

    bundled_version = bundled_package_version(package_name)
    if bundled_version:
        return bundled_version

    target_version = version_from_install_target(package_name, install_target)
    if target_version:
        return target_version

    try:
        resolved_version = importlib_metadata.version(package_name)
    except Exception:
        resolved_version = None

    version_text = str(resolved_version or "").strip()
    return version_text or None


def is_package_installed(package_name, install_target=None, allow_cache_fallback=True):
    resolved_version = installed_version(package_name, install_target)
    if resolved_version:
        return True, resolved_version, "metadata"

    if allow_cache_fallback and install_target and has_target_package_marker(package_name, install_target):
        cached_version = load_cached_versions(
            install_target,
            package_names=(package_name,),
        ).get(package_name, "").strip()
        if cached_version:
            return True, cached_version, "cache"

    return False, "", "missing"


def matches_distribution_entry(entry_stem, package_name):
    normalized_stem = canonical_package_name(entry_stem)
    safe_stem = wheel_safe_package_name(entry_stem)
    normalized_name = canonical_package_name(package_name)
    safe_name = wheel_safe_package_name(package_name)
    return (
        normalized_stem == normalized_name
        or safe_stem == safe_name
        or safe_stem.startswith(f"{safe_name}-")
        or re.match(rf"^{re.escape(safe_name)}_[0-9]", safe_stem) is not None
    )


def cleanup_target_package(install_target, package_name):
    if not install_target or not os.path.isdir(install_target):
        return 0

    import_name = str(package_name).replace("-", "_").strip().lower()
    removed = 0

    try:
        for entry in os.listdir(install_target):
            full_path = os.path.join(install_target, entry)
            if not os.path.exists(full_path):
                continue

            lower_entry = entry.lower()
            should_remove = False

            if lower_entry.endswith(".dist-info"):
                stem = lower_entry[:-10]
                if matches_distribution_entry(stem, package_name):
                    removed += cleanup_record_entries(install_target, full_path)
                    should_remove = True
            elif lower_entry in {import_name, f"{import_name}.py"}:
                should_remove = True
            elif lower_entry.endswith(".egg-info"):
                stem = lower_entry[:-9]
                should_remove = matches_distribution_entry(stem, package_name)

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

    for relative_path in package_owned_paths(package_name):
        full_path = os.path.join(install_target, relative_path)
        if not os.path.lexists(full_path):
            continue
        try:
            if os.path.islink(full_path) or not os.path.isdir(full_path):
                os.remove(full_path)
            else:
                shutil.rmtree(full_path)
            removed += 1
            cleanup_empty_parent_dirs(install_target, os.path.dirname(full_path))
        except Exception:
            print(f"[palladium] failed to remove package-owned target entry: {relative_path}")
            traceback.print_exc()

    return removed


def clear_payload_packages(install_target):
    if not install_target:
        raise ValueError("Manual payload install target is unavailable.")

    target_path = os.path.abspath(install_target)
    if target_path in (os.path.abspath(os.sep), os.path.expanduser("~")):
        raise ValueError(f"Refusing to clear unsafe payload target: {install_target}")

    os.makedirs(target_path, exist_ok=True)
    removed = 0
    for entry_name in os.listdir(target_path):
        full_path = os.path.join(target_path, entry_name)
        try:
            if os.path.islink(full_path) or not os.path.isdir(full_path):
                os.remove(full_path)
            else:
                shutil.rmtree(full_path)
            removed += 1
        except FileNotFoundError:
            continue
        except Exception:
            print(f"[palladium] failed to remove payload entry: {entry_name}")
            traceback.print_exc()

    return removed


def safe_relative_path(path, context):
    path_text = str(path or "")
    if not path_text or path_text.startswith(("/", "\\")):
        raise ValueError(f"Unsafe {context} entry: {path_text}")

    normalized_path = os.path.normpath(path_text)
    if (
        normalized_path == "."
        or normalized_path.startswith("..")
        or os.path.isabs(normalized_path)
    ):
        raise ValueError(f"Unsafe {context} entry: {path_text}")

    return normalized_path


def is_safe_child_path(root, relative_path):
    normalized_path = safe_relative_path(relative_path, "payload")
    root_abs = os.path.abspath(root)
    target_path = os.path.abspath(os.path.join(root, normalized_path))
    return target_path == root_abs or target_path.startswith(root_abs + os.sep)


def cleanup_empty_parent_dirs(root, start_dir):
    root_abs = os.path.abspath(root)
    current = os.path.abspath(start_dir)
    while current != root_abs and current.startswith(root_abs + os.sep):
        try:
            os.rmdir(current)
        except OSError:
            return
        current = os.path.dirname(current)


def cleanup_record_entries(install_target, dist_info_path):
    record_path = os.path.join(dist_info_path, "RECORD")
    if not os.path.isfile(record_path):
        return 0

    removed = 0
    try:
        with open(record_path, "r", encoding="utf-8", errors="replace") as record_file:
            lines = list(record_file)
    except Exception:
        return 0

    for line in lines:
        relative_path = line.split(",", 1)[0].strip()
        if not relative_path:
            continue

        try:
            if not is_safe_child_path(install_target, relative_path):
                continue
            target_path = os.path.abspath(os.path.join(install_target, relative_path))
        except ValueError:
            continue

        if target_path == os.path.abspath(dist_info_path):
            continue
        if target_path.startswith(os.path.abspath(dist_info_path) + os.sep):
            continue
        if not os.path.exists(target_path):
            continue

        try:
            if os.path.isdir(target_path):
                shutil.rmtree(target_path)
            else:
                os.remove(target_path)
            removed += 1
            cleanup_empty_parent_dirs(install_target, os.path.dirname(target_path))
        except Exception:
            print(f"[palladium] failed to remove stale wheel record entry: {relative_path}")
            traceback.print_exc()

    return removed


def safe_extract_zip(zip_path, extract_root):
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.infolist():
            normalized_name = safe_relative_path(member.filename, "payload zip")

            target_path = os.path.abspath(os.path.join(extract_root, normalized_name))
            extract_root_abs = os.path.abspath(extract_root)
            if target_path != extract_root_abs and not target_path.startswith(extract_root_abs + os.sep):
                raise ValueError(f"Unsafe payload zip entry: {member.filename}")

        archive.extractall(extract_root)


def preferred_payload_site_packages_names():
    names = []
    configured_name = os.environ.get("PALLADIUM_PAYLOAD_SITE_PACKAGES", "").strip()
    if configured_name:
        names.append(configured_name)

    names.extend([
        "site-packages",
        "site-packages-iphoneos",
        "site-packages-iphonesimulator",
    ])
    return tuple(dict.fromkeys(names))


def detect_bundled_payload_packages(package_dir):
    detected = []
    for package_name in BUNDLED_RUNTIME_PACKAGES:
        if version_from_install_target(package_name, package_dir):
            detected.append(package_name)
    return detected


def candidate_payload_package_dirs(extract_root):
    yielded = set()

    def yield_if_needed(path):
        normalized_path = os.path.abspath(path)
        if normalized_path in yielded or not os.path.isdir(normalized_path):
            return []
        yielded.add(normalized_path)
        return [normalized_path]

    candidates = []
    for directory_name in preferred_payload_site_packages_names():
        candidates.extend(yield_if_needed(os.path.join(extract_root, directory_name)))
        try:
            for child_name in os.listdir(extract_root):
                child_path = os.path.join(extract_root, child_name)
                candidates.extend(yield_if_needed(os.path.join(child_path, directory_name)))
        except Exception:
            pass

    candidates.extend(yield_if_needed(extract_root))
    try:
        for child_name in os.listdir(extract_root):
            child_path = os.path.join(extract_root, child_name)
            candidates.extend(yield_if_needed(child_path))
    except Exception:
        pass

    return candidates


def find_payload_package_dir(extract_root):
    for candidate_dir in candidate_payload_package_dirs(extract_root):
        detected_packages = detect_bundled_payload_packages(candidate_dir)
        if detected_packages:
            return candidate_dir, detected_packages

    raise ValueError(
        "Payload bundle does not contain wheels or a supported bundled runtime package "
        f"({', '.join(BUNDLED_RUNTIME_PACKAGES)})."
    )


def copy_payload_package_contents(source_dir, install_target):
    os.makedirs(install_target, exist_ok=True)
    copied = 0
    for entry_name in os.listdir(source_dir):
        source_path = os.path.join(source_dir, entry_name)
        target_path = os.path.join(install_target, entry_name)
        if os.path.isdir(source_path):
            if os.path.exists(target_path) and not os.path.isdir(target_path):
                os.remove(target_path)
            shutil.copytree(source_path, target_path, dirs_exist_ok=True)
        else:
            if os.path.isdir(target_path):
                shutil.rmtree(target_path)
            shutil.copy2(source_path, target_path)
        copied += 1
    return copied


def wheel_dist_info_dir(member_names):
    candidates = []
    for member_name in member_names:
        normalized_name = safe_relative_path(member_name, "wheel")
        parts = normalized_name.split(os.sep)
        if len(parts) < 2:
            continue
        if parts[0].lower().endswith(".dist-info") and parts[1] == "METADATA":
            candidates.append(parts[0])

    candidates = sorted(set(candidates))
    if len(candidates) != 1:
        raise ValueError("Wheel payload must contain exactly one dist-info METADATA file.")
    return candidates[0]


def wheel_metadata(archive, dist_info_dir):
    metadata_path = f"{dist_info_dir}/METADATA"
    try:
        metadata_text = archive.read(metadata_path).decode("utf-8", errors="replace")
    except KeyError:
        raise ValueError("Wheel payload is missing METADATA.") from None

    metadata = Parser().parsestr(metadata_text)
    package_name = str(metadata.get("Name", "")).strip()
    version = str(metadata.get("Version", "")).strip()
    if not package_name or not version:
        raise ValueError("Wheel payload metadata must include Name and Version.")
    return package_name, version


def wheel_destination_relative_path(member_name, data_dir):
    normalized_name = safe_relative_path(member_name, "wheel")
    parts = normalized_name.split(os.sep)
    if len(parts) >= 3 and parts[0] == data_dir:
        scheme = parts[1]
        if scheme not in ("purelib", "platlib"):
            return None
        return os.path.join(*parts[2:])
    return normalized_name


def stage_wheel_contents(wheel_path, stage_dir):
    if not zipfile.is_zipfile(wheel_path):
        raise ValueError(f"Payload wheel is not a valid ZIP archive: {os.path.basename(wheel_path)}")

    with zipfile.ZipFile(wheel_path) as archive:
        members = archive.infolist()
        member_names = [str(member.filename or "") for member in members]
        dist_info_dir = wheel_dist_info_dir(member_names)
        if f"{dist_info_dir}/WHEEL" not in member_names:
            raise ValueError("Wheel payload is missing WHEEL metadata.")

        package_name, version = wheel_metadata(archive, dist_info_dir)
        data_dir = dist_info_dir[:-10] + ".data"
        copied = 0
        skipped = 0

        for member in members:
            member_name = str(member.filename or "")
            destination_relative_path = wheel_destination_relative_path(member_name, data_dir)
            if member.is_dir() or destination_relative_path in (None, "", "."):
                if destination_relative_path is None:
                    skipped += 1
                continue

            destination_relative_path = safe_relative_path(destination_relative_path, "wheel")
            destination_path = os.path.abspath(os.path.join(stage_dir, destination_relative_path))
            stage_dir_abs = os.path.abspath(stage_dir)
            if destination_path != stage_dir_abs and not destination_path.startswith(stage_dir_abs + os.sep):
                raise ValueError(f"Unsafe wheel entry: {member_name}")

            os.makedirs(os.path.dirname(destination_path), exist_ok=True)
            with archive.open(member) as source_file, open(destination_path, "wb") as destination_file:
                shutil.copyfileobj(source_file, destination_file)
            copied += 1

    return {
        "path": wheel_path,
        "name": package_name,
        "version": version,
        "stage_dir": stage_dir,
        "copied": copied,
        "skipped": skipped,
    }


def find_payload_wheel_files(extract_root):
    wheel_paths = []
    for current_root, _dir_names, file_names in os.walk(extract_root):
        for file_name in file_names:
            if file_name.lower().endswith(".whl"):
                wheel_paths.append(os.path.join(current_root, file_name))
    return sorted(wheel_paths)


def install_payload_wheels(wheel_paths, install_target, temp_root):
    staged_wheels = []
    seen_packages = {}
    stage_root = os.path.join(temp_root, "wheel-staging")
    os.makedirs(stage_root, exist_ok=True)

    for index, wheel_path in enumerate(wheel_paths):
        wheel_stage_dir = os.path.join(stage_root, str(index))
        os.makedirs(wheel_stage_dir, exist_ok=True)
        wheel_info = stage_wheel_contents(wheel_path, wheel_stage_dir)
        normalized_name = canonical_package_name(wheel_info["name"])
        if normalized_name in seen_packages:
            first_path = os.path.basename(seen_packages[normalized_name])
            second_path = os.path.basename(wheel_path)
            raise ValueError(
                "Payload bundle contains duplicate wheels for "
                f"{wheel_info['name']}: {first_path}, {second_path}"
            )
        seen_packages[normalized_name] = wheel_path
        staged_wheels.append(wheel_info)

    removed = 0
    copied = 0
    skipped = 0
    installed_packages = []
    for wheel_info in staged_wheels:
        package_name = wheel_info["name"]
        removed += cleanup_target_package(install_target, package_name)
        copied += copy_payload_package_contents(wheel_info["stage_dir"], install_target)
        skipped += wheel_info["skipped"]
        installed_packages.append(package_name)

    print(f"[palladium] installed payload wheel packages: {', '.join(installed_packages)}")
    print(f"[palladium] removed stale payload package entries: {removed}")
    print(f"[palladium] copied payload wheel entries: {copied}")
    if skipped:
        print(f"[palladium] skipped non-importable wheel data entries: {skipped}")
    return installed_packages


def install_payload_zip(payload_zip_path, install_target):
    payload_path = str(payload_zip_path or "").strip()
    if not payload_path:
        raise ValueError("Payload bundle path is missing.")
    if not os.path.isfile(payload_path):
        raise ValueError(f"Payload bundle not found: {payload_path}")
    if not zipfile.is_zipfile(payload_path):
        raise ValueError("Payload file is not a valid ZIP-compatible archive.")
    if not install_target:
        raise ValueError("Manual payload install target is unavailable.")

    temp_root = tempfile.mkdtemp(prefix="palladium-payload-")
    try:
        if payload_path.lower().endswith(".whl"):
            return install_payload_wheels([payload_path], install_target, temp_root)

        safe_extract_zip(payload_path, temp_root)
        wheel_paths = find_payload_wheel_files(temp_root)
        if wheel_paths:
            return install_payload_wheels(wheel_paths, install_target, temp_root)

        package_dir, detected_packages = find_payload_package_dir(temp_root)

        removed = 0
        for package_name in detected_packages:
            removed += cleanup_target_package(install_target, package_name)
        copied = copy_payload_package_contents(package_dir, install_target)

        print(f"[palladium] installed payload packages: {', '.join(detected_packages)}")
        print(f"[palladium] payload source package directory: {package_dir}")
        print(f"[palladium] removed stale payload package entries: {removed}")
        print(f"[palladium] copied payload package entries: {copied}")
        return detected_packages
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)


def collect_versions(install_target=None, allow_cache_fallback=True, package_source=None):
    package_names = managed_package_names(package_source)
    cached_versions = (
        load_cached_versions(install_target, package_names=package_names)
        if allow_cache_fallback else {}
    )
    versions = {}
    for package_name in package_names:
        resolved_version = installed_version(package_name, install_target)
        if resolved_version:
            versions[package_name] = display_version(package_name, resolved_version)
            continue

        cached_version = cached_versions.get(package_name, "").strip()
        if allow_cache_fallback and cached_version:
            versions[package_name] = cached_version
        else:
            versions[package_name] = "not installed"

    save_cached_versions(versions, install_target, package_names=package_names)
    return versions


def normalized_version_text(value):
    return str(value or "").strip()


def parse_package_source(source_json=None):
    source = {
        "mode": "stable",
        "custom_specs": [],
        "additional_packages": [],
        "locked_versions": dict(MANAGED_PACKAGE_LOCKS),
        "allow_prereleases": False,
        "patch_mode": DEFAULT_YOUTUBE_PATCH_MODE,
    }
    if not source_json:
        return source

    try:
        parsed = json.loads(str(source_json))
    except Exception:
        return source

    if not isinstance(parsed, dict):
        return source

    mode = str(parsed.get("mode", "stable")).strip().lower()
    if mode not in ("stable", "nightly", "custom"):
        mode = "stable"

    specs = []
    raw_specs = parsed.get("custom_specs", [])
    if isinstance(raw_specs, list):
        for item in raw_specs:
            spec = str(item).strip()
            if spec and not spec.startswith("#"):
                specs.append(spec)

    additional_packages = []
    seen_packages = {canonical_package_name(name) for name in TRACKED_PACKAGES}
    raw_additional_packages = parsed.get("additional_packages", [])
    if isinstance(raw_additional_packages, list):
        for item in raw_additional_packages:
            package_name = normalized_additional_package_name(item)
            if not package_name or package_name in seen_packages:
                continue
            seen_packages.add(package_name)
            additional_packages.append(package_name)

    locked_versions = dict(MANAGED_PACKAGE_LOCKS)
    raw_locked_versions = parsed.get("locked_versions", {})
    if isinstance(raw_locked_versions, dict):
        for package_name in managed_package_names({"additional_packages": additional_packages}):
            version_text = normalized_version_text(raw_locked_versions.get(package_name))
            if version_text:
                locked_versions[package_name] = version_text

    patch_mode = normalize_youtube_patch_mode(parsed.get("youtube_patch_mode"))
    if "youtube_patch_mode" not in parsed and parsed.get("disable_webkit_jsi_patch"):
        patch_mode = "off"
    if mode == "custom":
        patch_mode = "off"

    source["mode"] = mode
    source["custom_specs"] = specs
    source["additional_packages"] = additional_packages
    source["locked_versions"] = locked_versions
    source["allow_prereleases"] = mode == "nightly"
    source["patch_mode"] = patch_mode
    return source


def build_pip_install_args(
    package_specs,
    install_target=None,
    allow_prereleases=False,
    upgrade=False,
    force_reinstall=False,
):
    args = ["install"]
    if install_target:
        args.extend(["--target", install_target])
    if upgrade:
        args.append("--upgrade")
    if force_reinstall:
        args.append("--force-reinstall")
    if allow_prereleases:
        args.append("--pre")
    args.extend([
        "--disable-pip-version-check",
        "--no-cache-dir",
        "--progress-bar",
        "off",
        "--no-color",
    ])
    args.extend(list(package_specs or []))
    return args


def latest_index_version(indexed_versions, package_name):
    for candidate in indexed_versions.get(package_name) or []:
        resolved = normalized_version_text(candidate)
        if resolved:
            return resolved
    return ""


def package_target_version(indexed_versions, package_name, package_source=None):
    package_source = package_source or {}
    locked_versions = package_source.get("locked_versions") or {}
    if isinstance(locked_versions, dict):
        locked_version = normalized_version_text(locked_versions.get(package_name))
        if locked_version:
            return locked_version

    return latest_index_version(indexed_versions, package_name)


def build_missing_package_install_specs(package_names, package_source=None):
    package_source = package_source or parse_package_source()
    if package_source.get("mode") == "custom":
        return list(package_source.get("custom_specs") or [])

    specs = []
    for package_name in package_names:
        locked_version = package_target_version({}, package_name, package_source)
        if locked_version:
            specs.append(f"{package_name}=={locked_version}")
        else:
            specs.append(package_name)
    return specs


def missing_installable_runtime_packages(installed_versions, package_source=None):
    missing_packages = []
    for package_name in runtime_package_names(package_source):
        if is_bundled_runtime_package(package_name):
            continue

        current_version = normalized_version_text(installed_versions.get(package_name))
        if not current_version or current_version in ("not installed", "unknown"):
            missing_packages.append(package_name)

    return missing_packages


def missing_runtime_packages_summary(missing_packages):
    packages_text = ", ".join(missing_packages)
    return (
        f"Required packages are not installed: {packages_text}. "
        "Install them by starting a download or tapping Update Packages."
    )


def build_package_update_lines(installed_versions, indexed_versions, include_missing=False, package_source=None):
    package_source = package_source or parse_package_source()
    runtime_packages = set(runtime_package_names(package_source))
    lines = []
    for package_name in managed_package_names(package_source):
        if is_bundled_runtime_package(package_name):
            continue

        current_version = normalized_version_text(installed_versions.get(package_name))
        target_version = package_target_version(indexed_versions, package_name, package_source)
        if not current_version or current_version in ("not installed", "unknown"):
            if include_missing and target_version and package_name in runtime_packages:
                lines.append(f"{package_name}: not installed -> {target_version}")
            continue

        if target_version and target_version != current_version:
            lines.append(f"{package_name}: {current_version} -> {target_version}")
    return lines


def build_package_install_plan(installed_versions, indexed_versions, custom_versions=None, package_source=None):
    custom_versions = custom_versions or {}
    package_source = package_source or parse_package_source()
    packages = []
    cleanup_packages = []
    managed_packages = managed_package_names(package_source)
    runtime_packages = set(runtime_package_names(package_source))

    if package_source.get("mode") == "custom":
        custom_specs = list(package_source.get("custom_specs") or [])
        if custom_specs:
            return custom_specs, list(runtime_package_names(package_source))
        return [], []

    if custom_versions:
        for package_name in managed_packages:
            requested_version = normalized_version_text(custom_versions.get(package_name))
            if not requested_version:
                continue

            if is_bundled_runtime_package(package_name):
                print(f"[palladium] skipping {package_name}; bundled in app")
                continue

            current_version = normalized_version_text(installed_versions.get(package_name))
            if requested_version == current_version:
                print(f"[palladium] skipping {package_name}; already on requested version {requested_version}")
                continue

            packages.append(f"{package_name}=={requested_version}")
            if package_name in runtime_packages:
                cleanup_packages.append(package_name)
        return packages, cleanup_packages

    for package_name in managed_packages:
        if is_bundled_runtime_package(package_name):
            continue

        current_version = normalized_version_text(installed_versions.get(package_name))
        target_version = package_target_version(indexed_versions, package_name, package_source)
        if not current_version or current_version in ("not installed", "unknown"):
            if package_name in runtime_packages:
                if target_version:
                    packages.append(f"{package_name}=={target_version}")
                elif package_name in installed_versions:
                    packages.append(package_name)
                else:
                    continue
                if package_name in runtime_packages:
                    cleanup_packages.append(package_name)
            continue

        if target_version and target_version != current_version:
            packages.append(f"{package_name}=={target_version}")
            if package_name in runtime_packages:
                cleanup_packages.append(package_name)

    return packages, cleanup_packages


def check_package_updates(install_target=None, package_source=None, include_missing=False):
    package_source = package_source or parse_package_source()
    if package_source.get("mode") == "custom":
        if package_source.get("custom_specs"):
            return True, "Custom packages will be installed on update."
        return False, "Add custom package requirements before updating."

    installed_versions = collect_versions(
        install_target=install_target,
        allow_cache_fallback=False,
        package_source=package_source,
    )
    missing_runtime_packages = missing_installable_runtime_packages(installed_versions, package_source)
    installable_runtime_packages = filter_installable_packages(runtime_package_names(package_source))
    if (
        missing_runtime_packages
        and len(missing_runtime_packages) == len(installable_runtime_packages)
        and not include_missing
    ):
        return False, missing_runtime_packages_summary(missing_runtime_packages)

    pip_main = ensure_pip_entrypoint(install_target, install_target_pip=False)
    if pip_main is None:
        return False, "Unable to check updates (pip unavailable)."

    try:
        indexed_versions = fetch_package_index_versions(
            install_target=install_target,
            pip_main=pip_main,
            allow_prereleases=bool(package_source.get("allow_prereleases")),
            package_source=package_source,
        )
        update_lines = build_package_update_lines(
            installed_versions,
            indexed_versions,
            include_missing=include_missing,
            package_source=package_source,
        )
        if update_lines:
            return True, "\n".join(update_lines)
        if missing_runtime_packages and not include_missing:
            return False, missing_runtime_packages_summary(missing_runtime_packages)
        if indexed_versions:
            return False, "All packages are up to date."

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

        tracked = {name.lower() for name in managed_package_names(package_source)}
        locked = {
            name.lower()
            for name, version in (package_source.get("locked_versions") or {}).items()
            if normalized_version_text(version)
        }
        relevant = [
            item for item in items
            if str(item.get("name", "")).lower() in tracked
            and str(item.get("name", "")).lower() not in locked
        ]
        if not relevant:
            return False, "All packages are up to date."

        lines = []
        for item in relevant:
            name = str(item.get("name", "package"))
            package_key = name.lower()
            old_ver = normalized_version_text(item.get("version", "?")) or "?"
            new_ver = normalized_version_text(item.get("latest_version", "?")) or "?"

            installed_ver = normalized_version_text(installed_versions.get(package_key))
            if installed_ver and installed_ver not in ("not installed", "unknown"):
                old_ver = installed_ver

            if old_ver == new_ver:
                continue

            lines.append(f"{name}: {old_ver} -> {new_ver}")

        if not lines:
            return False, "All packages are up to date."

        return True, "\n".join(lines)
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


def fetch_package_index_versions(
    install_target=None,
    pip_main=None,
    allow_prereleases=False,
    package_source=None,
):
    if pip_main is None:
        pip_main = ensure_pip_entrypoint(install_target)
    if pip_main is None:
        return {}

    resolved = {}
    for package_name in managed_package_names(package_source):
        if is_bundled_runtime_package(package_name):
            print(f"[palladium] skipping index versions for bundled {package_name}")
            continue

        try:
            capture = io.StringIO()
            pip_args = [
                "index",
                "versions",
                "--disable-pip-version-check",
                "--no-color",
                package_name,
            ]
            if allow_prereleases:
                pip_args.insert(-1, "--pre")
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
