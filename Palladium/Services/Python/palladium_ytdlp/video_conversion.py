import contextlib
import json
import os
from dataclasses import dataclass, replace

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
    always_reencode: bool = False

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
        return replace(self, encoder=encoder, auto_encoder=False, hardware_decoding=False)


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
    always_reencode = configuration.get("alwaysReencode", False)
    if (
        method not in VIDEO_CONVERSION_METHODS
        or target not in VIDEO_CONVERSION_FORMATS
        or (codec != "auto" and codec not in CODEC_ENCODERS)
        or encoder not in VIDEO_ENCODER_KINDS
        or quality not in VIDEO_CONVERSION_QUALITIES
        or not isinstance(hardware_decoding, bool)
        or not isinstance(always_reencode, bool)
    ):
        raise ValueError("Unsupported video post-processing settings")

    # Match the settings screen: unsupported choices for the container fall back to Auto.
    if codec not in SUPPORTED_CODECS[target]:
        codec = DEFAULT_CODECS[target]
    available = [kind for kind, _ in CODEC_ENCODERS[codec]]
    auto_encoder = encoder not in available
    if auto_encoder:
        encoder = available[0]
    return VideoConversionSettings(
        method, target, codec, encoder, auto_encoder, quality, hardware_decoding, always_reencode
    )


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


def source_stream_codecs(metadata):
    """Returns the main video codec and the audio codecs from ffprobe metadata."""
    video_codec = None
    audio_codecs = []
    for stream in (metadata or {}).get("streams") or []:
        if not isinstance(stream, dict):
            continue
        codec_name = str(stream.get("codec_name") or "").lower()
        if stream.get("codec_type") == "video" and video_codec is None:
            # Embedded cover art is a video stream too, but not the one being converted.
            if (stream.get("disposition") or {}).get("attached_pic") != 1:
                video_codec = codec_name
        elif stream.get("codec_type") == "audio":
            audio_codecs.append(codec_name)
    return video_codec, audio_codecs


def plan_video_conversion(settings, source_ext, video_codec):
    """Decides how to reach the target: "skip", "copy" the video stream, or "encode" it."""
    if settings.always_reencode or video_codec != settings.codec:
        return "encode"
    return "skip" if source_ext == settings.format else "copy"


def stream_copy_output_args(settings, audio_codecs):
    copyable_audio = COPYABLE_AUDIO_CODECS.get(settings.format)
    if copyable_audio is None or all(codec in copyable_audio for codec in audio_codecs):
        audio_args = ["-c:a", "copy"]
    else:
        audio_args = audio_encoder_args(settings)
    video_args = ["-c:v", "copy", *video_tag_args(settings)]
    if settings.codec == "h264" and settings.format == "avi":
        # AVI stores H.264 as Annex B, unlike the MP4 and MKV sources it is copied from.
        video_args.extend(["-bsf:v", "h264_mp4toannexb"])
    return [*video_args, *audio_args]


@contextlib.contextmanager
def codec_aware_video_conversion(settings):
    """Makes yt-dlp's converter compare video codecs, not only file extensions.

    Re-encodes files already in the target container when their codec differs, copies the
    video stream when the codec already matches unless every video must be re-encoded, and
    retries hardware failures without hardware decoding or with a software encoder when Auto
    allows it.
    """
    if settings is None or settings.method != "recode":
        yield
        return
    try:
        import yt_dlp.postprocessor.ffmpeg as ydl_ffmpeg_pp
        from yt_dlp.utils import prepend_extension, replace_extension
    except Exception:
        yield
        return

    converter_class = ydl_ffmpeg_pp.FFmpegVideoConvertorPP
    original_run = converter_class.run

    def run_ffmpeg_with_args(processor, source, output, options, input_args, output_args):
        def configuration_args(exe, keys=None, *args, **kwargs):
            keys = list(keys or [])
            return list(input_args if any(key.startswith("_i") for key in keys) else output_args)

        processor._configuration_args = configuration_args
        try:
            processor.run_ffmpeg(source, output, options)
        finally:
            del processor._configuration_args

    def encode(processor, source, output, options, attempt):
        while True:
            try:
                run_ffmpeg_with_args(
                    processor, source, output, options,
                    video_decoder_args(attempt), recode_output_args(attempt),
                )
                return
            except ydl_ffmpeg_pp.FFmpegPostProcessorError as error:
                fallback = attempt.software_fallback
                if fallback is None:
                    raise
                processor.report_warning(f"Hardware conversion failed, retrying with {fallback.ffmpeg_encoder}: {error}")
                attempt = fallback

    @ydl_ffmpeg_pp.PostProcessor._restrict_to(images=False)
    def patched_run(self, info):
        if isinstance(self, ydl_ffmpeg_pp.FFmpegVideoRemuxerPP):
            return original_run(self, info)

        filename, source_ext = info["filepath"], info["ext"].lower()
        try:
            video_codec, audio_codecs = source_stream_codecs(self.get_metadata_object(filename))
        except Exception as error:
            self.report_warning(f"Unable to read video codecs, converting by extension only: {error}")
            return original_run(self, info)
        if video_codec is None:
            return original_run(self, info)

        plan = plan_video_conversion(settings, source_ext, video_codec)
        options = list(ydl_ffmpeg_pp.FFmpegPostProcessor.stream_copy_opts(False))
        if plan == "skip":
            self.to_screen(f'Not converting media file "{filename}"; already {settings.format} with {video_codec}')
            return [], info
        if source_ext == settings.format:
            # yt-dlp skips matching extensions, so encode to a temporary file and replace the source.
            outpath = prepend_extension(filename, "temp")
            self.to_screen(f"Converting video from {video_codec} to {settings.codec}; Destination: {filename}")
            try:
                encode(self, filename, outpath, options, settings)
                os.replace(outpath, filename)
            finally:
                if os.path.exists(outpath):
                    os.remove(outpath)
            return [], info

        outpath = replace_extension(filename, settings.format, source_ext)
        if plan == "copy":
            self.to_screen(f"Copying {video_codec} video from {source_ext} to {settings.format}; Destination: {outpath}")
            run_ffmpeg_with_args(self, filename, outpath, options, [], stream_copy_output_args(settings, audio_codecs))
        else:
            self.to_screen(f"Converting video from {video_codec} to {settings.codec}; Destination: {outpath}")
            encode(self, filename, outpath, options, settings)
        info["filepath"] = outpath
        info["format"] = info["ext"] = settings.format
        return [filename], info

    converter_class.run = patched_run
    try:
        yield
    finally:
        converter_class.run = original_run
