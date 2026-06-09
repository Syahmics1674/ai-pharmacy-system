import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

enum BadgeStyle {
  lowStock,
  moderate,
  healthy,
  pending,
  submitted,
  completed,
  high,
  medium,
  low,
  info,
  warning,
  danger,
  success,
}

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeStyle style;
  final double fontSize;
  final bool showDot;

  const StatusBadge({
    super.key,
    required this.label,
    this.style = BadgeStyle.info,
    this.fontSize = 11,
    this.showDot = true,
  });

  factory StatusBadge.lowStock(String label) {
    return StatusBadge(label: label, style: BadgeStyle.lowStock);
  }

  factory StatusBadge.moderate(String label) {
    return StatusBadge(label: label, style: BadgeStyle.moderate);
  }

  factory StatusBadge.healthy(String label) {
    return StatusBadge(label: label, style: BadgeStyle.healthy);
  }

  factory StatusBadge.pending(String label) {
    return StatusBadge(label: label, style: BadgeStyle.pending);
  }

  factory StatusBadge.submitted(String label) {
    return StatusBadge(label: label, style: BadgeStyle.submitted);
  }

  factory StatusBadge.completed(String label) {
    return StatusBadge(label: label, style: BadgeStyle.completed);
  }

  factory StatusBadge.high(String label) {
    return StatusBadge(label: label, style: BadgeStyle.high);
  }

  factory StatusBadge.medium(String label) {
    return StatusBadge(label: label, style: BadgeStyle.medium);
  }

  factory StatusBadge.low(String label) {
    return StatusBadge(label: label, style: BadgeStyle.low);
  }

  Color get _color {
    switch (style) {
      case BadgeStyle.lowStock:
      case BadgeStyle.high:
      case BadgeStyle.danger:
        return AppColors.danger;
      case BadgeStyle.moderate:
      case BadgeStyle.medium:
      case BadgeStyle.warning:
        return AppColors.warning;
      case BadgeStyle.healthy:
      case BadgeStyle.completed:
      case BadgeStyle.success:
        return AppColors.success;
      case BadgeStyle.pending:
      case BadgeStyle.submitted:
        return AppColors.primary;
      case BadgeStyle.low:
      case BadgeStyle.info:
        return AppColors.textSecondary;
    }
  }

  IconData get _icon {
    switch (style) {
      case BadgeStyle.lowStock:
      case BadgeStyle.danger:
        return Icons.error_outline_rounded;
      case BadgeStyle.moderate:
      case BadgeStyle.warning:
        return Icons.warning_amber_rounded;
      case BadgeStyle.healthy:
      case BadgeStyle.success:
        return Icons.check_circle_outline_rounded;
      case BadgeStyle.pending:
        return Icons.schedule_rounded;
      case BadgeStyle.submitted:
        return Icons.send_rounded;
      case BadgeStyle.completed:
        return Icons.task_alt_rounded;
      case BadgeStyle.high:
        return Icons.priority_high_rounded;
      case BadgeStyle.medium:
        return Icons.remove_circle_outline_rounded;
      case BadgeStyle.low:
        return Icons.lens_rounded;
      case BadgeStyle.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot)
            Icon(_icon, size: 12, color: c),
          if (showDot) const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: c,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
