import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.gallery import gallery_item_media_type  # noqa: E402


class GalleryMediaTests(unittest.TestCase):
    def test_gallery_audio_urls_with_tiktok_hints_are_classified_as_audio(self):
        self.assertEqual(
            gallery_item_media_type("https://sf16-ies-music-va.tiktokcdn.com/obj/tos-useast2a-v-2774/music-file"),
            "audio",
        )
        self.assertEqual(
            gallery_item_media_type("https://example.com/media?id=1&mime_type=audio_mpeg"),
            "audio",
        )

    def test_gallery_unknown_urls_without_media_hints_are_classified_as_file(self):
        self.assertEqual(gallery_item_media_type("https://example.com/download/opaque-token"), "file")
