import os
import sys
import zipimport

from .runtime import invalidate_runtime_package_modules

PLUGINS_DIR_ENV = "PALLADIUM_PLUGINS_DIR"
PLUGIN_PACKAGE_NAME = "yt_dlp_plugins"

_loaded_plugin_signature = None


def plugin_directory():
    path = os.environ.get(PLUGINS_DIR_ENV, "").strip()
    if path and os.path.isdir(path):
        return os.path.abspath(path)
    return None


def plugin_dir_args():
    directory = plugin_directory()
    return ("--plugin-dirs", directory) if directory else ()


def plugin_dirs_value():
    directory = plugin_directory()
    return ["default", directory] if directory else ["default"]


def plugin_directory_signature(directory):
    if not directory:
        return ()

    entries = []
    for root, dir_names, file_names in os.walk(directory):
        dir_names[:] = sorted(name for name in dir_names if not name.startswith("."))
        for file_name in sorted(file_names):
            if file_name.startswith("."):
                continue
            path = os.path.join(root, file_name)
            try:
                stat = os.stat(path)
            except OSError:
                continue
            entries.append((os.path.relpath(path, directory), stat.st_size, stat.st_mtime_ns))
    return tuple(entries)


def plugin_namespace_packages():
    packages = {PLUGIN_PACKAGE_NAME}
    for finder in sys.meta_path:
        if type(finder).__name__ == "PluginFinder":
            packages.update(getattr(finder, "packages", ()))
    return packages


def clear_plugin_import_caches(directory):
    """Drop cached plugin imports so yt-dlp sees added, replaced, or removed plugins."""
    # Only the namespace packages cache plugin search paths. Plugin modules stay loaded
    # because yt-dlp re-executes them on each load, and some keep native state.
    for name in plugin_namespace_packages():
        sys.modules.pop(name, None)

    if directory:
        prefix = os.path.join(directory, "")
        for cache in (sys.path_importer_cache, zipimport._zip_directory_cache):
            for key in [key for key in cache if str(key).startswith(prefix)]:
                cache.pop(key, None)

    plugins_module = sys.modules.get("yt_dlp.plugins")
    dirs_in_zip = getattr(plugins_module, "dirs_in_zip", None)
    if dirs_in_zip is not None and hasattr(dirs_in_zip, "cache_clear"):
        dirs_in_zip.cache_clear()


def prepare_plugin_imports():
    """Reset plugin import state before a yt-dlp run and reload yt-dlp when plugins changed."""
    global _loaded_plugin_signature

    directory = plugin_directory()
    signature = plugin_directory_signature(directory)
    if _loaded_plugin_signature is not None and signature != _loaded_plugin_signature:
        print("[palladium] yt-dlp plugins changed, reloading yt-dlp")
        invalidate_runtime_package_modules()

    clear_plugin_import_caches(directory)
    _loaded_plugin_signature = signature
    return directory


def import_yt_dlp_with_plugins():
    """Import yt-dlp for API use with the Palladium plugin folder enabled."""
    prepare_plugin_imports()

    import yt_dlp
    from yt_dlp import globals as yt_dlp_globals

    if hasattr(yt_dlp_globals, "plugin_dirs"):
        yt_dlp_globals.plugin_dirs.value = plugin_dirs_value()
    if hasattr(yt_dlp_globals, "all_plugins_loaded"):
        yt_dlp_globals.all_plugins_loaded.value = False
    return yt_dlp
