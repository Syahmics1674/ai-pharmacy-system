import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'config/api_config.dart';
import 'widgets/common/metric_card.dart';
import 'widgets/common/page_header.dart';
import 'widgets/common/status_badge.dart';
import 'widgets/common/empty_state.dart';
import 'widgets/common/section_card.dart';
import 'widgets/common/loading_state.dart';
import 'services/time_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';

String dashItemNameOf(dynamic item) {
  if (item is Map) {
    return (item['item_name'] ?? item['name'] ?? 'Unknown').toString();
  }
  return 'Unknown';
}

Future<Map<String, dynamic>> apiGet(String url) async {
  final response = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode == 200) {
    return json.decode(response.body) as Map<String, dynamic>;
  }
  throw Exception("HTTP ${response.statusCode}");
}

class DashboardPage extends StatefulWidget {
  final String clinicId;
  final VoidCallback? onNavigateInventory;
  final VoidCallback? onNavigateOperations;
  final VoidCallback? onNavigateOrders;
  final VoidCallback? onNavigateReports;

  const DashboardPage({
    super.key,
    required this.clinicId,
    this.onNavigateInventory,
    this.onNavigateOperations,
    this.onNavigateOrders,
    this.onNavigateReports,
  });

  @override
  State<DashboardPage> createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> {
  final String baseUrl = ApiConfig.baseUrl;
  bool isLoading = true;
  bool isLoadingSection2 = true;

  Map<String, dynamic> summary = {};
  List<dynamic> recentActivity = [];
  String insightMessage = "";
  List<dynamic> topProducts = [];

  @override
  void initState() {
    super.initState();
    fetchDashboardData();
  }

  Future<void> fetchDashboardData() async {
    setState(() => isLoading = true);
    try {
      final data = await apiGet("$baseUrl/dashboard/summary?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          summary = Map<String, dynamic>.from(data);
          recentActivity = List<dynamic>.from(data['recent_activity'] ?? []);
          insightMessage = data['insight_message'] ?? "";
          topProducts = List<dynamic>.from(data['top_products'] ?? []);
          isLoading = false;
          isLoadingSection2 = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingSection2 = false;
          summary = {"clinic_name": widget.clinicId, "greeting": "Hello", "error": "Could not load data"};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: fetchDashboardData,
          color: isDark ? AppColors.primaryLight : AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
            child: isLoading
                ? const LoadingState(message: "Loading dashboard...")
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGreetingHeader(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildSummaryCards(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildAlertsPanel(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildInsightPreview(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildQuickActions(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildInventoryHealth(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildRecentActivity(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingHeader() {
    final clinicName = summary['clinic_name'] ?? widget.clinicId;
    final greeting = summary['greeting'] ?? "Hello";
    final district = summary['district'] ?? "";
    final mytNow = TimeService.nowMYT();
    final headerTime = "${TimeService.formatDateLong(mytNow)}  •  ${TimeService.formatTime(mytNow)} MYT";

    return PageHeader(
      title: "$greeting, $clinicName",
      subtitle: district.isNotEmpty
          ? "$headerTime  •  District: $district"
          : headerTime,
      icon: Icons.dashboard_rounded,
      trailing: StatusBadge(
        label: "Active Online",
        style: BadgeStyle.success,
      ),
    );
  }

  Widget _buildSummaryCards() {
    final total = summary['total_medicines'] ?? 0;
    final lowStock = summary['low_stock_count'] ?? 0;
    final moderate = summary['moderate_count'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: "Total Medicines",
            value: "$total Items",
            icon: Icons.medication_liquid_rounded,
            color: AppColors.primary,
            onTap: widget.onNavigateInventory,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: MetricCard(
            label: "Low Stock Alerts",
            value: "$lowStock Items",
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
            onTap: widget.onNavigateInventory,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: MetricCard(
            label: "Moderate Stock",
            value: "$moderate Items",
            icon: Icons.remove_circle_outline_rounded,
            color: AppColors.warning,
            onTap: widget.onNavigateInventory,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertsPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lowStock = summary['low_stock_count'] ?? 0;
    final moderate = summary['moderate_count'] ?? 0;
    final adequate = summary['adequate_count'] ?? 0;
    final pendingOrders = summary['pending_orders_count'] ?? 0;

    final alerts = <Map<String, dynamic>>[];
    if (lowStock > 0) {
      alerts.add({
        "icon": Icons.inventory_2_rounded,
        "label": "$lowStock medicines are running critically low",
        "color": AppColors.danger,
      });
    }
    if (moderate > 0) {
      alerts.add({
        "icon": Icons.warning_rounded,
        "label": "$moderate medicines at moderate stock levels",
        "color": AppColors.warning,
      });
    }
    if (adequate > 0) {
      alerts.add({
        "icon": Icons.check_circle_rounded,
        "label": "$adequate medicines are adequately stocked",
        "color": AppColors.success,
      });
    }
    if (pendingOrders > 0) {
      alerts.add({
        "icon": Icons.local_shipping_rounded,
        "label": "$pendingOrders pending procurement orders active",
        "color": AppColors.primary,
      });
    }

    return SectionCard(
      title: "System Alerts & Notifications",
      icon: Icons.notifications_active_rounded,
      trailing: alerts.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "${alerts.length} Alerts",
                style: const TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      child: alerts.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: "All systems healthy",
              subtitle: "All inventory systems running within safe thresholds",
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alerts.length,
              itemBuilder: (context, idx) {
                final a = alerts[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: a['color'].withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: a['color'].withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(a['icon'], size: 18, color: a['color']),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            a['label'],
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInsightPreview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (insightMessage.isEmpty && topProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: "AI Inventory Analytics",
      icon: Icons.auto_awesome_rounded,
      accentColor: isDark ? AppColors.primaryLight : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (insightMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      insightMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (topProducts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              "Top Dispensed Products (Last 3 Months)",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ..._buildTopProducts(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTopProducts() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int maxUsed = 1;
    for (var p in topProducts) {
      final count = p['total_used'] ?? 0;
      if (count is int && count > maxUsed) {
        maxUsed = count;
      }
    }
    return topProducts.take(3).map((p) {
      final name = dashItemNameOf(p);
      final count = p['total_used'] ?? 0;
      final ratio = (count is int ? count.toDouble() : 0.0) / maxUsed;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 14, color: AppColors.success),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  "$count units",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.05, 1.0),
                  backgroundColor: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildQuickActions() {
    return SectionCard(
      title: "Quick Navigation Hub",
      icon: Icons.explore_rounded,
      child: Row(
        children: [
          Expanded(
            child: _actionButton(
              "Inventory",
              Icons.inventory_2_outlined,
              AppColors.primary,
              widget.onNavigateInventory ?? () {},
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _actionButton(
              "Add Stock",
              Icons.add_box_outlined,
              AppColors.success,
              widget.onNavigateOperations ?? () {},
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _actionButton(
              "Orders",
              Icons.shopping_cart_outlined,
              AppColors.warning,
              widget.onNavigateOrders ?? () {},
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _actionButton(
              "AI Insights",
              Icons.auto_graph_outlined,
              AppColors.primary,
              widget.onNavigateReports ?? () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryHealth() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final health = summary['inventory_health'] as Map<String, dynamic>? ?? {};
    final low = health['low'] ?? 0;
    final moderate = health['moderate'] ?? 0;
    final adequate = health['adequate'] ?? 0;
    final total = low + moderate + adequate;

    if (total == 0) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: "Inventory Health Index",
      icon: Icons.monitor_heart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (adequate > 0)
                    Expanded(
                      flex: adequate,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.success, AppColors.successDark],
                          ),
                        ),
                      ),
                    ),
                  if (moderate > 0)
                    Expanded(
                      flex: moderate,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.warning, AppColors.warningDark],
                          ),
                        ),
                      ),
                    ),
                  if (low > 0)
                    Expanded(
                      flex: low,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.danger, AppColors.dangerDark],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _healthLegend("Adequate Stock", adequate, AppColors.success),
          Divider(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            height: AppSpacing.md,
          ),
          _healthLegend("Moderate Stock", moderate, AppColors.warning),
          Divider(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            height: AppSpacing.md,
          ),
          _healthLegend("Low Stock warning", low, AppColors.danger),
        ],
      ),
    );
  }

  Widget _healthLegend(String label, int count, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Text(
            "$count items",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    return SectionCard(
      title: "Recent Operation Logs",
      icon: Icons.history_toggle_off_rounded,
      child: recentActivity.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_rounded,
              title: "No recent activity",
              subtitle: "No operations logged in the past 24 hours",
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentActivity.take(10).length,
              itemBuilder: (context, idx) {
                final entry = recentActivity[idx];
                final isLast = idx == recentActivity.take(10).length - 1;
                return _activityTimelineTile(entry, isLast);
              },
            ),
    );
  }

  Widget _activityTimelineTile(Map<String, dynamic> entry, bool isLast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final type = entry['type'] ?? "";
    final itemName = dashItemNameOf(entry);
    final ts = entry['timestamp'] ?? "";
    IconData icon;
    Color color;
    String description;
    final quantity = entry['quantity'] ?? 0;

    if (type == "stock_in") {
      icon = Icons.add_circle_outline_rounded;
      color = AppColors.success;
      description = "Restocked $quantity × $itemName";
    } else if (type == "stock_out") {
      icon = Icons.remove_circle_outline_rounded;
      color = AppColors.warning;
      description = "Dispensed $quantity × $itemName";
    } else if (type == "order") {
      final status = entry['status'] ?? "PENDING";
      icon = Icons.receipt_long_rounded;
      color = status == "RECEIVED" ? AppColors.success : AppColors.primary;
      description = "Procurement Order $status";
    } else {
      icon = Icons.circle_outlined;
      color = AppColors.textSecondary;
      description = itemName;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (ts.isNotEmpty)
                    Text(
                      TimeService.formatRelative(ts),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
