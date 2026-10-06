import 'package:flutter/widgets.dart';

class WithTextController extends StatefulWidget {
  const WithTextController({
    super.key,
    this.initialText,
    required this.builder,
  });

  final String? initialText;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<WithTextController> createState() => _WithTextControllerState();
}

class _WithTextControllerState extends State<WithTextController> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
