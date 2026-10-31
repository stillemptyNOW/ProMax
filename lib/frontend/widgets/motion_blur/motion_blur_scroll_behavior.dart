import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'motion_blur_box.dart';

class MotionBlurScrollBehavior implements ScrollBehavior {
  const MotionBlurScrollBehavior(this.inner, {this.preview = false});

  final ScrollBehavior inner;
  final bool preview;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => MotionBlurBox.scroll(
    preview: preview,
    child: inner.buildOverscrollIndicator(context, child, details),
  );

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => inner.buildScrollbar(context, child, details);

  @override
  ScrollBehavior copyWith({
    bool? scrollbars,
    bool? overscroll,
    Set<PointerDeviceKind>? dragDevices,
    MultitouchDragStrategy? multitouchDragStrategy,
    Set<LogicalKeyboardKey>? pointerAxisModifiers,
    ScrollPhysics? physics,
    TargetPlatform? platform,
    ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior,
  }) => MotionBlurScrollBehavior(
    inner.copyWith(
      scrollbars: scrollbars,
      overscroll: overscroll,
      dragDevices: dragDevices,
      multitouchDragStrategy: multitouchDragStrategy,
      pointerAxisModifiers: pointerAxisModifiers,
      physics: physics,
      platform: platform,
      keyboardDismissBehavior: keyboardDismissBehavior,
    ),
    preview: preview,
  );

  @override
  Set<PointerDeviceKind> get dragDevices => inner.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      inner.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      inner.getMultitouchDragStrategy(context);

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      inner.getPlatform(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      inner.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => inner.getKeyboardDismissBehavior(context);

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      inner.velocityTrackerBuilder(context);

  @override
  bool shouldNotify(covariant ScrollBehavior oldDelegate) =>
      oldDelegate is! MotionBlurScrollBehavior ||
      oldDelegate.preview != preview ||
      oldDelegate.inner.runtimeType != inner.runtimeType ||
      inner.shouldNotify(oldDelegate.inner);

  @override
  String toString() => 'MotionBlurScrollBehavior($inner)';
}
