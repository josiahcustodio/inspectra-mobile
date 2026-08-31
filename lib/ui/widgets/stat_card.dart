import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const StatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glassDecoration(Theme.of(context).colorScheme.surface),
      child: Stack(
        children: [
          // Micro-trend line in the background
          Positioned(
            right: 0,
            bottom: 24,
            left: 40,
            height: 30,
            child: Opacity(
              opacity: 0.15,
              child: CustomPaint(
                painter: _TrendLinePainter(iconColor),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: iconColor.withAlpha(30)),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.trending_up_rounded, color: AppTheme.primary, size: 16),
                        const SizedBox(width: 4),
                        const Text(
                          '+12%',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: '.SF Pro Text',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  final Color color;
  _TrendLinePainter(this.color);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
      
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width * 0.2, size.height * 0.8, size.width * 0.4, size.height * 0.7)
      ..quadraticBezierTo(size.width * 0.6, size.height * 0.5, size.width * 0.8, size.height * 0.3)
      ..lineTo(size.width, 0);
      
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
