import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String clinicName;
  final String? subtitle;
  final String? syncStatus;
  final bool isSyncing;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onClinicTap;

  const AppTopBar({
    super.key,
    required this.clinicName,
    this.subtitle,
    this.syncStatus,
    this.isSyncing = false,
    this.onSettingsTap,
    this.onNotificationTap,
    this.onClinicTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClinicTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.white).withValues(alpha: isDark ? 0.1 : 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_hospital_rounded,
                    size: 16,
                    color: isDark ? AppColors.primaryLight : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    clinicName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDark ? AppColors.textOnDark : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "AI-Assisted Pharmacy Inventory System",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? AppColors.textOnDark : Colors.white,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: (isDark ? AppColors.textDarkSecondary : Colors.white).withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (syncStatus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.successLight : Colors.white).withValues(alpha: isDark ? 0.12 : 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: isSyncing
                        ? const CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white)
                        : Icon(Icons.circle, size: 8, color: isDark ? AppColors.successLight : AppColors.success),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    syncStatus!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textOnDark : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          if (onNotificationTap != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              color: isDark ? AppColors.textOnDark : Colors.white,
              iconSize: 22,
              onPressed: onNotificationTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: "Notifications",
            ),
          ],
          if (onSettingsTap != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              color: isDark ? AppColors.textOnDark : Colors.white,
              iconSize: 22,
              onPressed: onSettingsTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: "Settings",
            ),
          ],
        ],
      ),
    );
  }
}
