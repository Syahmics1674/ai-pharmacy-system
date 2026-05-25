import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  final String baseUrl = "http://localhost:5000";
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
    if (isLoading) {
      return RefreshIndicator(
        onRefresh: fetchDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(height: 160),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _shimmerBox(height: 100)),
                const SizedBox(width: 10),
                Expanded(child: _shimmerBox(height: 100)),
              ]),
              const SizedBox(height: 20),
              _shimmerBox(height: 120),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: fetchDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreetingHeader(),
            const SizedBox(height: 20),
            _buildSummaryCards(),
            const SizedBox(height: 20),
            _buildAlertsPanel(),
            const SizedBox(height: 20),
            _buildInsightPreview(),
            const SizedBox(height: 20),
            _buildQuickActions(),
            const SizedBox(height: 20),
            _buildInventoryHealth(),
            const SizedBox(height: 20),
            _buildRecentActivity(),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox({double height = 100}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildGreetingHeader() {
    final clinicName = summary['clinic_name'] ?? widget.clinicId;
    final greeting = summary['greeting'] ?? "Hello";
    final currentDate = summary['current_date'] ?? "";
    final currentDay = summary['current_day'] ?? "";
    final currentTime = summary['current_time'] ?? "";
    final district = summary['district'] ?? "";
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueAccent, Colors.blue.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
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
                        "$greeting, $clinicName",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (district.isNotEmpty)
                        Text(
                          "District: $district",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.greenAccent),
                      SizedBox(width: 6),
                      Text(
                        "Online",
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _confirmLogout(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.logout, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.white.withOpacity(0.7)),
                const SizedBox(width: 6),
                Text(
                  "$currentDay, $currentDate",
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                ),
                const SizedBox(width: 20),
                Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.7)),
                const SizedBox(width: 6),
                Text(
                  currentTime,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final total = summary['total_medicines'] ?? 0;
    final lowStock = summary['low_stock_count'] ?? 0;
    final expiringSoon = summary['expiring_soon_count'] ?? 0;
    final pendingOrders = summary['pending_orders_count'] ?? 0;

    return Row(
      children: [
        Expanded(child: _summaryCard("Total\nMedicines", "$total", Colors.blue, Icons.medication)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard("Low\nStock", "$lowStock", Colors.orange, Icons.warning_amber)),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsPanel() {
    final lowStock = summary['low_stock_count'] ?? 0;
    final expiringSoon = summary['expiring_soon_count'] ?? 0;
    final expired = summary['expired_count'] ?? 0;
    final pendingOrders = summary['pending_orders_count'] ?? 0;

    final alerts = <Map<String, dynamic>>[];
    if (lowStock > 0) {
      alerts.add({
        "icon": Icons.inventory,
        "label": "$lowStock items low on stock",
        "color": Colors.orange,
        "bg": Colors.orange.withOpacity(0.1),
      });
    }
    if (expiringSoon > 0) {
      alerts.add({
        "icon": Icons.schedule,
        "label": "$expiringSoon items expiring soon",
        "color": Colors.red,
        "bg": Colors.red.withOpacity(0.1),
      });
    }
    if (expired > 0) {
      alerts.add({
        "icon": Icons.dangerous,
        "label": "$expired items expired",
        "color": Colors.red.shade700,
        "bg": Colors.red.shade50,
      });
    }
    if (pendingOrders > 0) {
      alerts.add({
        "icon": Icons.shopping_cart,
        "label": "$pendingOrders pending orders",
        "color": Colors.blue,
        "bg": Colors.blue.withOpacity(0.1),
      });
    }
    if (insightMessage.isNotEmpty) {
      alerts.add({
        "icon": Icons.auto_awesome,
        "label": insightMessage.length > 60
            ? "${insightMessage.substring(0, 60)}..."
            : insightMessage,
        "color": Colors.purple,
        "bg": Colors.purple.withOpacity(0.1),
      });
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, size: 20, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Text(
                  "Notifications & Alerts",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text("All clear - no alerts", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              ...alerts.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: a['bg'],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(a['icon'], size: 18, color: a['color']),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              a['label'],
                              style: TextStyle(
                                fontSize: 13,
                                color: a['color'],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightPreview() {
    if (insightMessage.isEmpty && topProducts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [Colors.indigo.shade50, Colors.purple.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 20, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  "AI Insights Preview",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (insightMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        insightMessage,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            if (topProducts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                "Top Dispensed Products",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...topProducts.take(3).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.trending_up, size: 14, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Text(
                          dashItemNameOf(p),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          "${p['total_used'] ?? 0} used",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Quick Actions",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    "View Inventory",
                    Icons.inventory,
                    Colors.blue,
                    widget.onNavigateInventory ?? () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    "Add Stock",
                    Icons.add_circle,
                    Colors.green,
                    widget.onNavigateOperations ?? () {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    "Orders",
                    Icons.shopping_cart,
                    Colors.orange,
                    widget.onNavigateOrders ?? () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    "Reports",
                    Icons.bar_chart,
                    Colors.purple,
                    widget.onNavigateReports ?? () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout?.call();
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryHealth() {
    final health = summary['inventory_health'] as Map<String, dynamic>? ?? {};
    final healthy = health['healthy'] ?? 0;
    final low = health['low'] ?? 0;
    final expired = health['expired'] ?? 0;
    final expiringSoon = health['expiring_soon'] ?? 0;
    final total = healthy + low + expired + expiringSoon;

    if (total == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Inventory Health",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    if (healthy > 0)
                      Expanded(
                        flex: healthy,
                        child: Container(color: Colors.green),
                      ),
                    if (low > 0)
                      Expanded(
                        flex: low,
                        child: Container(color: Colors.orange),
                      ),
                    if (expiringSoon > 0)
                      Expanded(
                        flex: expiringSoon,
                        child: Container(color: Colors.red.shade300),
                      ),
                    if (expired > 0)
                      Expanded(
                        flex: expired,
                        child: Container(color: Colors.red.shade700),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _healthLegend("Healthy", healthy, Colors.green),
            _healthLegend("Low Stock", low, Colors.orange),
            _healthLegend("Expiring Soon", expiringSoon, Colors.red.shade300),
            _healthLegend("Expired", expired, Colors.red.shade700),
          ],
        ),
      ),
    );
  }

  Widget _healthLegend(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(
            "$count",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Text(
                  "Recent Activity",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentActivity.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox, size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text(
                        "No recent activity",
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...recentActivity.take(10).map((a) => _activityTile(a)),
          ],
        ),
      ),
    );
  }

  Widget _activityTile(Map<String, dynamic> entry) {
    final type = entry['type'] ?? "";
    final itemName = dashItemNameOf(entry);
    final ts = entry['timestamp'] ?? "";
    IconData icon;
    Color color;
    String description;
    final quantity = entry['quantity'] ?? 0;

    if (type == "stock_in") {
      icon = Icons.add_circle_outline;
      color = Colors.green;
      description = "Added $quantity × $itemName";
    } else if (type == "stock_out") {
      icon = Icons.remove_circle_outline;
      color = Colors.orange;
      description = "Used $quantity × $itemName";
    } else if (type == "order") {
      final status = entry['status'] ?? "PENDING";
      icon = Icons.receipt_long;
      color = status == "RECEIVED" ? Colors.green : Colors.blue;
      description = "Order $status";
    } else {
      icon = Icons.circle;
      color = Colors.grey;
      description = itemName;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (ts.isNotEmpty)
                  Text(
                    _formatTimestamp(ts),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
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
