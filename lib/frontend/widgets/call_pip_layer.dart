import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCVideoRenderer, RTCVideoViewObjectFit;

import '../../core/calls/call_pip.dart';
import 'call_video_view.dart';
import 'promax_avatar.dart';

class CallPipLayer extends StatelessWidget {
  const CallPipLayer({super.key, required this.child, this.pip});

  final Widget child;
  final CallPip? pip;

  @override
  Widget build(BuildContext context) {
    final controller = pip ?? CallPip.instance;
    return ListenableBuilder(
      listenable: controller,
      child: child,
      builder: (context, app) {
        final active = controller.active;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: active, child: app),
            if (active) CallPipView(pip: controller),
          ],
        );
      },
    );
  }
}

class CallPipView extends StatefulWidget {
  const CallPipView({super.key, required this.pip});

  final CallPip pip;

  @override
  State<CallPipView> createState() => _CallPipViewState();
}

class _CallPipViewState extends State<CallPipView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.pip.addListener(_attach);
    _renderer.addListener(_reportSize);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _renderer.initialize();
    if (!mounted) {
      await _renderer.dispose();
      return;
    }
    _ready = true;
    _attach();
  }

  void _attach() {
    if (!_ready || !mounted) return;
    final stream = widget.pip.videoStream;
    if (identical(_renderer.srcObject, stream)) return;
    _renderer.srcObject = stream;
    setState(() {});
  }

  void _reportSize() {
    widget.pip.reportVideoSize(_renderer.videoWidth, _renderer.videoHeight);
  }

  @override
  void dispose() {
    widget.pip.removeListener(_attach);
    _renderer.removeListener(_reportSize);
    if (_ready) {
      _renderer.srcObject = null;
      unawaited(_renderer.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.pip.presentation;
    final showVideo = _ready && _renderer.srcObject != null;
    final avatar = _CallPipAvatar(
      name: presentation?.name ?? '',
      avatarUrl: presentation?.avatarUrl,
    );
    return ColoredBox(
      color: Colors.black,
      child: showVideo
          ? CallVideoView(
              renderer: _renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              placeholder: avatar,
            )
          : avatar,
    );
  }
}

class _CallPipAvatar extends StatelessWidget {
  const _CallPipAvatar({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide * 0.5;
        return Center(
          child: ProMaxAvatar(
            name: name,
            imageUrl: avatarUrl,
            size: side.isFinite && side > 0 ? side : 48,
            fadeIn: false,
          ),
        );
      },
    );
  }
}
