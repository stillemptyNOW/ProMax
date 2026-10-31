import 'package:flutter/widgets.dart';

import '../../../core/plugins/motion_blur/motion_blur_settings.dart';
import 'motion_blur_box.dart';

class MotionBlurRouteContent extends StatelessWidget {
  const MotionBlurRouteContent({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) => MotionBlurBox(
    target: MotionBlurTarget.transitions,
    motion: [animation, secondaryAnimation],
    child: child,
  );
}

class MotionBlurPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionBlurPageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    MotionBlurRouteContent(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    ),
  );
}
