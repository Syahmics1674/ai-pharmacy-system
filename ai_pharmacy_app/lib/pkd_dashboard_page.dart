import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PKDDashboardPage extends StatefulWidget {
  final String district;

  const PKDDashboardPage({super.key, required this.district});

  @override
  State<PKDDashboardPage> createState() => _PKDDashboardPageState();
}

class _PKDDashboardPageState extends State<PKDDashboardPage> {
  final String baseUrl = "http://localhost:5000";

  bool isLoading = true;
  String errorMessage = "";
  Map<String, dynamic> summary = {};
  List<Map<String, dynamic>> routes = [];
  List<Map<String, dynamic>> clinics = [];
  List<String> alerts = [];

  @override
  void initState() {
    super.initState();
    refreshDashboard();
  }

  Future<void> refreshDashboard() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final districtQuery = Uri.encodeComponent(widget.district);
      final responses = await Future.wait([
        http.get(Uri.parse("$baseUrl/pkd_summary?district=$districtQuery")),
        http.get(
          Uri.parse("$baseUrl/pkd_clinic_analysis?district=$districtQuery"),
        ),
        http.get(
          Uri.parse("$baseUrl/pkd_route_analysis?district=$districtQuery"),
        ),
        http.get(Uri.parse("$baseUrl/pkd_alerts?district=$districtQuery")),
      ]);

      if (!mounted) return;

      final decoded = responses
          .map((response) => json.decode(response.body) as Map<String, dynamic>)
          .toList();

      if (responses.any((response) => response.statusCode != 200)) {
        final failedIndex = responses.indexWhere(
          (response) => response.statusCode != 200,
        );
        setState(() {
          isLoading = false;
          errorMessage =
              (decoded[failedIndex]["error"] ?? "Failed to load dashboard")
                  .toString();
        });
        return;
      }

      setState(() {
        summary = Map<String, dynamic>.from(decoded[0]);
        clinics = (decoded[1]["clinics"] as List<dynamic>? ?? [])
            .map((clinic) => Map<String, dynamic>.from(clinic as Map))
            .toList();
        routes = (decoded[2]["routes"] as List<dynamic>? ?? [])
            .map((route) => Map<String, dynamic>.from(route as Map))
            .toList();
        alerts = (decoded[3]["alerts"] as List<dynamic>? ?? [])
            .map((alert) => alert.toString())
            .toList();
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = "Unable to connect to backend";
      });
    }
  }

  List<FlSpot> buildTrendSpots(int currentValue, {int floor = 0}) {
    final safeCurrent = math.max(currentValue, floor);
    final previousOne = math.max(
      floor,
      safeCurrent - math.max(1, safeCurrent ~/ 3),
    );
    final previousTwo = math.max(
      floor,
      safeCurrent - math.max(1, safeCurrent ~/ 2),
    );

    return [
      FlSpot(0, previousTwo.toDouble()),
      FlSpot(1, previousOne.toDouble()),
      FlSpot(2, safeCurrent.toDouble()),
    ];
  }

  Color riskColor(String riskLevel) {
    switch (riskLevel) {
      case "HIGH":
        return const Color(0xFFFF6B6B);
      case "MEDIUM":
        return const Color(0xFFFFB347);
      default:
        return const Color(0xFF4CD97B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1320),
        appBar: AppBar(
          backgroundColor: const Color(0xFF172033),
          title: Text("PKD Dashboard - ${widget.district}"),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.lightBlueAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: "Overview", icon: Icon(Icons.dashboard_outlined)),
              Tab(text: "Clinics", icon: Icon(Icons.local_hospital_outlined)),
              Tab(text: "Routes", icon: Icon(Icons.route_outlined)),
              Tab(text: "Alerts", icon: Icon(Icons.warning_amber_rounded)),
            ],
          ),
        ),
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              )
            : errorMessage.isNotEmpty
            ? _buildErrorState()
            : RefreshIndicator(
                onRefresh: refreshDashboard,
                child: TabBarView(
                  children: [
                    _buildOverviewTab(),
                    _buildClinicsTab(),
                    _buildRoutesTab(),
                    _buildAlertsTab(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: refreshDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final highRisk = (summary["high_risk_clinics"] ?? 0).toString();
    final pending = (summary["pending_orders"] ?? 0).toString();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.admin_panel_settings,
                    color: Colors.lightBlueAccent,
                  ),
                  SizedBox(width: 10),
                  Text(
                    "District Monitoring",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Welcome PKD ${widget.district}",
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                "$highRisk clinics are currently marked HIGH risk, with $pending pending orders requiring attention.",
                style: const TextStyle(color: Colors.white60, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle("District Summary"),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.45,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildSummaryCard(
              title: "Total Clinics",
              value: (summary["total_clinics"] ?? 0).toString(),
              icon: Icons.local_hospital,
              color: Colors.lightBlueAccent,
            ),
            _buildSummaryCard(
              title: "HIGH Risk Clinics",
              value: (summary["high_risk_clinics"] ?? 0).toString(),
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFFF6B6B),
            ),
            _buildSummaryCard(
              title: "Pending Orders",
              value: (summary["pending_orders"] ?? 0).toString(),
              icon: Icons.pending_actions,
              color: const Color(0xFFFFB347),
            ),
            _buildSummaryCard(
              title: "Submitted Orders",
              value: (summary["submitted_orders"] ?? 0).toString(),
              icon: Icons.assignment_turned_in,
              color: const Color(0xFF4CD97B),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionTitle("Trend Overview"),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 2 : 1,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildChartCard(
              title: "Orders Trend",
              subtitle: "Recent submitted order activity",
              color: Colors.lightBlueAccent,
              spots: buildTrendSpots(summary["submitted_orders"] ?? 0),
            ),
            _buildChartCard(
              title: "High-Risk Trend",
              subtitle: "Recent district risk pressure",
              color: const Color(0xFFFF6B6B),
              spots: buildTrendSpots(summary["high_risk_clinics"] ?? 0),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClinicsTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle("Clinic Monitoring"),
        const SizedBox(height: 12),
        if (clinics.isEmpty)
          _buildEmptyCard("No clinics available for district analysis.")
        else
          ...clinics.map(_buildClinicCard),
      ],
    );
  }

  Widget _buildRoutesTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle("Route Analysis"),
        const SizedBox(height: 12),
        if (routes.isEmpty)
          _buildEmptyCard("No route analysis available for this district yet.")
        else
          ...routes.map(_buildRouteCard),
      ],
    );
  }

  Widget _buildAlertsTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle("AI Alerts"),
        const SizedBox(height: 12),
        if (alerts.isEmpty)
          _buildEmptyCard("No district alerts at the moment.")
        else
          ...alerts.map(_buildAlertCard),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF172033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Color color,
    required List<FlSpot> spots,
  }) {
    final maxY =
        spots
            .map((spot) => spot.y)
            .fold<double>(0, (current, value) => math.max(current, value)) +
        2;

    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF172033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 2,
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: Colors.white10, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const labels = ["Earlier", "Recent", "Now"];
                          final index = value.toInt().clamp(0, 2);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              labels[index],
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.14),
                      ),
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: color,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicCard(Map<String, dynamic> clinic) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF172033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    clinic["name"]?.toString() ??
                        clinic["clinic_id"].toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _buildRiskChip(clinic["risk_level"].toString()),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              clinic["clinic_id"]?.toString() ?? "",
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _buildMetaRow(
              icon: Icons.route_outlined,
              label: "Route",
              value: clinic["route_id"]?.toString() ?? "-",
              color: Colors.lightBlueAccent,
            ),
            _buildMetaRow(
              icon: Icons.event,
              label: "Next Order Date",
              value: clinic["next_order_date"]?.toString() ?? "-",
              color: const Color(0xFFFFB347),
            ),
            _buildMetaRow(
              icon: Icons.pending_actions,
              label: "Pending Orders",
              value: (clinic["pending_orders"] ?? 0).toString(),
              color: const Color(0xFFFF6B6B),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> route) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF172033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              route["route_id"]?.toString() ?? "Unassigned",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _buildMetaRow(
              icon: Icons.apartment,
              label: "Clinics",
              value: (route["total_clinics"] ?? 0).toString(),
              color: Colors.lightBlueAccent,
            ),
            _buildMetaRow(
              icon: Icons.warning_amber_rounded,
              label: "HIGH Risk Clinics",
              value: (route["high_risk_clinics"] ?? 0).toString(),
              color: const Color(0xFFFF6B6B),
            ),
            _buildMetaRow(
              icon: Icons.event,
              label: "Next Urgent Date",
              value: (route["urgent_date"] ?? "-").toString(),
              color: const Color(0xFFFFB347),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsSectionCard(String alert) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF172033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB347)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                alert,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(String alert) => _buildAlertsSectionCard(alert);

  Widget _buildRiskChip(String riskLevel) {
    final color = riskColor(riskLevel);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        riskLevel,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMetaRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white60)),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF172033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}
