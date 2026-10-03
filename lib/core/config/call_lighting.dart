import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallLighting {
  const CallLighting({
    this.color = Colors.white,
    this.brightness = 0.75,
    this.width = 64,
    this.opacity = 1,
    this.radius = 36,
  });

  final Color color;
  final double brightness;
  final double width;
  final double opacity;
  final double radius;

  static Future<CallLighting> load() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyDefault =
        prefs.getBool('call_light_wide_default') != true &&
        prefs.getDouble('call_light_width') == 24 &&
        (prefs.getInt('call_light_color') ?? 0xffffffff) == 0xffffffff &&
        (prefs.getDouble('call_light_brightness') ?? 0.75) == 0.75 &&
        (prefs.getDouble('call_light_opacity') ?? 1) == 1 &&
        (prefs.getDouble('call_light_radius') ?? 36) == 36;
    if (legacyDefault) await prefs.setDouble('call_light_width', 64);
    await prefs.setBool('call_light_wide_default', true);
    return CallLighting(
      color: Color(prefs.getInt('call_light_color') ?? 0xffffffff),
      brightness: (prefs.getDouble('call_light_brightness') ?? 0.75).clamp(
        0.1,
        1,
      ),
      width: (prefs.getDouble('call_light_width') ?? 64).clamp(4, 100),
      opacity: (prefs.getDouble('call_light_opacity') ?? 1).clamp(0.1, 1),
      radius: (prefs.getDouble('call_light_radius') ?? 36).clamp(0, 100),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_light_wide_default', true);
    await prefs.setInt('call_light_color', color.toARGB32());
    await prefs.setDouble('call_light_brightness', brightness);
    await prefs.setDouble('call_light_width', width);
    await prefs.setDouble('call_light_opacity', opacity);
    await prefs.setDouble('call_light_radius', radius);
  }
}
