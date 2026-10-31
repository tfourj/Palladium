import json
import unittest
from unittest import mock

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.packages import (  # noqa: E402
    build_pip_install_args,
    fetch_package_index_versions,
    parse_package_source,
    pip_index_args,
)


class PackageIndexTests(unittest.TestCase):
    def test_default_source_uses_pip_default_index(self):
        source = parse_package_source(json.dumps({"mode": "stable"}))

        self.assertEqual(source["index_url"], "")
        self.assertNotIn("--index-url", build_pip_install_args(["yt-dlp"], index_url=source["index_url"]))

    def test_source_keeps_https_index_url(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "index_url": " https://pypi.tuna.tsinghua.edu.cn/simple ",
        }))

        self.assertEqual(source["index_url"], "https://pypi.tuna.tsinghua.edu.cn/simple")

    def test_source_drops_invalid_index_url(self):
        for value in ("ftp://example.com/simple", "example.com/simple", "https://", 42):
            with self.subTest(value=value):
                source = parse_package_source(json.dumps({"mode": "stable", "index_url": value}))
                self.assertEqual(source["index_url"], "")

    def test_install_args_put_index_url_before_specs(self):
        args = build_pip_install_args(["yt-dlp==1.0"], index_url="https://mirrors.aliyun.com/pypi/simple/")

        self.assertEqual(args[-3:], ["--index-url", "https://mirrors.aliyun.com/pypi/simple/", "yt-dlp==1.0"])

    def test_http_index_url_is_trusted_host(self):
        self.assertEqual(
            pip_index_args("http://mirror.local:8080/simple"),
            ["--index-url", "http://mirror.local:8080/simple", "--trusted-host", "mirror.local"],
        )

    def test_index_versions_use_index_url(self):
        source = parse_package_source(json.dumps({
            "mode": "stable",
            "index_url": "https://mirrors.aliyun.com/pypi/simple/",
        }))
        pip_main = mock.Mock(return_value=0)

        with mock.patch("palladium_ytdlp.packages.is_bundled_runtime_package", return_value=False):
            fetch_package_index_versions(pip_main=pip_main, package_source=source)

        self.assertTrue(pip_main.call_args_list)
        for call in pip_main.call_args_list:
            pip_args = call.args[0]
            self.assertIn("--index-url", pip_args)
            self.assertEqual(pip_args[pip_args.index("--index-url") + 1], "https://mirrors.aliyun.com/pypi/simple/")


if __name__ == "__main__":
    unittest.main()
