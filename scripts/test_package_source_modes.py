import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_tests(loader, tests, pattern):
    return loader.discover(str(ROOT / "scripts" / "python_tests"), top_level_dir=str(ROOT))


if __name__ == "__main__":
    unittest.main()
