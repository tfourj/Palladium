import json
import unittest

from scripts.python_tests import helpers  # noqa: F401
from palladium_ytdlp.args import apply_post_processing_args
from palladium_ytdlp.video_conversion import (
    parse_video_conversion_settings,
    plan_video_conversion,
    recode_output_args,
    source_stream_codecs,
    stream_copy_output_args,
)


class PostProcessingTests(unittest.TestCase):
    def configuration(self, method="recode", target="mp4", **encoding):
        return json.dumps({"enabled": True, "method": method, "format": target, **encoding})

    def settings(self, target="mp4", **encoding):
        return parse_video_conversion_settings(self.configuration("recode", target, **encoding))

    def postprocessor_args(self, extra):
        return [extra[index + 1] for index, arg in enumerate(extra) if arg == "--postprocessor-args"]

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
        for method, target in (("unknown", "mp4"), ("recode", "invalid"), ("remux", "invalid")):
            with self.subTest(method=method, target=target), self.assertRaises(ValueError):
                apply_post_processing_args([], [], self.configuration(method, target))

    def test_default_recode_uses_videotoolbox_encoding_and_decoding(self):
        _, extra = apply_post_processing_args([], [], self.configuration())
        self.assertEqual(self.postprocessor_args(extra), [
            "VideoConvertor+ffmpeg_o:-c:v h264_videotoolbox -b:v 8M -pix_fmt yuv420p -c:a aac -b:a 192k",
            "VideoConvertor+ffmpeg_i:-hwaccel videotoolbox",
        ])

    def test_hevc_is_tagged_for_apple_players_and_decoding_can_be_disabled(self):
        _, extra = apply_post_processing_args(
            [], [], self.configuration(target="mov", codec="hevc", quality="low", hardwareDecoding=False)
        )
        self.assertEqual(self.postprocessor_args(extra), [
            "VideoConvertor+ffmpeg_o:-c:v hevc_videotoolbox -b:v 2M -pix_fmt yuv420p -tag:v hvc1 -c:a aac -b:a 128k",
        ])

    def test_remux_ignores_encoding_settings(self):
        _, extra = apply_post_processing_args([], [], self.configuration("remux", codec="hevc"))
        self.assertEqual(self.postprocessor_args(extra), [])

    def test_codec_and_encoder_resolve_for_container(self):
        cases = [
            ({}, "mp4", "h264", "h264_videotoolbox"),
            ({}, "webm", "vp9", "libvpx-vp9"),
            ({}, "avi", "mpeg4", "mpeg4"),
            ({"codec": "vp8"}, "mp4", "h264", "h264_videotoolbox"),
            ({"codec": "h264", "encoder": "software"}, "mkv", "h264", "h264_videotoolbox"),
            ({"codec": "prores"}, "mov", "prores", "prores_videotoolbox"),
            ({"codec": "prores", "encoder": "software"}, "mov", "prores", "prores_ks"),
        ]
        for encoding, target, codec, encoder in cases:
            with self.subTest(target=target, **encoding):
                settings = self.settings(target, **encoding)
                self.assertEqual(settings.codec, codec)
                self.assertEqual(settings.ffmpeg_encoder, encoder)

    def test_every_supported_combination_builds_arguments(self):
        for target in ("mp4", "webm", "avi", "mkv", "mov"):
            for codec in ("auto", "h264", "hevc", "vp9", "vp8", "mpeg4", "prores"):
                for quality in ("low", "medium", "high", "maximum"):
                    settings = self.settings(target, codec=codec, quality=quality)
                    arguments = recode_output_args(settings)
                    self.assertEqual(arguments[arguments.index("-c:v") + 1], settings.ffmpeg_encoder)
                    self.assertIn("-c:a", arguments)

    def test_unsupported_encoding_values_are_rejected(self):
        for encoding in ({"codec": "av1"}, {"encoder": "gpu"}, {"quality": "ultra"}, {"hardwareDecoding": "yes"}):
            with self.subTest(**encoding), self.assertRaises(ValueError):
                self.settings(**encoding)

    def test_auto_falls_back_to_software_after_hardware_failure(self):
        prores = self.settings("mov", codec="prores").software_fallback
        self.assertEqual((prores.ffmpeg_encoder, prores.hardware_decoding), ("prores_ks", False))
        h264 = self.settings().software_fallback
        self.assertEqual((h264.ffmpeg_encoder, h264.hardware_decoding), ("h264_videotoolbox", False))
        self.assertIsNone(h264.software_fallback)
        self.assertIsNone(self.settings("mov", codec="prores", encoder="hardware", hardwareDecoding=False).software_fallback)

    def test_conversion_plan_compares_codecs(self):
        hevc = self.settings(codec="hevc")
        self.assertEqual(plan_video_conversion(hevc, "mp4", "h264"), "encode")
        self.assertEqual(plan_video_conversion(hevc, "mp4", "hevc"), "skip")
        self.assertEqual(plan_video_conversion(hevc, "mkv", "hevc"), "copy")
        always = self.settings(codec="hevc", alwaysReencode=True)
        self.assertEqual(plan_video_conversion(always, "mp4", "hevc"), "encode")

    def test_stream_copy_converts_only_incompatible_audio(self):
        hevc = self.settings(codec="hevc")
        self.assertEqual(stream_copy_output_args(hevc, ["aac"]), ["-c:v", "copy", "-tag:v", "hvc1", "-c:a", "copy"])
        self.assertEqual(
            stream_copy_output_args(hevc, ["opus"]), ["-c:v", "copy", "-tag:v", "hvc1", "-c:a", "aac", "-b:a", "192k"]
        )
        self.assertEqual(
            stream_copy_output_args(self.settings("avi", codec="h264"), ["mp3"]),
            ["-c:v", "copy", "-tag:v", "H264", "-bsf:v", "h264_mp4toannexb", "-c:a", "copy"],
        )
        self.assertEqual(stream_copy_output_args(self.settings("mkv"), ["opus"]), ["-c:v", "copy", "-c:a", "copy"])

    def test_source_codecs_ignore_cover_art(self):
        metadata = {"streams": [
            {"codec_type": "video", "codec_name": "mjpeg", "disposition": {"attached_pic": 1}},
            {"codec_type": "video", "codec_name": "VP9"},
            {"codec_type": "audio", "codec_name": "opus"},
        ]}
        self.assertEqual(source_stream_codecs(metadata), ("vp9", ["opus"]))
        self.assertEqual(source_stream_codecs({"streams": []}), (None, []))


if __name__ == "__main__":
    unittest.main()
