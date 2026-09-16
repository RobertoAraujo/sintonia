import 'package:flutter/material.dart';

enum BadgeStyle { filled, outlined, subtle }

class StatusBadgeWidget extends StatelessWidget {
  final String label;
  final Color color;
  final BadgeStyle style;
  final double fontSize;

  const StatusBadgeWidget({
    super.key,
    required this.label,
    required this.color,
    this.style = BadgeStyle.subtle,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Border? border;

    switch (style) {
      case BadgeStyle.filled:
        bgColor = color;
        textColor = Colors.white;
        border = null;
        break;
      case BadgeStyle.outlined:
        bgColor = Colors.transparent;
        textColor = color;
        border = Border.all(color: color, width: 1.5);
        break;
      case BadgeStyle.subtle:
        bgColor = color.withAlpha(31);
        textColor = color;
        border = null;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100),
        border: border,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
