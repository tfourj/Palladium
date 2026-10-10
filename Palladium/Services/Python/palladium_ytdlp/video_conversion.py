import json
from dataclasses import dataclass

VIDEO_CONVERSION_METHODS = ("recode", "remux")
VIDEO_CONVERSION_FORMATS = ("mp4", "webm", "avi", "mkv", "mov")
VIDEO_CONVERSION_QUALITIES = ("low", "medium", "high", "maximum")
VIDEO_ENCODER_KINDS = ("auto", "hardware", "software")

SUPPORTED_CODECS = {
    "mp4": ("h264", "hevc", "vp9", "mpeg4"),
    "mov": ("h264", "hevc", "prores", "mpeg4"),
    "mkv": ("h264", "hevc", "vp9", "vp8", "prores", "mpeg4"),
    "webm": ("vp9", "vp8"),
    "avi": ("mpeg4", "h264"),
}
DEFAULT_CODECS = {"mp4": "h264", "mov": "h264", "mkv": "h264", "webm": "vp9", "avi": "mpeg4"}

# Encoders included in the iOS FFmpeg framework, hardware first so Auto prefers VideoToolbox.
CODEC_ENCODERS = {
    "h264": (("hardware", "h264_videotoolbox"),),
    "hevc": (("hardware", "hevc_videotoolbox"),),
    "prores": (("hardware", "prores_videotoolbox"), ("software", "prores_ks")),
    "vp9": (("software", "libvpx-vp9"),),
    "vp8": (("software", "libvpx"),),
    "mpeg4": (("software", "mpeg4"),),
}

# VideoToolbox on iOS has no constant-quality mode, so hardware encoders use bitrates.
VIDEO_QUALITY_ARGS = {
    "h264_videotoolbox": {"low": ["-b:v", "3M"], "medium": ["-b:v", "5M"], "high": ["-b:v", "8M"],
                          "maximum": ["-b:v", "16M"]},
    "hevc_videotoolbox": {"low": ["-b:v", "2M"], "medium": ["-b:v", "3M"], "high": ["-b:v", "5M"],
                          "maximum": ["-b:v", "10M"]},
    "libvpx-vp9": {"low": ["-crf", "40"], "medium": ["-crf", "36"], "high": ["-crf", "32"],
                   "maximum": ["-crf", "24"]},
    "libvpx": {"low": ["-b:v", "2M"], "medium": ["-b:v", "4M"], "high": ["-b:v", "6M"],
               "maximum": ["-b:v", "12M"]},
    "mpeg4": {"low": ["-q:v", "8"], "medium": ["-q:v", "5"], "high": ["-q:v", "3"], "maximum": ["-q:v", "2"]},
}
PRORES_PROFILES = {"low": "proxy", "medium": "lt", "high": "standard", "maximum": "hq"}
AAC_BITRATES = {"low": "128k", "medium": "160k", "high": "192k", "maximum": "256k"}
OPUS_BITRATES = {"low": "96k", "medium": "112k", "high": "128k", "maximum": "160k"}

# Audio codecs each container can hold without re-encoding. MKV accepts any codec.
# Opus is excluded from MP4 and MOV because Apple players and Photos reject it there.
COPYABLE_AUDIO_CODECS = {
    "mp4": {"aac", "alac", "mp3", "ac3", "eac3"},
    "mov": {"aac", "alac", "mp3", "ac3", "eac3", "pcm_s16le"},
    "webm": {"opus", "vorbis"},
    "avi": {"mp3", "ac3", "pcm_s16le"},
}


@dataclass(frozen=True)
class VideoConversionSettings:
    method: str
    format: str
    codec: str
    encoder: str
    auto_encoder: bool
    quality: str
    hardware_decoding: bool

    @property
    def ffmpeg_encoder(self):
        return dict(CODEC_ENCODERS[self.codec])[self.encoder]

    @property
    def software_fallback(self):
        """Settings to retry with after a hardware failure, or None when nothing would change."""
        encoder = self.encoder
        if self.auto_encoder and "software" in dict(CODEC_ENCODERS[self.codec]):
            encoder = "software"
        if encoder == self.encoder and not self.hardware_decoding:
            return None
        return VideoConversionSettings(
            self.method, self.format, self.codec, encoder, False, self.quality, False
        )


def parse_video_conversion_settings(configuration_json):
    """Returns settings for an enabled conversion, None when disabled, or raises ValueError."""
    if not configuration_json:
        return None
    configuration = json.loads(str(configuration_json))
    if not isinstance(configuration, dict) or configuration.get("enabled") is not True:
        return None

    method = configuration.get("method")
    target = configuration.get("format")
    codec = configuration.get("codec", "auto")
    encoder = configuration.get("encoder", "auto")
    quality = configuration.get("quality", "high")
    hardware_decoding = configuration.get("hardwareDecoding", True)
    if (
        method not in VIDEO_CONVERSION_METHODS
        or target not in VIDEO_CONVERSION_FORMATS
        or (codec != "auto" and codec not in CODEC_ENCODERS)
        or encoder not in VIDEO_ENCODER_KINDS
        or quality not in VIDEO_CONVERSION_QUALITIES
        or not isinstance(hardware_decoding, bool)
    ):
        raise ValueError("Unsupported video post-processing settings")

    # Match the settings screen: unsupported choices for the container fall back to Auto.
    if codec not in SUPPORTED_CODECS[target]:
        codec = DEFAULT_CODECS[target]
    available = [kind for kind, _ in CODEC_ENCODERS[codec]]
    auto_encoder = encoder not in available
    if auto_encoder:
        encoder = available[0]
    return VideoConversionSettings(method, target, codec, encoder, auto_encoder, quality, hardware_decoding)


def video_decoder_args(settings):
    return ["-hwaccel", "videotoolbox"] if settings.hardware_decoding else []


def video_encoder_args(settings):
    encoder = settings.ffmpeg_encoder
    args = ["-c:v", encoder]
    if settings.codec == "prores":
        args.extend(["-profile:v", PRORES_PROFILES[settings.quality]])
        if encoder == "prores_ks":
            args.extend(["-pix_fmt", "yuv422p10le"])
        return args

    args.extend(VIDEO_QUALITY_ARGS[encoder][settings.quality])
    if encoder == "libvpx-vp9":
        args.extend(["-b:v", "0", "-row-mt", "1"])
    if encoder in ("libvpx-vp9", "libvpx"):
        # libvpx defaults to its slowest preset, which is impractical on a phone.
        args.extend(["-deadline", "good", "-cpu-used", "4"])
    args.extend(["-pix_fmt", "yuv420p"])
    return args


def video_tag_args(settings):
    if settings.codec == "hevc" and settings.format in ("mp4", "mov"):
        # Apple players only recognize HEVC tagged as hvc1.
        return ["-tag:v", "hvc1"]
    if settings.codec == "h264" and settings.format == "avi":
        # yt-dlp tags AVI video as XVID, which is wrong for H.264.
        return ["-tag:v", "H264"]
    return []


def audio_encoder_args(settings):
    if settings.format == "webm":
        return ["-c:a", "libopus", "-b:a", OPUS_BITRATES[settings.quality]]
    if settings.format == "avi" or settings.codec == "prores":
        return ["-c:a", "pcm_s16le"]
    return ["-c:a", "aac", "-b:a", AAC_BITRATES[settings.quality]]


def recode_output_args(settings):
    return [*video_encoder_args(settings), *video_tag_args(settings), *audio_encoder_args(settings)]
