import json
import os
import tempfile
import unittest
from unittest import mock

import yt_dlp

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.ytdlp import list_yt_dlp_formats, resolve_picker_formats  # noqa: E402
from palladium_ytdlp.args import apply_post_processing_args, build_output_args  # noqa: E402
from palladium_ytdlp.video_conversion import (  # noqa: E402
    codec_aware_video_conversion,
    parse_video_conversion_settings,
)
from yt_dlp.postprocessor.ffmpeg import FFmpegPostProcessorError, FFmpegVideoConvertorPP, FFmpegVideoRemuxerPP


class OutputTemplateIntegrationTests(unittest.TestCase):
    def test_default_shortens_long_unicode_titles_and_keeps_extension(self):
        output_args = build_output_args("default", "", False, [], [])
        options = yt_dlp.parse_options(["--ignore-config", *output_args]).ydl_opts
        downloader = yt_dlp.YoutubeDL(options)

        short_name = downloader.prepare_filename({"id": "short", "title": "Short title", "ext": "mp4"})
        long_name = downloader.prepare_filename({"id": "long", "title": "é" * 200, "ext": "mp4"})

        self.assertEqual(short_name, "Short title.mp4")
        self.assertTrue(long_name.endswith(".mp4"))
        self.assertLessEqual(len(long_name.encode("utf-8")), 204)


class PostProcessingIntegrationTests(unittest.TestCase):
    def test_all_supported_targets_produce_exactly_one_conversion_processor(self):
        for method in ("recode", "remux"):
            for target in ("mp4", "webm", "avi", "mkv", "mov"):
                with self.subTest(method=method, target=target):
                    preset, extra = apply_post_processing_args(
                        ["--remux-video", "mp4"],
                        ["--recode-video=mov", "--format", "137+140"],
                        json.dumps({"enabled": True, "method": method, "format": target}),
                    )
                    options = yt_dlp.parse_options(["--ignore-config", *preset, *extra]).ydl_opts
                    processors = [
                        pp for pp in options["postprocessors"]
                        if pp["key"] in ("FFmpegVideoConvertor", "FFmpegVideoRemuxer")
                    ]
                    expected = "FFmpegVideoConvertor" if method == "recode" else "FFmpegVideoRemuxer"
                    self.assertEqual(len(processors), 1)
                    self.assertEqual(processors[0]["key"], expected)
                    self.assertEqual(processors[0]["preferedformat"], target)
                    self.assertEqual(options["merge_output_format"], "mkv")
                    self.assertEqual(options["format"], "137+140")

                    downloader = yt_dlp.YoutubeDL(options)
                    processor = next(pp for pp in downloader._pps["post_process"] if pp.pp_key() == expected[6:])
                    arguments = processor._configuration_args("ffmpeg", ["_o1", "_o", ""])
                    if method == "recode":
                        if target == "webm":
                            self.assertEqual(arguments[arguments.index("-c:v") + 1], "libvpx-vp9")
                            self.assertEqual(arguments[arguments.index("-c:a") + 1], "libopus")
                        else:
                            self.assertIn("mpeg4" if target == "avi" else "h264_videotoolbox", arguments)
                    else:
                        self.assertEqual(arguments, [])

    def test_converted_path_is_returned_and_original_is_marked_for_cleanup(self):
        for processor_type in (FFmpegVideoConvertorPP, FFmpegVideoRemuxerPP):
            processor = processor_type(yt_dlp.YoutubeDL({"quiet": True}), preferedformat="avi")
            with mock.patch.object(processor, "run_ffmpeg") as run:
                deleted, result = processor.run({"filepath": "/tmp/video.mp4", "ext": "mp4"})
            run.assert_called_once()
            self.assertEqual(deleted, ["/tmp/video.mp4"])
            self.assertEqual(result["filepath"], "/tmp/video.avi")
            self.assertEqual(result["ext"], "avi")

    def test_matching_container_is_not_reencoded(self):
        processor = FFmpegVideoConvertorPP(yt_dlp.YoutubeDL({"quiet": True}), preferedformat="mp4")
        with mock.patch.object(processor, "run_ffmpeg") as run:
            deleted, result = processor.run({"filepath": "/tmp/video.mp4", "ext": "mp4"})
        run.assert_not_called()
        self.assertEqual(deleted, [])
        self.assertEqual(result["filepath"], "/tmp/video.mp4")


class CodecAwareConversionTests(unittest.TestCase):
    def convert(self, source_ext, video_codec, audio_codec="aac", fail_first=False, **encoding):
        settings = parse_video_conversion_settings(json.dumps({"enabled": True, "method": "recode", **encoding}))
        directory = self.enterContext(tempfile.TemporaryDirectory())
        source = os.path.join(directory, f"video.{source_ext}")
        with open(source, "w") as file:
            file.write("source")
        metadata = {"streams": [
            {"codec_type": "video", "codec_name": video_codec},
            {"codec_type": "audio", "codec_name": audio_codec},
        ]}
        calls = []

        with codec_aware_video_conversion(settings):
            processor = FFmpegVideoConvertorPP(yt_dlp.YoutubeDL({"quiet": True}), preferedformat=settings.format)

            def run_ffmpeg(path, out_path, options):
                calls.append((
                    processor._configuration_args("ffmpeg", ["_i1", "_i"]),
                    processor._configuration_args("ffmpeg", ["_o1", "_o", ""]),
                ))
                if fail_first and len(calls) == 1:
                    raise FFmpegPostProcessorError("hardware failed")
                with open(out_path, "w") as file:
                    file.write("converted")

            with (
                mock.patch.object(processor, "get_metadata_object", return_value=metadata),
                mock.patch.object(processor, "run_ffmpeg", side_effect=run_ffmpeg),
                mock.patch.object(processor, "report_warning"),
            ):
                deleted, info = processor.run({
                    "filepath": source, "ext": source_ext, "vcodec": video_codec, "acodec": audio_codec,
                })
        return source, deleted, info, calls, sorted(os.listdir(directory))

    def test_matching_container_with_other_codec_is_reencoded_in_place(self):
        source, deleted, info, calls, files = self.convert("mp4", "h264", format="mp4", codec="hevc")
        self.assertEqual(deleted, [])
        self.assertEqual(info["filepath"], source)
        self.assertEqual(files, ["video.mp4"])
        self.assertEqual(calls[0][0], ["-hwaccel", "videotoolbox"])
        self.assertIn("hevc_videotoolbox", calls[0][1])

    def test_matching_container_and_codec_is_skipped(self):
        _, deleted, _, calls, _ = self.convert("mp4", "h264", format="mp4")
        self.assertEqual((deleted, calls), ([], []))

    def test_matching_codec_is_copied_into_new_container(self):
        source, deleted, info, calls, _ = self.convert("mkv", "h264", "opus", format="mp4")
        self.assertEqual(deleted, [source])
        self.assertEqual(info["ext"], "mp4")
        self.assertEqual(calls, [([], ["-c:v", "copy", "-c:a", "aac", "-b:a", "192k"])])

    def test_always_reencode_encodes_matching_codec(self):
        _, _, _, calls, _ = self.convert("mkv", "h264", format="mp4", alwaysReencode=True)
        self.assertIn("h264_videotoolbox", calls[0][1])

    def test_auto_retries_hardware_failure_with_software(self):
        _, _, info, calls, _ = self.convert("mkv", "h264", fail_first=True, format="mov", codec="prores")
        self.assertEqual(info["ext"], "mov")
        self.assertIn("prores_videotoolbox", calls[0][1])
        self.assertEqual(calls[1][0], [])
        self.assertIn("prores_ks", calls[1][1])

    def test_explicit_hardware_failure_is_not_hidden(self):
        with self.assertRaises(FFmpegPostProcessorError):
            self.convert(
                "mkv", "h264", fail_first=True,
                format="mov", codec="prores", encoder="hardware", hardwareDecoding=False,
            )


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
        self.assertEqual(selected["selected_audio"]["id"], "251")
        self.assertEqual(selected["selected_audio"]["extension"], "webm")
        self.assertEqual(selected["selected_audio"]["filesize"], 500)

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
        self.assertEqual(selected["selected_audio"]["filesize"], 191000)

    def test_available_thumbnail_is_exposed_for_final_container_display(self):
        info = {
            "thumbnails": [{"url": "https://example.com/thumbnail.jpg"}],
            "formats": [self.format("137", "mp4", vcodec="avc1")],
        }
        with mock.patch.object(yt_dlp.YoutubeDL, "extract_info", return_value=info):
            selected = json.loads(list_yt_dlp_formats("https://example.com/watch"))["formats"][0]

        self.assertTrue(selected["has_thumbnail"])
        self.assertIsNone(selected["selected_audio"])

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
