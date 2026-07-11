import unittest

from scripts.python_tests import helpers  # noqa: F401

from palladium_ytdlp.ffmpeg_bridge import (  # noqa: E402
    BridgeCommandResult,
    SwiftFFmpegBridge,
    audio_codec_from_metadata,
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
