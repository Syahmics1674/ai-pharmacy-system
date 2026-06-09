import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final Color? color;

  const StatusChip({
    super.key,
    required this.label,
    this.color,
  });

  factory StatusChip.success(String label) {
    return StatusChip(label: label, color: AppColors.success);
  }

  factory StatusChip.warning(String label) {
    return StatusChip(label: label, color: AppColors.warning);
  }

  factory StatusChip.danger(String label) {
    return StatusChip(label: label, color: AppColors.danger);
  }

  factory StatusChip.info(String label) {
    return StatusChip(label: label, color: AppColors.primary);
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: c,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
