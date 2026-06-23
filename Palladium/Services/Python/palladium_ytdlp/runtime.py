import importlib
import io
import logging
import runpy
import sys

from .ffmpeg_bridge import is_cancel_requested
from .shared import Tee


class GalleryDLOutputCapture(io.StringIO):
    """String output capture compatible with gallery-dl's stream setup."""

    def reconfigure(self, **_options):
        return None


def reset_gallery_dl_runtime():
    """Discard gallery-dl state and log handlers from a previous in-process run."""
    loggers = [logging.getLogger()]
    loggers.extend(
        logger
        for logger in logging.Logger.manager.loggerDict.values()
        if isinstance(logger, logging.Logger)
    )
    for logger in loggers:
        for handler in list(logger.handlers):
            if not isinstance(getattr(handler, "stream", None), (Tee, GalleryDLOutputCapture)):
                continue
            logger.removeHandler(handler)
            handler.close()

    for module_name in list(sys.modules):
        if module_name == "gallery_dl" or module_name.startswith("gallery_dl."):
            del sys.modules[module_name]


def run_gallery_dl_module():
    reset_gallery_dl_runtime()
    try:
        runpy.run_module("gallery_dl", run_name="__main__", alter_sys=True)
    finally:
        reset_gallery_dl_runtime()


def invalidate_runtime_package_modules():
    prefixes = ("yt_dlp", "yt_dlp_plugins")
    webkit_jsi_loaded = any(
        name == "yt_dlp_plugins.webkit_jsi" or name.startswith("yt_dlp_plugins.webkit_jsi.")
        for name in sys.modules
    )
    if webkit_jsi_loaded:
        print("[palladium] restart required to refresh loaded webkit jsi runtime")
        return True

    stale_modules = [
        name
        for name in sys.modules
        if any(name == prefix or name.startswith(f"{prefix}.") for prefix in prefixes)
    ]

    for name in stale_modules:
        sys.modules.pop(name, None)

    importlib.invalidate_caches()
    print(f"[palladium] invalidated {len(stale_modules)} cached yt-dlp runtime module(s)")
    return False


def raise_if_cancel_requested(cancel_file_path, message):
    if is_cancel_requested(cancel_file_path):
        print(message)
        raise KeyboardInterrupt("cancel requested")
