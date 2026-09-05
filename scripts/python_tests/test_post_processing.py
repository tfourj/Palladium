import json
import unittest

from scripts.python_tests import helpers  # noqa: F401
from palladium_ytdlp.args import apply_post_processing_args


class PostProcessingTests(unittest.TestCase):
    def configuration(self, method="recode", target="mp4"):
        return json.dumps({"enabled": True, "method": method, "format": target})

    def test_disabled_preserves_existing_arguments(self):
        preset = ["--remux-video", "mp4"]
        extra = ["--recode-video", "avi"]
        for configuration in (None, "{}", '{"enabled": false}'):
            self.assertEqual(apply_post_processing_args(preset, extra, configuration), (preset, extra))

    def test_enabled_overrides_separate_and_inline_conversion_options(self):
        preset, extra = apply_post_processing_args(
            ["-f", "137+140", "--remux-video=mov", "--merge-output-format", "mp4"],
            ["--recode-video", "avi", "--remux-video", "mkv", "--no-mtime"],
            self.configuration("remux", "webm"),
        )
        self.assertEqual(preset, ["-f", "137+140"])
        self.assertEqual(extra, ["--no-mtime", "--merge-output-format", "mkv", "--remux-video", "webm"])

    def test_audio_extraction_preserves_existing_arguments(self):
        for flag in ("-x", "--extract-audio"):
            for preset, extra in (([flag], []), ([], [flag])):
                self.assertEqual(
                    apply_post_processing_args(preset, extra, self.configuration()), (preset, extra)
                )

    def test_unsupported_configuration_is_rejected(self):
        for method, target in (("unknown", "mp4"), ("recode", "webm"), ("remux", "invalid")):
            with self.subTest(method=method, target=target), self.assertRaises(ValueError):
                apply_post_processing_args([], [], self.configuration(method, target))


if __name__ == "__main__":
    unittest.main()
