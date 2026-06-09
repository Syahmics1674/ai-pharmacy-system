import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class InfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? color;
  final String? label;
  final Widget? trailing;

  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color,
    this.label,
    this.trailing,
  });

  factory InfoBanner.success({
    required String message,
    String? label,
    Widget? trailing,
  }) {
    return InfoBanner(
      message: message,
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.success,
      label: label,
      trailing: trailing,
    );
  }

  factory InfoBanner.warning({
    required String message,
    String? label,
    Widget? trailing,
  }) {
    return InfoBanner(
      message: message,
      icon: Icons.warning_amber_rounded,
      color: AppColors.warning,
      label: label,
      trailing: trailing,
    );
  }

  factory InfoBanner.error({
    required String message,
    String? label,
    Widget? trailing,
  }) {
    return InfoBanner(
      message: message,
      icon: Icons.error_outline_rounded,
      color: AppColors.danger,
      label: label,
      trailing: trailing,
    );
  }

  factory InfoBanner.info({
    required String message,
    String? label,
    Widget? trailing,
  }) {
    return InfoBanner(
      message: message,
      icon: Icons.info_outline_rounded,
      color: AppColors.primary,
      label: label,
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: c,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label!,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c),
                ),
              ),
            ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
