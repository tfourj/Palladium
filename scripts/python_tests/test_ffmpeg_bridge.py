import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.ffmpeg_bridge import audio_codec_from_metadata  # noqa: E402


class FFmpegBridgeTests(unittest.TestCase):
    def test_audio_codec_uses_audio_stream(self):
        metadata = {
            "streams": [
                {"codec_type": "video", "codec_name": "h264"},
                {"codec_type": "audio", "codec_name": "aac"},
            ],
        }

        self.assertEqual(audio_codec_from_metadata(metadata), "aac")

    def test_audio_codec_returns_none_without_audio_stream(self):
        self.assertIsNone(audio_codec_from_metadata({"streams": [{"codec_type": "video"}]}))
        self.assertIsNone(audio_codec_from_metadata(None))
