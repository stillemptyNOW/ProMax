import 'package:flutter/material.dart';

import '../../../core/config/call_lighting.dart';
import '../../widgets/color_wheel_picker.dart';

class CallLightingSheet extends StatefulWidget {
  const CallLightingSheet({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final CallLighting initial;
  final ValueChanged<CallLighting> onChanged;

  @override
  State<CallLightingSheet> createState() => _CallLightingSheetState();
}

class _CallLightingSheetState extends State<CallLightingSheet> {
  late CallLighting _value = widget.initial;

  void _change({
    Color? color,
    double? brightness,
    double? width,
    double? opacity,
    double? radius,
  }) {
    setState(
      () => _value = CallLighting(
        color: color ?? _value.color,
        brightness: brightness ?? _value.brightness,
        width: width ?? _value.width,
        opacity: opacity ?? _value.opacity,
        radius: radius ?? _value.radius,
      ),
    );
    widget.onChanged(_value);
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> change, {
    bool percent = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title: ${(percent ? value * 100 : value).round()}${percent ? '%' : ''}',
        ),
        Slider(value: value, min: min, max: max, onChanged: change),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Подсветка для селфи',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 200,
                child: ColorWheelPicker(
                  color: _value.color,
                  onChanged: (color) => _change(color: color),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _slider(
              'Яркость экрана',
              _value.brightness,
              0.1,
              1,
              (value) => _change(brightness: value),
              percent: true,
            ),
            _slider(
              'Ширина рамки',
              _value.width,
              4,
              100,
              (value) => _change(width: value),
            ),
            _slider(
              'Непрозрачность рамки',
              _value.opacity,
              0.1,
              1,
              (value) => _change(opacity: value),
              percent: true,
            ),
            _slider(
              'Скругление',
              _value.radius,
              0,
              100,
              (value) => _change(radius: value),
            ),
            OutlinedButton(
              onPressed: () => _change(
                color: Colors.white,
                brightness: 0.75,
                width: 24,
                opacity: 1,
                radius: 36,
              ),
              child: const Text('Вернуть белую подсветку · 75%'),
            ),
          ],
        ),
      ),
    );
  }
}
