import contextlib
import io
import json
import os
import re
import shutil
import sys
import traceback
import importlib.metadata as importlib_metadata

from .shared import (
    CLEANUP_PACKAGES,
    DISPLAY_PACKAGES,
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


def ensure_pip_entrypoint(install_target=None):
    pip_main = None
    try:
        from pip._internal.cli.main import main as pip_main
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


def wheel_safe_package_name(name):
    return re.sub(r"[-_.]+", "_", str(name or "").strip().lower())


def package_marker_paths(package_name):
    normalized_name = canonical_package_name(package_name)
    import_name = str(package_name or "").replace("-", "_").strip().lower()
    candidates = [import_name, f"{import_name}.py"]
    if normalized_name == "yt-dlp-apple-webkit-jsi":
        candidates.append(WEBKIT_JSI_API_PACKAGE_RELATIVE_PATH)
    return tuple(candidates)


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


def installed_version(package_name, install_target=None):
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
        cached_version = load_cached_versions(install_target).get(package_name, "").strip()
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

            if lower_entry in {import_name, f"{import_name}.py"}:
                should_remove = True
            elif lower_entry.endswith(".dist-info"):
                stem = lower_entry[:-10]
                should_remove = matches_distribution_entry(stem, package_name)
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

    return removed


def collect_versions(install_target=None, allow_cache_fallback=True):
    cached_versions = load_cached_versions(install_target) if allow_cache_fallback else {}
    versions = {}
    for package_name in DISPLAY_PACKAGES:
        resolved_version = installed_version(package_name, install_target)
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


def normalized_version_text(value):
    return str(value or "").strip()


def latest_index_version(indexed_versions, package_name):
    for candidate in indexed_versions.get(package_name) or []:
        resolved = normalized_version_text(candidate)
        if resolved:
            return resolved
    return ""


def build_package_update_lines(installed_versions, indexed_versions):
    lines = []
    for package_name in TRACKED_PACKAGES:
        current_version = normalized_version_text(installed_versions.get(package_name))
        if not current_version or current_version in ("not installed", "unknown"):
            continue

        latest_version = latest_index_version(indexed_versions, package_name)
        if latest_version and latest_version != current_version:
            lines.append(f"{package_name}: {current_version} -> {latest_version}")
    return lines


def build_package_install_plan(installed_versions, indexed_versions, custom_versions=None):
    custom_versions = custom_versions or {}
    packages = []
    cleanup_packages = []

    if custom_versions:
        for package_name in TRACKED_PACKAGES:
            requested_version = normalized_version_text(custom_versions.get(package_name))
            if not requested_version:
                continue

            current_version = normalized_version_text(installed_versions.get(package_name))
            if requested_version == current_version:
                print(f"[palladium] skipping {package_name}; already on requested version {requested_version}")
                continue

            packages.append(f"{package_name}=={requested_version}")
            if package_name in CLEANUP_PACKAGES:
                cleanup_packages.append(package_name)
        return packages, cleanup_packages

    for package_name in TRACKED_PACKAGES:
        current_version = normalized_version_text(installed_versions.get(package_name))
        if not current_version or current_version in ("not installed", "unknown"):
            continue

        latest_version = latest_index_version(indexed_versions, package_name)
        if latest_version and latest_version != current_version:
            packages.append(package_name)

    return packages, cleanup_packages


def check_package_updates(install_target=None):
    pip_main = ensure_pip_entrypoint(install_target)
    if pip_main is None:
        return False, "Unable to check updates (pip unavailable)."

    try:
        installed_versions = collect_versions(install_target=install_target, allow_cache_fallback=False)
        indexed_versions = fetch_package_index_versions(install_target=install_target, pip_main=pip_main)
        update_lines = build_package_update_lines(installed_versions, indexed_versions)
        if update_lines:
            return True, "\\n".join(update_lines)
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

        tracked = {name.lower() for name in TRACKED_PACKAGES}
        relevant = [item for item in items if str(item.get("name", "")).lower() in tracked]
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
