import json
import re

from fastapi import HTTPException, Request
from request_body import read_bounded_body


LINK_CODE = re.compile(r"[A-Za-z0-9_-]{22}")
LINK_LIFETIME = 30 * 86400
MAX_LINKS = 20000
MAX_PAYLOAD_BYTES = 12000

BOOLEANS = {
    "promax_view_deleted", "promax_view_redacted", "promax_full_timestamp",
    "promax_show_forward", "promax_show_typing_time", "promax_ghost_mode",
    "promax_anti_read", "promax_read_on_reaction", "promax_read_on_reply",
    "promax_read_on_send", "promax_classic_design", "promax_self_online_check",
    "promax_hide_all_chats_folder", "promax_show_hidden_chats", "promax_archive_on_pull",
    "promax_record_debug_logs", "app_amoled", "dev_video_note_rear_camera",
    "call_light_wide_default", "promax_no_typing", "promax_hide_story_views",
    "promax_atmosphere_triggers", "promax_chat_aura", "promax_nav_tabs",
    "promax_icon_tiles", "promax_app_switcher_blur",
}
STRINGS = {
    "app_theme_mode": {"system", "light", "dark", "schedule"},
    "app_font": {"system", "inter", "unbounded"},
    "promax_atmosphere_effect": {
        "none", "snow", "rain", "stars", "leaves", "sakura", "hearts", "confetti",
        "sparkles", "bubbles", "fireflies",
    },
    "promax_theme_preset": {
        "graphite", "aurora", "sunset", "ocean", "forest", "neon", "sakura",
        "winter", "night", "system",
    },
}
COLORS = {"app_accent_seed", "call_light_color", "promax_atmosphere_color"}
NUMBERS = {
    "app_font_scale": (0.6, 1.35),
    "call_light_brightness": (0.1, 1.0),
    "call_light_width": (4.0, 100.0),
    "call_light_opacity": (0.1, 1.0),
    "call_light_radius": (0.0, 100.0),
    "promax_glass_blur": (0.0, 2.5),
    "promax_glass_refraction": (0.0, 40.0),
    "promax_glass_specular": (0.0, 2.0),
    "promax_glass_chroma": (0.0, 0.4),
    "promax_glass_rim": (0.0, 2.0),
    "promax_glass_tint": (0.0, 1.2),
    "promax_atmosphere_density": (0.2, 3.0),
    "promax_atmosphere_speed": (0.2, 3.0),
    "promax_atmosphere_size": (0.4, 2.5),
    "promax_atmosphere_opacity": (0.1, 1.0),
    "promax_atmosphere_wind": (-1.0, 1.0),
}
VIDEO = {"dev_video_note_resolution": {480, 720, 1080}, "dev_video_note_fps": {30, 60}}
PLATFORMS = {"android", "ios", "windows", "macos", "linux", "web", "fuchsia"}


def valid_setting(key, value):
    if key in BOOLEANS:
        return type(value) is bool
    if key in STRINGS:
        return isinstance(value, str) and value in STRINGS[key]
    if key == "promax_quick_reaction":
        return isinstance(value, str) and 0 < len(value.encode("utf-16-le")) <= 64
    if key in VIDEO:
        return type(value) is int and value in VIDEO[key]
    if key in COLORS:
        return type(value) is int and 0 <= value <= 4294967295
    if key in NUMBERS:
        minimum, maximum = NUMBERS[key]
        return type(value) in (int, float) and minimum <= value <= maximum
    return False


def valid_platform_setting(platform, key, value):
    if key == "app_performance_mode":
        return isinstance(value, str) and value in {"auto", "smooth", "beauty"}
    if key == "app_native_glass":
        return platform == "ios" and type(value) is bool
    if platform not in {"android", "ios"}:
        return False
    if key in {"call_pip_enabled", "dev_video_note_rear_camera"}:
        return type(value) is bool
    return key in VIDEO and valid_setting(key, value)


def valid_document(document):
    if not isinstance(document, dict):
        return False
    keys = {"format", "version", "settings"}
    if document.keys() not in (keys, keys | {"platform", "platformSettings"}):
        return False
    if document["format"] != "ProMax" or type(document["version"]) is not int or document["version"] != 1:
        return False
    settings = document["settings"]
    if not isinstance(settings, dict) or not settings or not all(
        valid_setting(key, value) for key, value in settings.items()
    ):
        return False
    if "platform" not in document:
        return True
    platform = document["platform"]
    scoped = document["platformSettings"]
    return (
        isinstance(platform, str)
        and platform in PLATFORMS
        and isinstance(scoped, dict)
        and all(valid_platform_setting(platform, key, value) for key, value in scoped.items())
    )


async def parse_settings_link(request: Request) -> str:
    body = await read_bounded_body(request, MAX_PAYLOAD_BYTES)
    try:
        document = json.loads(body.decode("utf-8"))
        if valid_document(document):
            return json.dumps(document, ensure_ascii=False, separators=(",", ":"))
    except (ValueError, RecursionError):
        pass
    raise HTTPException(422, "invalid_settings_link")
