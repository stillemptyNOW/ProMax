import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallLighting {
  const CallLighting({
    this.color = Colors.white,
    this.brightness = 0.75,
    this.width = 24,
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
    return CallLighting(
      color: Color(prefs.getInt('call_light_color') ?? 0xffffffff),
      brightness: (prefs.getDouble('call_light_brightness') ?? 0.75).clamp(
        0.1,
        1,
      ),
      width: (prefs.getDouble('call_light_width') ?? 24).clamp(4, 100),
      opacity: (prefs.getDouble('call_light_opacity') ?? 1).clamp(0.1, 1),
      radius: (prefs.getDouble('call_light_radius') ?? 36).clamp(0, 100),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('call_light_color', color.toARGB32());
    await prefs.setDouble('call_light_brightness', brightness);
    await prefs.setDouble('call_light_width', width);
    await prefs.setDouble('call_light_opacity', opacity);
    await prefs.setDouble('call_light_radius', radius);
  }
}
