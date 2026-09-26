import unittest

from scripts.python_tests import helpers  # noqa: F401
from palladium_ytdlp.args import build_output_args


class OutputTemplateTests(unittest.TestCase):
    def test_default_uses_byte_limited_title_and_playlist_number(self):
        self.assertEqual(
            build_output_args("default", "", False, [], []),
            ["-o", "%(title).200B.%(ext)s"],
        )
        self.assertEqual(
            build_output_args("default", "", True, [], []),
            ["-o", "%(playlist_index)03d - %(title).200B.%(ext)s"],
        )

    def test_video_id_and_custom_templates(self):
        self.assertEqual(
            build_output_args("video_id", "", True, [], []),
            ["-o", "%(id)s.%(ext)s"],
        )
        template = "%(uploader)s/%(title)s.%(ext)s"
        self.assertEqual(build_output_args("custom", template, False, [], []), ["-o", template])

    def test_empty_custom_and_unknown_preset_use_default(self):
        for preset, template in (("custom", "  \n"), ("unknown", "ignored")):
            with self.subTest(preset=preset):
                self.assertEqual(
                    build_output_args(preset, template, False, [], []),
                    ["-o", "%(title).200B.%(ext)s"],
                )

    def test_existing_output_argument_takes_priority(self):
        for preset_args, extra_args in (
            (["-o", "%(title)s.%(ext)s"], []),
            (["-o%(title)s.%(ext)s"], []),
            ([], ["--output", "%(id)s.%(ext)s"]),
            ([], ["--output=%(id)s.%(ext)s"]),
        ):
            with self.subTest(preset_args=preset_args, extra_args=extra_args):
                self.assertEqual(
                    build_output_args("video_id", "", False, preset_args, extra_args),
                    [],
                )


if __name__ == "__main__":
    unittest.main()
