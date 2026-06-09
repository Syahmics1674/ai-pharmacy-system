import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class MetricCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double? valueFontSize;
  final String? subtitle;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.valueFontSize,
    this.subtitle,
  });

  @override
  State<MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<MetricCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = widget.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? color.withValues(alpha: 0.4)
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: _isHovered ? 1.5 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? Colors.black.withValues(alpha: isDark ? 0.25 : 0.08)
                  : Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: _isHovered ? 16 : 10,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: color, size: 22),
                      ),
                      const Spacer(),
                      if (widget.onTap != null)
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.value,
                    style: TextStyle(
                      fontSize: widget.valueFontSize ?? 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
