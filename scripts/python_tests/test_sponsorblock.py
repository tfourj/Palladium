import unittest

from scripts.python_tests import helpers  # noqa: F401
from palladium_ytdlp.args import build_sponsorblock_args


class SponsorBlockArgsTests(unittest.TestCase):
    def test_disabled_adds_nothing(self):
        self.assertEqual(build_sponsorblock_args(False, "auto_video", [], []), [])

    def test_video_presets_remove_sponsor_segments(self):
        for preset in ("auto_video", "mute", "custom"):
            with self.subTest(preset=preset):
                self.assertEqual(
                    build_sponsorblock_args(True, preset, ["--remux-video", "mp4"], []),
                    ["--sponsorblock-remove", "sponsor"],
                )

    def test_audio_and_image_presets_are_skipped(self):
        for preset in ("audio", "images"):
            with self.subTest(preset=preset):
                self.assertEqual(build_sponsorblock_args(True, preset, [], []), [])

    def test_audio_extraction_is_skipped(self):
        self.assertEqual(build_sponsorblock_args(True, "custom", ["-x"], []), [])
        self.assertEqual(build_sponsorblock_args(True, "auto_video", [], ["--extract-audio"]), [])

    def test_user_sponsorblock_options_take_precedence(self):
        for extra in (
            ["--sponsorblock-remove", "all"],
            ["--sponsorblock-mark=intro"],
            ["--no-sponsorblock"],
        ):
            with self.subTest(extra=extra):
                self.assertEqual(build_sponsorblock_args(True, "auto_video", [], extra), [])


if __name__ == "__main__":
    unittest.main()
