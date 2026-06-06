import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'config/api_config.dart';

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
  final VoidCallback? onLogout;
  final VoidCallback? onNavigateInventory;
  final VoidCallback? onNavigateOperations;
  final VoidCallback? onNavigateOrders;
  final VoidCallback? onNavigateReports;

  const DashboardPage({
    super.key,
    required this.clinicId,
    this.onLogout,
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF090D1A), Color(0xFF151C2C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: fetchDashboardData,
          backgroundColor: const Color(0xFF1E293B),
          color: Colors.cyanAccent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: isLoading
                ? _buildLoadingState()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGreetingHeader(),
                      const SizedBox(height: 24),
                      _buildSummaryCards(),
                      const SizedBox(height: 24),
                      _buildAlertsPanel(),
                      const SizedBox(height: 24),
                      _buildInsightPreview(),
                      const SizedBox(height: 24),
                      _buildQuickActions(),
                      const SizedBox(height: 24),
                      _buildInventoryHealth(),
                      const SizedBox(height: 24),
                      _buildRecentActivity(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _shimmerBox(height: 140, child: _buildGlowLogoLoading()),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 120)),
            const SizedBox(width: 16),
            Expanded(child: _shimmerBox(height: 120)),
          ],
        ),
        const SizedBox(height: 24),
        _shimmerBox(height: 200),
        const SizedBox(height: 24),
        _shimmerBox(height: 150),
      ],
    );
  }

  Widget _buildGlowLogoLoading() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Analyzing Clinic Database...",
          style: TextStyle(
            color: Colors.cyanAccent.withOpacity(0.8),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _shimmerBox({double height = 100, Widget? child}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  Widget _buildGreetingHeader() {
    final clinicName = summary['clinic_name'] ?? widget.clinicId;
    final greeting = summary['greeting'] ?? "Hello";
    final currentDate = summary['current_date'] ?? "";
    final currentDay = summary['current_day'] ?? "";
    final currentTime = summary['current_time'] ?? "";
    final district = summary['district'] ?? "";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1E38).withOpacity(0.8),
            const Color(0xFF0F172A).withOpacity(0.8)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$greeting,",
                      style: TextStyle(
                        color: Colors.cyanAccent.shade200,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      clinicName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (district.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
                        ),
                        child: Text(
                          "District: $district",
                          style: TextStyle(
                            color: Colors.cyanAccent.shade100,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                        SizedBox(width: 6),
                        Text(
                          "Active Online",
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.redAccent.withOpacity(0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.2)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _confirmLogout(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 14),
                            SizedBox(width: 6),
                            Text(
                              "Logout",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 8),
              Text(
                "$currentDay, $currentDate",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(Icons.access_time_filled_rounded, size: 14, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 8),
              Text(
                currentTime,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final total = summary['total_medicines'] ?? 0;
    final lowStock = summary['low_stock_count'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            "Total Medicines",
            "$total Items",
            const Color(0xFF3B82F6),
            Icons.medication_liquid_rounded,
            widget.onNavigateInventory ?? () {},
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _summaryCard(
            "Low Stock Alerts",
            "$lowStock Items",
            const Color(0xFFEF4444),
            Icons.warning_amber_rounded,
            widget.onNavigateInventory ?? () {},
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertsPanel() {
    final lowStock = summary['low_stock_count'] ?? 0;
    final moderate = summary['moderate_count'] ?? 0;
    final adequate = summary['adequate_count'] ?? 0;
    final pendingOrders = summary['pending_orders_count'] ?? 0;

    final alerts = <Map<String, dynamic>>[];
    if (lowStock > 0) {
      alerts.add({
        "icon": Icons.inventory_2_rounded,
        "label": "$lowStock medicines are running critically low",
        "color": const Color(0xFFEF4444),
        "bg": const Color(0xFFEF4444).withOpacity(0.08),
        "border": const Color(0xFFEF4444).withOpacity(0.25),
      });
    }
    if (moderate > 0) {
      alerts.add({
        "icon": Icons.warning_rounded,
        "label": "$moderate medicines at moderate stock levels",
        "color": const Color(0xFFF59E0B),
        "bg": const Color(0xFFF59E0B).withOpacity(0.08),
        "border": const Color(0xFFF59E0B).withOpacity(0.25),
      });
    }
    if (adequate > 0) {
      alerts.add({
        "icon": Icons.check_circle_rounded,
        "label": "$adequate medicines are adequately stocked",
        "color": const Color(0xFF10B981),
        "bg": const Color(0xFF10B981).withOpacity(0.08),
        "border": const Color(0xFF10B981).withOpacity(0.25),
      });
    }
    if (pendingOrders > 0) {
      alerts.add({
        "icon": Icons.local_shipping_rounded,
        "label": "$pendingOrders pending procurement orders active",
        "color": const Color(0xFF3B82F6),
        "bg": const Color(0xFF3B82F6).withOpacity(0.08),
        "border": const Color(0xFF3B82F6).withOpacity(0.25),
      });
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded, size: 20, color: Colors.cyanAccent),
              const SizedBox(width: 10),
              const Text(
                "System Alerts & Notifications",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (alerts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${alerts.length} Alerts",
                    style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.15)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34D399), size: 18),
                  SizedBox(width: 10),
                  Text(
                    "All inventory systems running within safe thresholds",
                    style: TextStyle(color: Color(0xFF34D399), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alerts.length,
              itemBuilder: (context, idx) {
                final a = alerts[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: a['bg'],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: a['border']),
                    ),
                    child: Row(
                      children: [
                        Icon(a['icon'], size: 18, color: a['color']),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            a['label'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.9),
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
        ],
      ),
    );
  }

  Widget _buildInsightPreview() {
    if (insightMessage.isEmpty && topProducts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.purpleAccent.withOpacity(0.02),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.purpleAccent),
              const SizedBox(width: 10),
              const Text(
                "AI Inventory Analytics",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Text(
                "AI Preview",
                style: TextStyle(
                  color: Colors.purpleAccent.shade100,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (insightMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 20, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      insightMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (topProducts.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              "Top Dispensed Products (Last 3 Months)",
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...() {
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
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.trending_up_rounded, size: 14, color: Colors.greenAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "$count units",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.cyanAccent,
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
                            backgroundColor: Colors.white.withOpacity(0.04),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.purpleAccent),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              });
            }(),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Quick Navigation Hub",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  "Inventory",
                  Icons.inventory_2_outlined,
                  const Color(0xFF3B82F6),
                  widget.onNavigateInventory ?? () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  "Add Stock",
                  Icons.add_box_outlined,
                  const Color(0xFF10B981),
                  widget.onNavigateOperations ?? () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  "Orders",
                  Icons.shopping_cart_outlined,
                  const Color(0xFFF59E0B),
                  widget.onNavigateOrders ?? () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  "AI Insights",
                  Icons.auto_graph_outlined,
                  const Color(0xFF8B5CF6),
                  widget.onNavigateReports ?? () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.9),
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
    final health = summary['inventory_health'] as Map<String, dynamic>? ?? {};
    final low = health['low'] ?? 0;
    final moderate = health['moderate'] ?? 0;
    final adequate = health['adequate'] ?? 0;
    final total = low + moderate + adequate;

    if (total == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Inventory Health Index",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 16),
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                        ),
                      ),
                    ),
                  if (moderate > 0)
                    Expanded(
                      flex: moderate,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                        ),
                      ),
                    ),
                  if (low > 0)
                    Expanded(
                      flex: low,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _healthLegend("Adequate Stock", adequate, const Color(0xFF10B981)),
          Divider(color: Colors.white.withOpacity(0.04), height: 12),
          _healthLegend("Moderate Stock", moderate, const Color(0xFFF59E0B)),
          Divider(color: Colors.white.withOpacity(0.04), height: 12),
          _healthLegend("Low Stock warning", low, const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _healthLegend(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.2)),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_toggle_off_rounded, size: 20, color: Colors.cyanAccent),
              const SizedBox(width: 10),
              const Text(
                "Recent Operation Logs",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (recentActivity.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_rounded, size: 48, color: Colors.white.withOpacity(0.1)),
                    const SizedBox(height: 12),
                    Text(
                      "No operations logged in the past 24 hours",
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentActivity.take(10).length,
              itemBuilder: (context, idx) {
                final entry = recentActivity[idx];
                final isLast = idx == recentActivity.take(10).length - 1;
                return _activityTimelineTile(entry, isLast);
              },
            ),
        ],
      ),
    );
  }

  Widget _activityTimelineTile(Map<String, dynamic> entry, bool isLast) {
    final type = entry['type'] ?? "";
    final itemName = dashItemNameOf(entry);
    final ts = entry['timestamp'] ?? "";
    IconData icon;
    Color color;
    String description;
    final quantity = entry['quantity'] ?? 0;

    if (type == "stock_in") {
      icon = Icons.add_circle_outline_rounded;
      color = const Color(0xFF10B981);
      description = "Restocked $quantity × $itemName";
    } else if (type == "stock_out") {
      icon = Icons.remove_circle_outline_rounded;
      color = const Color(0xFFF59E0B);
      description = "Dispensed $quantity × $itemName";
    } else if (type == "order") {
      final status = entry['status'] ?? "PENDING";
      icon = Icons.receipt_long_rounded;
      color = status == "RECEIVED" ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
      description = "Procurement Order $status";
    } else {
      icon = Icons.circle_outlined;
      color = Colors.grey;
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
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (ts.isNotEmpty)
                    Text(
                      _formatTimestamp(ts),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.4),
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

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Confirm Logout", style: TextStyle(color: Colors.white)),
        content: Text(
          "Are you sure you want to logout from ${summary['clinic_name'] ?? widget.clinicId}?",
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout?.call();
            },
            child: const Text(
              "Logout",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String ts) {
    try {
      if (ts.contains(".")) ts = ts.split(".")[0];
      final dt = DateTime.parse(ts);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return "Just now";
      if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
      if (diff.inHours < 24) return "${diff.inHours}h ago";
      if (diff.inDays < 7) return "${diff.inDays}d ago";
      return "${dt.day}/${dt.month}/${dt.year}";
    } catch (_) {
      return ts;
    }
  }
}
