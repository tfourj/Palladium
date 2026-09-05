import json
import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.gallery import (  # noqa: E402
    gallery_item_media_type,
    gallery_item_thumbnail_url,
    gallery_items_from_resolver_output,
    gallery_items_from_url_records,
)


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

    def test_thumbnail_metadata_variants(self):
        url = "https://example.com/preview.jpg?token=123"
        for metadata in (
            {"thumbnail": url},
            {"thumbnail": {"url": url}},
            {"thumbnail_url": url},
            {"display_url": url},
            {"preview_url": f"  {url}  "},
        ):
            with self.subTest(metadata=metadata):
                self.assertEqual(gallery_item_thumbnail_url(metadata), url)

    def test_invalid_thumbnail_metadata_falls_back_to_next_field(self):
        url = "https://example.com/preview.jpg"
        for value in (None, 42, [], {}, "", "file:///tmp/preview.jpg", "/preview.jpg", "https:///", "http://["):
            with self.subTest(value=value):
                self.assertEqual(gallery_item_thumbnail_url({"thumbnail": value, "display_url": url}), url)
                self.assertIsNone(gallery_item_thumbnail_url({"thumbnail": value}))
        self.assertIsNone(gallery_item_thumbnail_url(None))

    def test_resolver_paths_preserve_video_previews_without_changing_selection(self):
        records = [
            ("https://example.com/video.mp4", {"display_url": "https://example.com/preview.jpg"}),
            ("https://example.com/image.jpg", {"thumbnail": "https://example.com/image-small.jpg"}),
            ("https://example.com/audio.mp3", {"display_url": "https://example.com/cover.jpg"}),
            ("https://example.com/second.mp4", {}),
        ]
        # Duplicate media must not create another selectable download.
        duplicated = records + [records[0]]
        entries = [[3, url, metadata] for url, metadata in duplicated]
        results = (
            gallery_items_from_url_records(duplicated),
            gallery_items_from_resolver_output(json.dumps(entries)),
            gallery_items_from_resolver_output("\n".join(json.dumps(entry) for entry in entries)),
        )
        for items in results:
            self.assertEqual([item["index"] for item in items], [1, 2, 3, 4])
            self.assertEqual([item["url"] for item in items], [url for url, _ in records])
            self.assertEqual([item["media_type"] for item in items], ["video", "image", "audio", "video"])
            self.assertEqual(
                [item["thumbnail_url"] for item in items],
                ["https://example.com/preview.jpg", None, None, None],
            )
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[0], results[2])

    def test_plain_url_resolution_keeps_video_without_thumbnail(self):
        items = gallery_items_from_resolver_output("https://example.com/video.mp4")
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["media_type"], "video")
        self.assertIsNone(items[0]["thumbnail_url"])
