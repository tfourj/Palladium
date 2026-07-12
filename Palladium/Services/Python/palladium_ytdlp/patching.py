import os
import sys
import traceback

from .shared import EJS_MODULE_RELATIVE_PATH
from .webkit_jsi import (
    ensure_safe_webkit_jsi_runtime,
    is_webkit_jsi_patch_applied,
    iter_webkit_jsi_api_paths,
)

YOUTUBE_PATCH_MODES = ("webkit", "ejs", "off")
DEFAULT_YOUTUBE_PATCH_MODE = "webkit"

# Injected into yt-dlp's EJS provider module. The EJS globals shim assigns
# `globalThis.location`; inside a WKWebView page that assignment triggers a
# real navigation to youtube.com, which iOS hands off to the YouTube app.
# The guard diverts the write when a real `location` already exists, while
# non-browser runtimes keep the original behavior.
EJS_GUARD_HELPER = r'''def _palladium_guard_location_assignment(code):
    """Palladium: divert location writes when a real browser location exists."""
    import re
    return re.sub(
        r'globalThis\.location\s*=(?![=])',
        'globalThis[typeof location === "undefined" ? "location" : "__palladium_location"] =',
        str(code))


'''

EJS_CLASS_ANCHOR = "class EJSBaseJCP(JsChallengeProvider):"
EJS_GUARDED_SCRIPT_REFS = ("self._lib_script.code", "self._core_script.code")


def iter_ejs_module_paths(install_target=None):
    seen = set()

    def add(path):
        candidate = os.path.abspath(str(path))
        if candidate in seen or not os.path.isfile(candidate):
            return
        seen.add(candidate)
        yield candidate

    if install_target:
        yield from add(os.path.join(install_target, EJS_MODULE_RELATIVE_PATH))

    for root in sys.path:
        if not root:
            continue
        yield from add(os.path.join(str(root), EJS_MODULE_RELATIVE_PATH))


def patch_ejs_module_source(source_text):
    updated = str(source_text)
    changed = False

    if "def _palladium_guard_location_assignment(" not in updated and EJS_CLASS_ANCHOR in updated:
        updated = updated.replace(EJS_CLASS_ANCHOR, EJS_GUARD_HELPER + EJS_CLASS_ANCHOR, 1)
        changed = True

    for script_ref in EJS_GUARDED_SCRIPT_REFS:
        plain = "{" + script_ref + "}"
        guarded = "{_palladium_guard_location_assignment(" + script_ref + ")}"
        if guarded not in updated and plain in updated:
            updated = updated.replace(plain, guarded, 1)
            changed = True

    is_safe = "def _palladium_guard_location_assignment(" in updated and all(
        "{_palladium_guard_location_assignment(" + script_ref + ")}" in updated
        for script_ref in EJS_GUARDED_SCRIPT_REFS
    )
    return updated, changed, is_safe


def ensure_safe_ejs_runtime(install_target=None):
    patched_count = 0
    found_any = False

    for path in iter_ejs_module_paths(install_target):
        found_any = True
        try:
            with open(path, "r", encoding="utf-8") as handle:
                source = handle.read()
        except Exception:
            print(f"[palladium] failed to read ejs module: {path}")
            traceback.print_exc()
            continue

        updated, changed, is_safe = patch_ejs_module_source(source)
        if not is_safe:
            print(f"[palladium] ejs module still unsafe after patch attempt: {path}")
            continue
        if not changed:
            print(f"[palladium] ejs module already safe: {path}")
            patched_count += 1
            continue

        temp_path = path + ".tmp"
        try:
            with open(temp_path, "w", encoding="utf-8") as handle:
                handle.write(updated)
            os.replace(temp_path, path)
            patched_count += 1
            print(f"[palladium] patched ejs module: {path}")
        except Exception:
            print(f"[palladium] failed to patch ejs module: {path}")
            traceback.print_exc()
            try:
                if os.path.exists(temp_path):
                    os.remove(temp_path)
            except Exception:
                pass

    if not found_any:
        print("[palladium] ejs module not found")

    return patched_count > 0


def is_ejs_patch_applied(source_text):
    return "def _palladium_guard_location_assignment(" in str(source_text)


def applied_youtube_patch_modes(install_target=None):
    modes = set()
    inspectors = (
        ("webkit", iter_webkit_jsi_api_paths(install_target), is_webkit_jsi_patch_applied),
        ("ejs", iter_ejs_module_paths(install_target), is_ejs_patch_applied),
    )
    for mode, paths, inspector in inspectors:
        for path in paths:
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    if inspector(handle.read()):
                        modes.add(mode)
                        break
            except Exception:
                print(f"[palladium] failed to inspect {mode} patch state: {path}")
                traceback.print_exc()
    return modes


def youtube_patch_state_warning(install_target=None, patch_mode=None):
    mode = normalize_youtube_patch_mode(patch_mode)
    applied_modes = applied_youtube_patch_modes(install_target)
    expected_modes = set() if mode == "off" else {mode}
    unexpected_modes = applied_modes - expected_modes
    expected_runtime_found = False
    if mode == "webkit":
        expected_runtime_found = any(iter_webkit_jsi_api_paths(install_target))
    elif mode == "ejs":
        expected_runtime_found = any(iter_ejs_module_paths(install_target))
    expected_patch_missing = bool(expected_modes - applied_modes) and expected_runtime_found

    if not unexpected_modes and not expected_patch_missing:
        print(f"[palladium] youtube patch state verified: {mode}")
        return False

    applied_text = ", ".join(sorted(applied_modes)) or "none"
    expected_text = ", ".join(sorted(expected_modes)) or "none"
    print(
        "[palladium] warning: installed youtube patch state does not match configuration "
        f"(expected={expected_text}, applied={applied_text})"
    )
    return True


def normalize_youtube_patch_mode(value):
    mode = str(value or "").strip().lower()
    if mode in YOUTUBE_PATCH_MODES:
        return mode
    return DEFAULT_YOUTUBE_PATCH_MODE


def apply_youtube_patches(install_target=None, patch_mode=None):
    mode = normalize_youtube_patch_mode(patch_mode)
    if mode == "off":
        print("[palladium] skipping youtube patches by configuration")
        return False

    print(f"[palladium] applying youtube patches: {mode}")
    if mode == "ejs":
        return ensure_safe_ejs_runtime(install_target)
    return ensure_safe_webkit_jsi_runtime(install_target)
