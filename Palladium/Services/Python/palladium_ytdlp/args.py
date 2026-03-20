import json
import re
import shlex
import traceback

CLI_DASHLIKE_PREFIX = "?\u2010\u2011\u2012\u2013\u2014\u2015\u2212\uFE58\uFE63\uFF0D"
FLAGS_WITH_VALUES = {
    "-o",
    "--output",
    "--convert-thumbnails",
    "--sub-lang",
    "--sub-langs",
}
PLAYLIST_CONTROL_FLAGS = {
    "--no-playlist",
    "--yes-playlist",
}
SUBTITLE_CONTROL_FLAGS = {
    "--all-subs",
    "--embed-subs",
    "--skip-download",
    "--sub-lang",
    "--sub-langs",
    "--write-auto-sub",
    "--write-auto-subs",
    "--write-sub",
    "--write-subs",
}
THUMBNAIL_CONTROL_FLAGS = {
    "--convert-thumbnails",
    "--embed-thumbnail",
    "--no-embed-thumbnail",
    "--write-all-thumbnails",
    "--write-thumbnail",
}


def build_preset_args(preset):
    if preset == "audio":
        print("[palladium] preset: audio (mp3 template)")
        return ["-f", "ba[acodec^=mp3]/ba/b", "-x", "--audio-format", "mp3"]

    if preset == "mute":
        print("[palladium] preset: mute (mp4 no-audio)")
        return [
            "-f", "bv*/bestvideo",
            "--merge-output-format", "mp4",
            "--remux-video", "mp4",
            "-S", "vcodec:h264,lang,quality,res,fps,hdr:12",
        ]

    print("[palladium] preset: auto_video (mp4 template)")
    return [
        "--merge-output-format", "mp4",
        "--remux-video", "mp4",
        "-S", "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac",
    ]


def normalize_cli_arg_token(token):
    value = str(token)
    if not value:
        return value
    if value.startswith("--"):
        return value
    if value.startswith("-") and (len(value) == 1 or value[1] not in CLI_DASHLIKE_PREFIX):
        return value
    if value.startswith(("http://", "https://", "file:/", "/")):
        return value
    if value[0] not in CLI_DASHLIKE_PREFIX:
        return value

    match = re.match(rf"^[{re.escape(CLI_DASHLIKE_PREFIX)}-]+([A-Za-z][A-Za-z0-9_-]*)(.*)$", value)
    if not match:
        return value

    option_name = match.group(1)
    suffix = match.group(2)
    prefix = "-" if len(option_name) == 1 else "--"
    normalized = f"{prefix}{option_name}{suffix}"
    if normalized != value:
        print(f"[palladium] normalized arg token: {value!r} -> {normalized!r}")
    return normalized


def normalize_cli_args(tokens):
    return [normalize_cli_arg_token(token) for token in tokens]


def parse_custom_args(custom_args_value):
    if not custom_args_value:
        return []
    try:
        parsed = normalize_cli_args(shlex.split(str(custom_args_value)))
        print(f"[palladium] custom args parsed: {parsed}")
        return parsed
    except Exception:
        print("[palladium] failed to parse custom args")
        traceback.print_exc()
        return []


def parse_preset_args_map(preset_args_json_value):
    defaults = {
        "auto_video": "",
        "mute": "",
        "audio": "",
        "custom": "",
    }
    if not preset_args_json_value:
        return defaults

    try:
        parsed = json.loads(str(preset_args_json_value))
        if not isinstance(parsed, dict):
            return defaults
        output = defaults.copy()
        for key in output.keys():
            if key in parsed and isinstance(parsed[key], str):
                output[key] = parsed[key].strip()
        return output
    except Exception:
        print("[palladium] failed to parse preset args json")
        traceback.print_exc()
        return defaults


def parse_extra_args(extra_args_value):
    if not extra_args_value:
        return []
    try:
        parsed = normalize_cli_args(shlex.split(str(extra_args_value)))
        print(f"[palladium] extra args parsed: {parsed}")
        return parsed
    except Exception:
        print("[palladium] failed to parse extra args")
        traceback.print_exc()
        return []


def has_custom_output_template(args):
    normalized = [str(arg) for arg in (args or [])]
    for index, arg in enumerate(normalized):
        if arg == "-o":
            return index + 1 < len(normalized)
        if arg == "--output":
            return index + 1 < len(normalized)
        if arg.startswith("--output="):
            return True
    return False


def strip_checkbox_owned_download_args(args):
    normalized = [str(arg) for arg in (args or [])]
    stripped = []
    index = 0

    while index < len(normalized):
        arg = normalized[index]
        option_name = arg.split("=", 1)[0]

        if option_name in PLAYLIST_CONTROL_FLAGS or option_name in SUBTITLE_CONTROL_FLAGS or option_name in THUMBNAIL_CONTROL_FLAGS:
            if option_name in FLAGS_WITH_VALUES and "=" not in arg and index + 1 < len(normalized):
                index += 2
            else:
                index += 1
            continue

        stripped.append(arg)
        index += 1

    return stripped
