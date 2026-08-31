import 'package:flutter/material.dart';

class DelayedEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const DelayedEntrance({
    super.key,
    required this.child,
    required this.delay,
  });

  @override
  State<DelayedEntrance> createState() => _DelayedEntranceState();
}

class _DelayedEntranceState extends State<DelayedEntrance> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slide = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );

    Future.delayed(delayWithFudgeFactor(), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  Duration delayWithFudgeFactor() {
    // Add a very small offset to guarantee rendering timeline
    return widget.delay + const Duration(milliseconds: 50);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _slide.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
