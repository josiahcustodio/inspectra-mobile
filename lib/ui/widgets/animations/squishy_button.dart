import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SquishyButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const SquishyButton({super.key, this.onPressed, required this.child});

  @override
  State<SquishyButton> createState() => _SquishyButtonState();
}

class _SquishyButtonState extends State<SquishyButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final bool isClickable = widget.onPressed != null;

    return GestureDetector(
      onTapDown: isClickable
          ? (details) {
              HapticFeedback.lightImpact();
              _ctrl.forward();
            }
          : null,
      onTapUp: isClickable
          ? (details) {
              _ctrl.reverse();
              widget.onPressed!();
            }
          : null,
      onTapCancel: isClickable
          ? () {
              _ctrl.reverse();
            }
          : null,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
