import gc
import importlib
import io
import logging
import os
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
    cache_module = sys.modules.get("gallery_dl.cache")
    database = getattr(cache_module, "DATABASE", None) if cache_module is not None else None
    if database is not None:
        try:
            database.close()
            print("[palladium] closed gallery-dl cache database")
        except Exception:
            print("[palladium] failed to close gallery-dl cache database")
        finally:
            cache_module.DATABASE = None

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

    # gallery-dl is run repeatedly inside one embedded interpreter. Ensure
    # cursors, HTTP sessions, and module globals from the completed job are
    # finalized before a later resolver/download opens the same SQLite cache.
    gc.collect()


def run_gallery_dl_module(progress_callback=None):
    reset_gallery_dl_runtime()
    original_handle_url = None
    try:
        if progress_callback is not None:
            from gallery_dl import job

            original_handle_url = job.DownloadJob.handle_url

            def handle_url_with_progress(download_job, url, kwdict):
                try:
                    progress_callback("started", url, kwdict, None)
                except Exception:
                    pass
                original_handle_url(download_job, url, kwdict)
                path = getattr(getattr(download_job, "pathfmt", None), "path", None)
                try:
                    completed = bool(path and os.path.isfile(path) and os.path.getsize(path) > 0)
                except Exception:
                    completed = False
                try:
                    progress_callback("completed" if completed else "failed", url, kwdict, path)
                except Exception:
                    pass

            job.DownloadJob.handle_url = handle_url_with_progress
        runpy.run_module("gallery_dl", run_name="__main__", alter_sys=True)
    finally:
        if original_handle_url is not None:
            job.DownloadJob.handle_url = original_handle_url
        reset_gallery_dl_runtime()


def invalidate_runtime_package_modules():
    prefixes = ("yt_dlp", "yt_dlp_plugins")
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
