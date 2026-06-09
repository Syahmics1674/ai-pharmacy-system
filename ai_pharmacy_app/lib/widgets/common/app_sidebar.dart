import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class AppSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final String clinicName;
  final String clinicDistrict;
  final VoidCallback? onLogout;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.collapsed = false,
    this.onToggleCollapse,
    this.clinicName = "",
    this.clinicDistrict = "",
    this.onLogout,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _widthAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _widthAnimation = Tween<double>(begin: 72, end: 220).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );
    if (!widget.collapsed) {
      _animController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != oldWidget.collapsed) {
      if (widget.collapsed) {
        _animController.reverse();
      } else {
        _animController.forward();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  static const items = <_NavItem>[
    _NavItem(Icons.dashboard_rounded, "Dashboard"),
    _NavItem(Icons.inventory_2_rounded, "Inventory"),
    _NavItem(Icons.swap_horiz_rounded, "Operations"),
    _NavItem(Icons.insights_rounded, "AI Insights"),
    _NavItem(Icons.shopping_cart_rounded, "Orders"),
    _NavItem(Icons.settings_rounded, "Settings"),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        final collapsed = _widthAnimation.value < 146;
        return Container(
          width: _widthAnimation.value,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(right: BorderSide(color: borderColor, width: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 4,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (!collapsed) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.local_hospital_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "AI Pharmacy",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ] else
                      const SizedBox(width: 8),
                    if (widget.onToggleCollapse != null)
                      IconButton(
                        icon: Icon(
                          collapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                          size: 20,
                          color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                        ),
                        onPressed: widget.onToggleCollapse,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...List.generate(items.length, (i) {
                final item = items[i];
                final active = widget.selectedIndex == i;
                return _NavItemTile(
                  item: item,
                  active: active,
                  collapsed: collapsed,
                  onTap: () => widget.onItemSelected(i),
                );
              }),
              const Spacer(),
              if (!collapsed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: borderColor, width: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.local_hospital_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.clinicName.isNotEmpty ? widget.clinicName : "Clinic",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.clinicDistrict.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.clinicDistrict,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        "AI-Assisted Pharmacy Inventory System  v1.0.0",
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onLogout,
                          icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.redAccent),
                          label: const Text(
                            "Logout",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (collapsed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                        onPressed: widget.onLogout,
                        tooltip: "Logout",
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _NavItemTile extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavItemTile({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primary;
    final inactiveColor = isDark ? AppColors.textDarkSecondary : AppColors.textSecondary;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 2, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active
              ? activeColor.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            if (active && !collapsed)
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            if (active && !collapsed) const SizedBox(width: 9),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: collapsed ? 0 : 12,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: active ? activeColor : inactiveColor,
                        ),
                        if (!collapsed) ...[
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? activeColor : inactiveColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
