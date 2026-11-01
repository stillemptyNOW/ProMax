import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../core/config/app_performance.dart';

class AmbientClock {
  AmbientClock({
    required TickerProvider vsync,
    required this.onTick,
    double frameRate = EffectBudget.uncapped,
  }) : _frameRate = frameRate {
    _ticker = vsync.createTicker(_handleTick);
  }

  final void Function(Duration elapsed) onTick;
  late final Ticker _ticker;
  final Stopwatch _watch = Stopwatch();
  Timer? _wait;
  bool _running = false;
  double _frameRate;

  bool get isRunning => _running;

  double get frameRate => _frameRate;

  set frameRate(double value) {
    if (value == _frameRate) return;
    _frameRate = value;
    if (!_running) return;
    _wait?.cancel();
    _wait = null;
    if (!_ticker.isActive) _ticker.start();
  }

  static Duration pauseBetweenFrames(double frameRate, double displayRate) {
    if (frameRate <= 0 || frameRate >= displayRate) return Duration.zero;
    final period = 1 / frameRate;
    final vsync = 1 / displayRate;
    final wait = period - vsync * 0.75;
    return Duration(
      microseconds: (wait * Duration.microsecondsPerSecond).round(),
    );
  }

  void start() {
    if (_running) return;
    _running = true;
    _watch.start();
    if (!_ticker.isActive) _ticker.start();
  }

  void stop() {
    _running = false;
    _wait?.cancel();
    _wait = null;
    _watch.stop();
    if (_ticker.isActive) _ticker.stop();
  }

  void dispose() {
    stop();
    _ticker.dispose();
  }

  void _handleTick(Duration _) {
    onTick(_watch.elapsed);
    if (!_running) return;
    final pause = pauseBetweenFrames(
      _frameRate,
      AppPerformance.displayRefreshRate(),
    );
    if (pause == Duration.zero) return;
    _ticker.stop();
    _wait = Timer(pause, () {
      _wait = null;
      if (_running && !_ticker.isActive) _ticker.start();
    });
  }
}
