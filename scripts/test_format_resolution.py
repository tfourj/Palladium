import json
import unittest
from unittest import mock

import yt_dlp

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.ytdlp import list_yt_dlp_formats, resolve_picker_formats  # noqa: E402


class FormatResolutionTests(unittest.TestCase):
    def setUp(self):
        self.downloader = self.enterContext(yt_dlp.YoutubeDL({
            "quiet": True,
            "no_warnings": True,
            "check_formats": False,
            "cachedir": False,
        }))
        self.enterContext(mock.patch.object(
            self.downloader, "urlopen", side_effect=AssertionError("Resolution must not fetch media")
        ))

    def format(self, format_id, ext, vcodec="none", acodec="none", size=1000):
        return {
            "format_id": format_id,
            "ext": ext,
            "vcodec": vcodec,
            "acodec": acodec,
            "filesize": size,
            "url": f"https://example.com/{format_id}",
            "format_note": format_id,
        }

    def resolve(self, formats):
        return resolve_picker_formats(self.downloader, {"formats": formats})

    def test_photos_video_prefers_m4a_even_when_opus_is_ranked_higher(self):
        formats = [
            self.format("140", "m4a", acodec="mp4a.40.2"),
            self.format("251", "webm", acodec="opus"),
            self.format("137", "mp4", vcodec="avc1.640028"),
        ]

        selected = self.resolve(formats)[-1]

        self.assertEqual(selected["format_id"], "137+140")
        self.assertEqual(selected["ext"], "mp4")
        self.assertEqual(selected["acodec"], "mp4a.40.2")
        self.assertEqual(selected["filesize_approx"], 2000)

    def test_missing_m4a_resolves_opus_and_mkv(self):
        selected = self.resolve([
            self.format("251", "webm", acodec="opus"),
            self.format("137", "mp4", vcodec="avc1.640028"),
        ])[-1]

        self.assertEqual(selected["format_id"], "137+251")
        self.assertEqual(selected["ext"], "mkv")
        self.assertEqual(selected["acodec"], "opus")

    def test_vp9_container_depends_on_selected_audio(self):
        for audio_ext, audio_codec, output_ext in [
            ("webm", "opus", "webm"),
            ("m4a", "mp4a.40.2", "mp4"),
        ]:
            with self.subTest(audio=audio_codec):
                selected = self.resolve([
                    self.format("audio", audio_ext, acodec=audio_codec),
                    self.format("628", "mp4", vcodec="vp09.00.51.08"),
                ])[-1]

                self.assertEqual(selected["format_id"], "628+audio")
                self.assertEqual(selected["ext"], output_ext)

    def test_exact_ids_resolve_to_the_same_container_for_download(self):
        formats = [
            self.format("251", "webm", acodec="opus"),
            self.format("137", "mp4", vcodec="avc1.640028"),
            self.format("628", "mp4", vcodec="vp09.00.51.08"),
        ]
        for selected in self.resolve(formats):
            with self.subTest(format_id=selected["format_id"]):
                selector = self.downloader.build_format_selector(selected["format_id"])
                downloaded = self.downloader._select_formats(formats, selector)[0]
                self.assertEqual(downloaded["ext"], selected["ext"])
                self.assertEqual(downloaded["vcodec"], selected["vcodec"])
                self.assertEqual(downloaded["acodec"], selected["acodec"])

    def test_missing_audio_keeps_selected_video_instead_of_progressive_fallback(self):
        video = self.format("137", "mp4", vcodec="avc1.640028")
        progressive = self.format("22", "mp4", vcodec="avc1.640028", acodec="mp4a.40.2")

        self.assertEqual(self.resolve([video, progressive]), [video, progressive])

    def test_audio_and_progressive_formats_remain_native(self):
        formats = [
            self.format("140", "m4a", acodec="mp4a.40.2"),
            self.format("22", "mp4", vcodec="avc1.640028", acodec="mp4a.40.2"),
        ]

        self.assertEqual(self.resolve(formats), formats)

    def test_non_media_and_missing_ids_are_excluded(self):
        self.assertEqual(self.resolve([
            self.format("storyboard", "mhtml"),
            self.format("", "mp4", vcodec="avc1.640028"),
        ]), [])
        self.assertEqual(self.resolve([]), [])

    def test_format_list_keeps_source_metadata_separate_from_download_selection(self):
        info = {"title": "Example", "formats": [
            self.format("251", "webm", acodec="opus", size=500),
            self.format("628", "mp4", vcodec="vp09.00.51.08", size=1000),
        ]}
        with mock.patch.object(yt_dlp.YoutubeDL, "extract_info", return_value=info) as extract:
            result = json.loads(list_yt_dlp_formats("https://example.com/watch"))

        extract.assert_called_once_with("https://example.com/watch", download=False)
        self.assertTrue(result["success"])
        self.assertEqual(result["title"], "Example")
        selected = result["formats"][-1]
        self.assertEqual(selected["id"], "628")
        self.assertEqual(selected["extension"], "mp4")
        self.assertEqual(selected["audio_codec"], "none")
        self.assertEqual(selected["filesize"], 1000)
        self.assertFalse(selected["filesize_is_approximate"])
        self.assertEqual(selected["note"], "628")
        self.assertEqual(selected["download_id"], "628+251")
        self.assertEqual(selected["output_extension"], "webm")
        self.assertEqual(selected["selected_audio_codec"], "opus")

    def test_unknown_video_size_does_not_become_audio_size(self):
        audio = self.format("251", "webm", acodec="opus", size=191000)
        audio["format_note"] = "medium"
        video = self.format("628", "mp4", vcodec="vp9", size=None)
        video["format_note"] = ""
        with mock.patch.object(yt_dlp.YoutubeDL, "extract_info", return_value={"formats": [audio, video]}):
            selected = json.loads(list_yt_dlp_formats("https://example.com/watch"))["formats"][-1]

        self.assertIsNone(selected["filesize"])
        self.assertFalse(selected["filesize_is_approximate"])
        self.assertEqual(selected["note"], "")
        self.assertEqual(selected["id"], "628")
        self.assertEqual(selected["download_id"], "628+251")

    def test_source_size_estimates_are_marked_approximate(self):
        video = self.format("18", "mp4", vcodec="avc1", acodec="mp4a.40.2", size=None)
        video["filesize_approx"] = 1024000
        with mock.patch.object(yt_dlp.YoutubeDL, "extract_info", return_value={"formats": [video]}):
            selected = json.loads(list_yt_dlp_formats("https://example.com/watch"))["formats"][0]

        self.assertEqual(selected["filesize"], 1024000)
        self.assertTrue(selected["filesize_is_approximate"])

    def test_resolution_error_is_reported_instead_of_guessing_a_container(self):
        with mock.patch.object(yt_dlp.YoutubeDL, "extract_info", side_effect=ValueError("Unavailable")):
            result = json.loads(list_yt_dlp_formats("https://example.com/watch"))

        self.assertFalse(result["success"])
        self.assertEqual(result["formats"], [])
        self.assertEqual(result["error_message"], "Unavailable")
