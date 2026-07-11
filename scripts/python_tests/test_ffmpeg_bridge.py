import os
import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.ffmpeg_bridge import (  # noqa: E402
    BridgeCommandResult,
    SwiftFFmpegBridge,
    audio_codec_from_metadata,
    bridge_ffmpeg_output_path,
    parse_bridge_json_object,
)


class FFmpegBridgeTests(unittest.TestCase):
    def make_bridge(self, ffmpeg_outputs, ffprobe_output="ffprobe version 8.0"):
        bridge = SwiftFFmpegBridge.__new__(SwiftFFmpegBridge)
        bridge._capabilities = None
        calls = []

        def run_ffmpeg(args):
            calls.append(("ffmpeg", args))
            output = ffmpeg_outputs[tuple(args)]
            if isinstance(output, Exception):
                raise output
            return BridgeCommandResult(0, output, "")

        def run_ffprobe(args):
            calls.append(("ffprobe", args))
            return BridgeCommandResult(0, ffprobe_output, "")

        bridge.run_ffmpeg = run_ffmpeg
        bridge.run_ffprobe = run_ffprobe
        return bridge, calls

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

    def test_output_path_normalizes_file_url(self):
        self.assertEqual(
            bridge_ffmpeg_output_path(["-i", "input.mp4", "file:/tmp/output%20file.mp4"]),
            "/tmp/output file.mp4",
        )

    def test_json_object_parser_ignores_captured_log_output(self):
        output = "[palladium] prior output {'not': 'json'}\n{\"streams\": [], \"format\": {}}\ntrailing log"

        self.assertEqual(parse_bridge_json_object(output), {"streams": [], "format": {}})

    def test_metadata_probe_requests_compact_json(self):
        bridge = SwiftFFmpegBridge.__new__(SwiftFFmpegBridge)
        calls = []

        def run_ffprobe(args):
            calls.append(args)
            output_path = args[args.index("-o") + 1]
            with open(output_path, "w", encoding="utf-8") as output_file:
                output_file.write('{"streams":[],"format":{}}')
            return BridgeCommandResult(0, "corrupted shared stdout", "")

        bridge.run_ffprobe = run_ffprobe

        self.assertEqual(bridge.probe_metadata("/tmp/video.mp4"), {"streams": [], "format": {}})
        self.assertEqual(calls, [[
            "-hide_banner",
            "-loglevel",
            "error",
            "-show_format",
            "-show_streams",
            "-print_format",
            "json=compact=1",
            "-o",
            calls[0][calls[0].index("-o") + 1],
            "/tmp/video.mp4",
        ]])
        self.assertFalse(os.path.exists(calls[0][calls[0].index("-o") + 1]))

    def test_capability_probe_gets_version_and_features_separately(self):
        bridge, calls = self.make_bridge({
            ("-version",): "ffmpeg version 8.0\nconfiguration: --enable-libfdk-aac",
            ("-bsfs",): "Bitstream filters:\naac_adtstoasc\nsetts",
        })

        capabilities = bridge.probe_capabilities()

        self.assertEqual(capabilities["versions"], {"ffmpeg": "8.0", "ffprobe": "8.0"})
        self.assertEqual(capabilities["features"], {
            "fdk": True,
            "setts": True,
            "needs_adtstoasc": True,
        })
        self.assertEqual(calls, [
            ("ffmpeg", ["-version"]),
            ("ffmpeg", ["-bsfs"]),
            ("ffprobe", ["-version"]),
        ])

    def test_capability_probe_preserves_version_when_bsf_probe_fails(self):
        bridge, _ = self.make_bridge({
            ("-version",): "ffmpeg version 8.0",
            ("-bsfs",): RuntimeError("unsupported probe"),
        })

        capabilities = bridge.probe_capabilities()

        self.assertEqual(capabilities["versions"]["ffmpeg"], "8.0")
        self.assertEqual(capabilities["features"], {
            "fdk": False,
            "setts": False,
            "needs_adtstoasc": False,
        })
