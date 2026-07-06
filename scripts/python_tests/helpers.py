import contextlib
import os
import pathlib
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
PYTHON_SERVICE_PATH = ROOT / "Palladium" / "Services" / "Python"

if str(PYTHON_SERVICE_PATH) not in sys.path:
    sys.path.insert(0, str(PYTHON_SERVICE_PATH))


def write_curl_cffi_package(root, version):
    root = pathlib.Path(root)
    (root / "curl_cffi").mkdir(parents=True, exist_ok=True)
    dist_info = root / f"curl_cffi-{version}.dist-info"
    dist_info.mkdir()
    (dist_info / "METADATA").write_text(
        f"Metadata-Version: 2.1\nName: curl-cffi\nVersion: {version}\n",
        encoding="utf-8",
    )


def write_wheel_package(path, name, version, modules=None, extra_files=None):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    safe_name = str(name).replace("-", "_").replace(".", "_")
    dist_info = f"{safe_name}-{version}.dist-info"
    wheel_entries = {}

    if modules is None:
        modules = [safe_name]
    for module_name in modules:
        module_path = str(module_name).replace(".", "/")
        wheel_entries[f"{module_path}/__init__.py"] = ""

    wheel_entries[f"{dist_info}/METADATA"] = (
        f"Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n"
    )
    wheel_entries[f"{dist_info}/WHEEL"] = "Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
    if extra_files:
        wheel_entries.update(extra_files)

    record_rows = [f"{entry_name},,\n" for entry_name in sorted(wheel_entries)]
    wheel_entries[f"{dist_info}/RECORD"] = "".join(record_rows)

    with zipfile.ZipFile(path, "w") as archive:
        for entry_name, contents in wheel_entries.items():
            archive.writestr(entry_name, contents)


def zip_directory(source_dir, zip_path):
    source_dir = pathlib.Path(source_dir)
    with zipfile.ZipFile(zip_path, "w") as archive:
        for path in source_dir.rglob("*"):
            archive.write(path, path.relative_to(source_dir))


@contextlib.contextmanager
def bundled_curl_cffi(version):
    with tempfile.TemporaryDirectory() as temp:
        write_curl_cffi_package(temp, version)
        yield temp


@contextlib.contextmanager
def temporary_env(**values):
    previous = {name: os.environ.get(name) for name in values}
    try:
        for name, value in values.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = str(value)
        yield
    finally:
        for name, value in previous.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
