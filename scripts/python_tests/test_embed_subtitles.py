import unittest

from scripts.python_tests import helpers  # noqa: F401
from palladium_ytdlp.args import build_embed_subtitle_args, strip_checkbox_owned_download_args


class EmbedSubtitleArgsTests(unittest.TestCase):
    def test_disabled_adds_nothing(self):
        self.assertEqual(build_embed_subtitle_args(False, "auto_video", [], []), [])

    def test_video_presets_embed_and_drop_sidecars(self):
        for preset in ("auto_video", "mute", "custom"):
            with self.subTest(preset=preset):
                self.assertEqual(
                    build_embed_subtitle_args(True, preset, ["--remux-video", "mp4"], []),
                    ["--embed-subs", "--compat-options", "no-keep-subs"],
                )

    def test_audio_and_image_presets_are_skipped(self):
        for preset in ("audio", "images"):
            with self.subTest(preset=preset):
                self.assertEqual(build_embed_subtitle_args(True, preset, [], []), [])

    def test_audio_extraction_is_skipped(self):
        self.assertEqual(build_embed_subtitle_args(True, "custom", ["-x"], []), [])
        self.assertEqual(build_embed_subtitle_args(True, "auto_video", [], ["--extract-audio"]), [])

    def test_user_embed_flag_is_owned_by_the_checkbox(self):
        self.assertEqual(strip_checkbox_owned_download_args(["--embed-subs", "-f", "best"]), ["-f", "best"])


if __name__ == "__main__":
    unittest.main()
