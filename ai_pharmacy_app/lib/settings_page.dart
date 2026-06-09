import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'widgets/common/app_card.dart';
import 'widgets/common/app_section_header.dart';
import 'widgets/common/status_chip.dart';
import 'widgets/common/page_header.dart';
import 'config/api_config.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentTheme;
  final ValueChanged<ThemeMode> onThemeChanged;

  const SettingsPage({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _backendStatus = "Checking...";
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    try {
      final uri = Uri.parse("${ApiConfig.baseUrl}/api/sync/status");
      final response = await get(uri).timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _isOnline = response.statusCode == 200;
          _backendStatus = response.statusCode == 200 ? "Connected" : "Disconnected";
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isOnline = false; _backendStatus = "Disconnected"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PageHeader(
            title: "Settings",
            subtitle: "Configure system preferences and view application information",
            icon: Icons.settings_rounded,
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Theme", style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _themeOption("Light", ThemeMode.light, Icons.light_mode_rounded),
                const SizedBox(height: 4),
                _themeOption("Dark", ThemeMode.dark, Icons.dark_mode_rounded),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppSectionHeader(title: "Application", icon: Icons.info_outline_rounded),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                _infoRow("App Version", "1.0.0+1"),
                const Divider(height: 16),
                _infoRow("Backend Status", _backendStatus,
                  trailing: StatusChip(
                    label: _isOnline ? "Online" : "Offline",
                    color: _isOnline ? AppColors.success : AppColors.danger,
                  ),
                ),
                const Divider(height: 16),
                _infoRow("Sync Status", _isOnline ? "Active" : "Unavailable",
                  trailing: StatusChip(
                    label: _isOnline ? "Active" : "Inactive",
                    color: _isOnline ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppSectionHeader(title: "About", icon: Icons.medical_services_rounded),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("AI-Assisted Pharmacy Inventory System", style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(
                  "A smart inventory management system for Ministry of Health "
                  "clinics, leveraging artificial intelligence to optimize "
                  "pharmaceutical stock levels and reduce wastage.",
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow("Team", "Pharmacy Informatics Team"),
                const Divider(height: 16),
                _infoRow("Supervisor", "Dr. Sarah Chen"),
                const Divider(height: 16),
                _infoRow("Version", "1.0.0"),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.local_hospital_rounded,
                  size: 32,
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  "AI-Assisted Pharmacy Inventory System",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Version 1.0.0",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "© 2026 Pharmacy Informatics Team",
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _themeOption(String label, ThemeMode mode, IconData icon) {
    final active = widget.currentTheme == mode;
    return ListTile(
      leading: Icon(icon, color: active ? AppColors.primary : null),
      title: Text(label),
      trailing: active
          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 22)
          : const Icon(Icons.radio_button_unchecked, color: AppColors.textSecondary, size: 22),
      onTap: () {
        widget.onThemeChanged(mode);
        _saveThemePreference(mode);
      },
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 36,
      dense: true,
    );
  }

  Widget _infoRow(String label, String value, {Widget? trailing}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: trailing ?? Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveThemePreference(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("theme_mode", mode == ThemeMode.light ? "light" : mode == ThemeMode.dark ? "dark" : "system");
  }
}
