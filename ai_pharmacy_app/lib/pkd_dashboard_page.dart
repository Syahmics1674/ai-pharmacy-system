import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config/api_config.dart';
import 'main.dart';
import 'services/live_inventory_service.dart';

class PKDDashboardPage extends StatefulWidget {
  final String district;

  const PKDDashboardPage({super.key, required this.district});

  @override
  State<PKDDashboardPage> createState() => _PKDDashboardPageState();
}

class _PKDDashboardPageState extends State<PKDDashboardPage> {
  final String baseUrl = ApiConfig.baseUrl;
  final TextEditingController searchController = TextEditingController();

  bool isLoading = true;
  bool isLoadingStage2 = true;
  String errorMessage = "";
  int selectedIndex = 0;

  Map<String, dynamic> overview = {};
  List<Map<String, dynamic>> clinics = [];
  List<Map<String, dynamic>> routes = [];
  List<Map<String, dynamic>> topMedicines = [];

  String clinicSearch = "";
  String selectedRoute = "All";
  String selectedDistrict = "All";
  String selectedRisk = "All";

  // PKD live inventory state
  String? selectedPKDClinicId;
  List<dynamic> pkdInventoryItems = [];
  int pkdTotalItems = 0;
  int pkdTotalQty = 0;
  int pkdLowStock = 0;
  bool pkdInventoryLoading = false;

  @override
  void initState() {
    super.initState();
    refreshDashboard();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _safeGet(String url, {Duration timeout = const Duration(seconds: 15)}) async {
    final response = await http.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception("HTTP ${response.statusCode}");
  }

  Future<Map<String, dynamic>> _safeGetOrEmpty(String url) async {
    try {
      return await _safeGet(url);
    } catch (_) {
      return {};
    }
  }

  Future<void> refreshDashboard() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      isLoadingStage2 = true;
      errorMessage = "";
    });

    // Safety timeout: force-stop loading after 25 seconds
    Future.delayed(const Duration(seconds: 25), () {
      if (mounted && isLoading) {
        setState(() {
          isLoading = false;
          isLoadingStage2 = false;
          if (errorMessage.isEmpty) {
            errorMessage = "Dashboard load timed out. Tap Retry.";
          }
        });
      }
    });

    try {
      final encodedDistrict = Uri.encodeComponent(widget.district);

      // Stage 1: Try consolidated endpoint first
      try {
        final consolidated = await _safeGet("$baseUrl/pkd/dashboard_summary?district=$encodedDistrict");
        if (mounted) {
          setState(() {
            overview = Map<String, dynamic>.from(consolidated['overview'] ?? {});
            clinics = (consolidated['clinics'] as List<dynamic>? ?? [])
                .map((c) => Map<String, dynamic>.from(c as Map))
                .toList();
            routes = (consolidated['routes'] as List<dynamic>? ?? [])
                .map((r) => Map<String, dynamic>.from(r as Map))
                .toList();
            final rawTopMeds = consolidated['overview']?['top_medicines'] as List<dynamic>? ?? [];
            topMedicines = rawTopMeds
                .map((m) => Map<String, dynamic>.from(m as Map))
                .toList();
            isLoading = false;
            isLoadingStage2 = false;
          });
          return;
        }
      } catch (_) {
        // Fall through to individual endpoints
      }

      // Stage 2: Individual endpoints in parallel, each tolerated individually
      final responses = await Future.wait([
        _safeGetOrEmpty("$baseUrl/pkd/overview?district=$encodedDistrict"),
        _safeGetOrEmpty("$baseUrl/pkd/clinic_risks?district=$encodedDistrict"),
        _safeGetOrEmpty("$baseUrl/pkd/routes?district=$encodedDistrict"),
        _safeGetOrEmpty("$baseUrl/pkd/top_medicines?district=$encodedDistrict"),
      ]);

      if (!mounted) return;

      final ov = responses[0];
      final clinicData = responses[1];
      final routeData = responses[2];
      final medData = responses[3];
      final anyData = ov.isNotEmpty || clinicData.isNotEmpty || routeData.isNotEmpty || medData.isNotEmpty;

      setState(() {
        overview = Map<String, dynamic>.from(ov);
        clinics = (clinicData["clinics"] as List<dynamic>? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        routes = (routeData["routes"] as List<dynamic>? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        topMedicines = (medData["medicines"] as List<dynamic>? ?? [])
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList();
        isLoading = false;
        isLoadingStage2 = false;
        if (!anyData) {
          errorMessage = "Unable to load dashboard data. Tap Retry.";
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        isLoadingStage2 = false;
        errorMessage = "Unable to connect to backend";
      });
    }
  }

  bool get isDesktop => MediaQuery.of(context).size.width >= 1024;

  bool get isWideLayout => MediaQuery.of(context).size.width >= 1280;

  ThemeData get theme => Theme.of(context);

  Color get backgroundColor => theme.brightness == Brightness.dark
      ? const Color(0xFF0D1320)
      : const Color(0xFFF4F7FB);

  Color get surfaceColor => theme.brightness == Brightness.dark
      ? const Color(0xFF172033)
      : Colors.white;

  Color get secondarySurfaceColor => theme.brightness == Brightness.dark
      ? const Color(0xFF1E2A40)
      : const Color(0xFFEAF1FB);

  Color get headlineColor => theme.brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF10233B);

  Color get bodyColor => theme.brightness == Brightness.dark
      ? Colors.white70
      : const Color(0xFF41556E);

  Color riskColor(String riskLevel) {
    switch (riskLevel.toUpperCase()) {
      case "HIGH":
        return const Color(0xFFEF5A5A);
      case "MEDIUM":
        return const Color(0xFFF5A524);
      default:
        return const Color(0xFF2FBF71);
    }
  }

  List<int> trendValues(String key) {
    final trend = overview["trend"] as Map<String, dynamic>? ?? {};
    final rawValues = trend[key] as List<dynamic>? ?? const [];
    return rawValues.map((value) => _asInt(value)).toList();
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  List<String> get routeOptions {
    final values =
        routes
            .map((route) => (route["route_id"] ?? "Unassigned").toString())
            .toSet()
            .toList()
          ..sort();
    return ["All", ...values];
  }

  List<String> get districtOptions {
    final values =
        clinics
            .map((clinic) => (clinic["district"] ?? widget.district).toString())
            .toSet()
            .toList()
          ..sort();
    return ["All", ...values];
  }

  List<Map<String, dynamic>> get filteredClinics {
    return clinics.where((clinic) {
      final clinicName = (clinic["name"] ?? clinic["clinic_id"] ?? "")
          .toString()
          .toLowerCase();
      final route = (clinic["route_id"] ?? "Unassigned").toString();
      final district = (clinic["district"] ?? widget.district).toString();
      final risk = (clinic["risk_level"] ?? "SAFE").toString();

      final matchesSearch =
          clinicSearch.isEmpty ||
          clinicName.contains(clinicSearch.toLowerCase());
      final matchesRoute = selectedRoute == "All" || route == selectedRoute;
      final matchesDistrict =
          selectedDistrict == "All" || district == selectedDistrict;
      final matchesRisk = selectedRisk == "All" || risk == selectedRisk;

      return matchesSearch && matchesRoute && matchesDistrict && matchesRisk;
    }).toList();
  }

  List<FlSpot> buildSpots(List<int> values) {
    if (values.isEmpty) {
      return const [FlSpot(0, 0), FlSpot(1, 0), FlSpot(2, 0)];
    }

    return List.generate(
      values.length,
      (index) => FlSpot(index.toDouble(), values[index].toDouble()),
    );
  }

  Future<void> _loadPKDInventory() async {
    setState(() => pkdInventoryLoading = true);
    final items = await LiveInventoryService.fetchLiveInventory(
      clinicId: selectedPKDClinicId,
    );
    if (!mounted) return;
    setState(() {
      pkdInventoryItems = items;
      pkdTotalItems = items.length;
      pkdTotalQty = 0;
      pkdLowStock = 0;
      for (final item in items) {
        final qty = (item['quantity'] ?? 0) as num;
        pkdTotalQty += qty.toInt();
        if (qty < 20) pkdLowStock++;
      }
      pkdInventoryLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = isLoading
        ? Center(
            child: CircularProgressIndicator(color: theme.colorScheme.primary),
          )
        : errorMessage.isNotEmpty
        ? _buildErrorState()
        : _buildShell();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text("PKD Observer Dashboard"),
              backgroundColor: surfaceColor,
              foregroundColor: headlineColor,
              elevation: 0,
              actions: [
                IconButton(
                  onPressed: refreshDashboard,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: "Logout",
                ),
              ],
            ),
      body: SafeArea(child: page),
      bottomNavigationBar: isDesktop ? null : _buildMobileNavigation(),
    );
  }

  Widget _buildShell() {
    return Row(
      children: [
        if (isDesktop) _buildSidebar(),
        Expanded(
          child: Column(
            children: [
              if (isDesktop) _buildDesktopHeader(),
              Expanded(child: _buildCurrentPage()),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _performLogout();
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  void _performLogout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "PKD Observer",
            style: TextStyle(
              color: headlineColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "District: ${widget.district}",
            style: TextStyle(color: bodyColor, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            _navigationItems.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildNavTile(
                index: index,
                label: _navigationItems[index].label,
                icon: _navigationItems[index].icon,
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildLogoutTile(),
          ),
          _buildSidebarFooter(),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: secondarySurfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Live Observer Mode",
            style: TextStyle(color: headlineColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            "Summaries only. No raw stock quantities are exposed to PKD users.",
            style: TextStyle(color: bodyColor, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = selectedIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.22)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? theme.colorScheme.primary : bodyColor,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? headlineColor : bodyColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _confirmLogout,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5A5A).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFEF5A5A).withValues(alpha: 0.18),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF5A5A)),
            SizedBox(width: 12),
            Text(
              "Logout",
              style: TextStyle(
                color: Color(0xFFEF5A5A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "PKD Observer Dashboard",
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "District-level monitoring for clinics, routes, and medicine demand across ${widget.district}.",
                  style: TextStyle(color: bodyColor, fontSize: 14),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: refreshDashboard,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text("Refresh"),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNavigation() {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
      destinations: _navigationItems
          .map(
            (item) =>
                NavigationDestination(icon: Icon(item.icon), label: item.label),
          )
          .toList(),
    );
  }

  Widget _buildCurrentPage() {
    switch (selectedIndex) {
      case 1:
        return _buildClinicsPage();
      case 2:
        return _buildRoutesPage();
      case 3:
        return _buildPKDInventoryPage();
      default:
        return _buildOverviewPage();
    }
  }

  Widget _buildPKDInventoryPage() {
    final clinics = this.clinics;
    final clinicOptions = <String, String>{};
    clinicOptions[""] = "All Clinics";
    for (final c in clinics) {
      final id = (c["clinic_id"] ?? "").toString();
      final name = (c["name"] ?? id).toString();
      if (id.isNotEmpty) clinicOptions[id] = name;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildSectionTitle("Live Inventory"),
        const SizedBox(height: 12),
        // District summary cards
        Row(
          children: [
            _buildSummaryCard("Total Items", "$pkdTotalItems", Colors.blue),
            const SizedBox(width: 10),
            _buildSummaryCard("Total Quantity", "$pkdTotalQty", Colors.green),
            const SizedBox(width: 10),
            _buildSummaryCard("Low Stock", "$pkdLowStock", Colors.red),
          ],
        ),
        const SizedBox(height: 16),
        // Clinic dropdown
        DropdownButtonFormField<String>(
          initialValue: selectedPKDClinicId ?? "",
          decoration: const InputDecoration(
            labelText: "Select Clinic",
            prefixIcon: Icon(Icons.local_hospital_outlined),
            border: OutlineInputBorder(),
          ),
          items: clinicOptions.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ))
              .toList(),
          onChanged: (val) {
            setState(() => selectedPKDClinicId = val);
            _loadPKDInventory();
          },
        ),
        const SizedBox(height: 12),
        // Inventory list
        if (pkdInventoryLoading)
          const Center(child: CircularProgressIndicator())
        else if (pkdInventoryItems.isEmpty)
          _buildEmptyState("No inventory data for selected clinic.")
        else
          ...pkdInventoryItems.map((item) {
            final qty = ((item['quantity'] ?? 0) as num).toInt();
            final color = qty > 50
                ? const Color(0xFF2FBF71)
                : qty >= 20
                    ? const Color(0xFFF5A524)
                    : const Color(0xFFEF5A5A);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 6, height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            liveInventoryDisplayName(item),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Text("$qty",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: color)),
                        if (qty < 20)
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFEF5A5A), size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: bodyColor, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewPage() {
    final summaryCards = [
      _MetricCardData(
        "Total Clinics",
        (overview["total_clinics"] ?? 0).toString(),
        Icons.local_hospital_outlined,
        theme.colorScheme.primary,
      ),
      _MetricCardData(
        "Clinics at Risk",
        (overview["clinics_at_risk"] ?? 0).toString(),
        Icons.warning_amber_rounded,
        const Color(0xFFEF5A5A),
      ),
      _MetricCardData(
        "Pending Orders",
        (overview["total_pending_orders"] ?? 0).toString(),
        Icons.pending_actions_outlined,
        const Color(0xFFF5A524),
      ),
      _MetricCardData(
        "Medicines Tracked",
        (overview["medicines_tracked"] ?? 0).toString(),
        Icons.medication_outlined,
        const Color(0xFF2FBF71),
      ),
      _MetricCardData(
        "Monthly Usage Logs",
        (overview["total_monthly_logs"] ?? 0).toString(),
        Icons.timeline_outlined,
        const Color(0xFF9A6CFF),
      ),
      _MetricCardData(
        "Active Routes",
        (overview["active_routes"] ?? 0).toString(),
        Icons.route_outlined,
        const Color(0xFF4AA3FF),
      ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        8,
        isDesktop ? 24 : 16,
        24,
      ),
      children: [
        _buildHeroCard(),
        const SizedBox(height: 20),
        _buildMetricGrid(summaryCards),
        const SizedBox(height: 20),
        _buildResponsivePanels(
          left: [
            _buildTrendCard(
              title: "Order Activity Trend",
              subtitle: "Recent submitted order movement",
              color: theme.colorScheme.primary,
              values: trendValues("orders"),
            ),
            const SizedBox(height: 16),
            _buildTrendCard(
              title: "High-Risk Clinic Trend",
              subtitle: "District pressure over recent checkpoints",
              color: const Color(0xFFEF5A5A),
              values: trendValues("high_risk"),
            ),
          ],
          right: [
            _buildTopMedicinesCard(),
            const SizedBox(height: 16),
            _buildInsightCard(),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle("Clinic Risk Snapshot"),
        const SizedBox(height: 12),
        _buildClinicSnapshotGrid(),
        const SizedBox(height: 20),
        _buildSectionTitle("Route Priorities"),
        const SizedBox(height: 12),
        _buildRoutePreviewGrid(),
      ],
    );
  }

  Widget _buildHeroCard() {
    final highRisk = overview["clinics_at_risk"] ?? overview["high_risk_clinics"] ?? 0;
    final activeRoutes = overview["active_routes"] ?? 0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.18),
            surfaceColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.monitor_heart_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "District Observer View",
                      style: TextStyle(
                        color: headlineColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Tracking risk posture, logistics demand, and route pressure across ${widget.district}.",
                      style: TextStyle(color: bodyColor, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeroTag(
                Icons.warning_amber_rounded,
                "$highRisk high-risk clinics",
                const Color(0xFFEF5A5A),
              ),
              _buildHeroTag(
                Icons.route_outlined,
                "$activeRoutes active delivery routes",
                const Color(0xFF4AA3FF),
              ),
              _buildHeroTag(
                Icons.shield_outlined,
                "Summary-only PKD access",
                const Color(0xFF2FBF71),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTag(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(List<_MetricCardData> cards) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 1400
        ? 3
        : width >= 900
        ? 3
        : 2;

    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: width >= 900 ? 1.8 : 1.35,
      ),
      itemBuilder: (context, index) => _buildMetricCard(cards[index]),
    );
  }

  Widget _buildMetricCard(_MetricCardData card) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(card.icon, color: card.color),
          const Spacer(),
          Text(
            card.value,
            style: TextStyle(
              color: headlineColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(card.label, style: TextStyle(color: bodyColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildResponsivePanels({
    required List<Widget> left,
    required List<Widget> right,
  }) {
    if (isWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 16),
          Expanded(child: Column(children: right)),
        ],
      );
    }

    return Column(children: [...left, const SizedBox(height: 16), ...right]);
  }

  Widget _buildTrendCard({
    required String title,
    required String subtitle,
    required Color color,
    required List<int> values,
  }) {
    final spots = buildSpots(values);
    final maxY = math.max<double>(
      4,
      spots.map((spot) => spot.y).fold<double>(0, math.max) + 2,
    );

    return _buildSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: headlineColor,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: bodyColor, fontSize: 13)),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(0, values.length - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: theme.dividerColor.withValues(alpha: 0.12),
                    strokeWidth: 1,
                  ),
                ),
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
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(color: bodyColor, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const labels = ["Earlier", "Recent", "Current"];
                        final safeIndex = value.toInt().clamp(
                          0,
                          labels.length - 1,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[safeIndex],
                            style: TextStyle(color: bodyColor, fontSize: 11),
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
                      color: color.withValues(alpha: 0.12),
                    ),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                            radius: 4,
                            color: color,
                            strokeWidth: 2,
                            strokeColor: surfaceColor,
                          ),
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

  Widget _buildTopMedicinesCard() {
    final highestUsage = topMedicines.isEmpty
        ? 1
        : topMedicines
              .map(
                (medicine) => _asInt(medicine["total_used"], fallback: 1),
              )
              .reduce(math.max);

    return _buildSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: "Top Dispensed Medicines",
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 4),
          Text(
            "District-wide ranking using recent usage logs.",
            style: TextStyle(color: bodyColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (topMedicines.isEmpty)
            _buildEmptyState("No medicine usage data available yet.")
          else
            ...topMedicines.map((medicine) {
              final rank = _asInt(medicine["rank"]);
              final usage = _asInt(medicine["total_used"]);
              final progress = highestUsage == 0 ? 0.0 : usage / highestUsage;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: rank == 1
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.16,
                                  )
                                : secondarySurfaceColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              "#$rank",
                              style: TextStyle(
                                color: rank == 1
                                    ? theme.colorScheme.primary
                                    : bodyColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (medicine["item_name"] ?? "Unknown Medicine")
                                    .toString(),
                                style: TextStyle(
                                  color: headlineColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                (medicine["category"] ?? "Uncategorized")
                                    .toString(),
                                style: TextStyle(
                                  color: bodyColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          usage.toString(),
                          style: TextStyle(
                            color: headlineColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: theme.dividerColor.withValues(
                          alpha: 0.10,
                        ),
                        color: rank == 1
                            ? theme.colorScheme.primary
                            : const Color(0xFF4AA3FF),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildInsightCard() {
    final insights = (overview["insights"] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();

    return _buildSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: "AI Recommendations",
            icon: Icons.auto_awesome_outlined,
          ),
          const SizedBox(height: 4),
          Text(
            "Operational guidance generated from route and clinic trends.",
            style: TextStyle(color: bodyColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (insights.isEmpty)
            _buildEmptyState("No AI recommendations available yet.")
          else
            ...insights.map(
              (insight) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: secondarySurfaceColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        insight,
                        style: TextStyle(color: headlineColor, height: 1.45),
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

  Widget _buildClinicSnapshotGrid() {
    final featuredClinics = clinics.take(4).toList();

    if (featuredClinics.isEmpty) {
      return _buildSurfaceCard(
        child: _buildEmptyState(
          "No clinics available for the selected district.",
        ),
      );
    }

    return GridView.builder(
      itemCount: featuredClinics.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWideLayout ? 2 : 1,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isWideLayout ? 2.25 : 1.9,
      ),
      itemBuilder: (context, index) => _buildClinicCard(featuredClinics[index]),
    );
  }

  Widget _buildRoutePreviewGrid() {
    final previewRoutes = routes.take(3).toList();

    if (previewRoutes.isEmpty) {
      return _buildSurfaceCard(
        child: _buildEmptyState("No route analytics available yet."),
      );
    }

    return GridView.builder(
      itemCount: previewRoutes.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWideLayout ? 3 : 1,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isWideLayout ? 1.25 : 1.5,
      ),
      itemBuilder: (context, index) => _buildRouteCard(previewRoutes[index]),
    );
  }

  Widget _buildClinicsPage() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        8,
        isDesktop ? 24 : 16,
        24,
      ),
      children: [
        _buildSectionTitle("Clinic Monitoring"),
        const SizedBox(height: 12),
        _buildFilterCard(),
        const SizedBox(height: 16),
        if (filteredClinics.isEmpty)
          _buildSurfaceCard(
            child: _buildEmptyState(
              "No clinics match the current search/filter set.",
            ),
          )
        else
          ...filteredClinics.map(_buildClinicCard),
      ],
    );
  }

  Widget _buildFilterCard() {
    final filterWidgets = [
      SizedBox(
        width: isDesktop ? 260 : double.infinity,
        child: TextField(
          controller: searchController,
          onChanged: (value) {
            setState(() {
              clinicSearch = value.trim();
            });
          },
          decoration: const InputDecoration(
            labelText: "Search clinic",
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
      SizedBox(
        width: isDesktop ? 180 : double.infinity,
        child: DropdownButtonFormField<String>(
          initialValue: selectedRoute,
          items: routeOptions
              .map(
                (route) =>
                    DropdownMenuItem<String>(value: route, child: Text(route)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              selectedRoute = value;
            });
          },
          decoration: const InputDecoration(
            labelText: "Route",
            prefixIcon: Icon(Icons.route_outlined),
          ),
        ),
      ),
      SizedBox(
        width: isDesktop ? 180 : double.infinity,
        child: DropdownButtonFormField<String>(
          initialValue: selectedDistrict,
          items: districtOptions
              .map(
                (district) => DropdownMenuItem<String>(
                  value: district,
                  child: Text(district),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              selectedDistrict = value;
            });
          },
          decoration: const InputDecoration(
            labelText: "District",
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
      ),
      SizedBox(
        width: isDesktop ? 180 : double.infinity,
        child: DropdownButtonFormField<String>(
          initialValue: selectedRisk,
          items: const ["All", "SAFE", "MEDIUM", "HIGH"]
              .map(
                (risk) =>
                    DropdownMenuItem<String>(value: risk, child: Text(risk)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              selectedRisk = value;
            });
          },
          decoration: const InputDecoration(
            labelText: "Risk Level",
            prefixIcon: Icon(Icons.shield_outlined),
          ),
        ),
      ),
    ];

    return _buildSurfaceCard(
      child: Wrap(spacing: 12, runSpacing: 12, children: filterWidgets),
    );
  }

  Widget _buildRoutesPage() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        8,
        isDesktop ? 24 : 16,
        24,
      ),
      children: [
        _buildSectionTitle("Route Analytics"),
        const SizedBox(height: 12),
        _buildRouteComparisonCard(),
        const SizedBox(height: 16),
        if (routes.isEmpty)
          _buildSurfaceCard(
            child: _buildEmptyState("No route analytics available yet."),
          )
        else
          ...routes.map(_buildRouteCard),
      ],
    );
  }

  Widget _buildRouteComparisonCard() {
    if (routes.isEmpty) {
      return _buildSurfaceCard(
        child: _buildEmptyState("No route comparison data available."),
      );
    }

    final highestPriority = routes
        .map((route) => (_asInt(route["delivery_priority_score"])).toDouble())
        .fold<double>(1, math.max);

    return _buildSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: "Route Demand Comparison",
            icon: Icons.stacked_bar_chart_rounded,
          ),
          const SizedBox(height: 4),
          Text(
            "Compares delivery pressure scores across all active routes.",
            style: TextStyle(color: bodyColor, fontSize: 13),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: highestPriority + 10,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: theme.dividerColor.withValues(alpha: 0.12),
                    strokeWidth: 1,
                  ),
                ),
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
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(color: bodyColor, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= routes.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            routes[index]["route_id"].toString(),
                            style: TextStyle(color: bodyColor, fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(routes.length, (index) {
                  final route = routes[index];
                  final riskLevel = (route["average_risk_level"] ?? "SAFE")
                      .toString();
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: _asInt(
                          route["delivery_priority_score"],
                        ).toDouble(),
                        color: riskColor(riskLevel),
                        width: 26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicCard(Map<String, dynamic> clinic) {
    final riskLevel = (clinic["risk_level"] ?? "SAFE").toString();
    final color = riskColor(riskLevel);
    final pendingOrders = _asInt(clinic["pending_orders"]);

    return _buildSurfaceCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (clinic["name"] ??
                              clinic["clinic_id"] ??
                              "Unknown Clinic")
                          .toString(),
                      style: TextStyle(
                        color: headlineColor,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${clinic["district"] ?? clinic["clinic_id"] ?? widget.district} • ${clinic["route_id"] ?? "Unassigned"}",
                      style: TextStyle(color: bodyColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _buildRiskChip(riskLevel),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetaPill(
                Icons.schedule_rounded,
                "Last Update",
                _formatDate(clinic["last_inventory_update"]),
              ),
              _buildMetaPill(
                Icons.pending_actions_outlined,
                "Pending Orders",
                pendingOrders.toString(),
              ),
              _buildMetaPill(
                Icons.auto_graph_outlined,
                "AI Status",
                (clinic["ai_status"] ?? "Monitoring").toString(),
              ),
              _buildMetaPill(
                Icons.event_outlined,
                "Next Order",
                (clinic["next_order_date"] ?? "-").toString(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (clinic["risk_reason"] ?? "No active risk reason detected")
                        .toString(),
                    style: TextStyle(color: headlineColor, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> route) {
    final riskLevel = (route["average_risk_level"] ?? "SAFE").toString();
    final clinicsInRoute =
        (route["clinics"] as List<dynamic>? ?? const <dynamic>[])
            .take(3)
            .map((clinic) => (clinic as Map)["name"].toString())
            .toList();

    return _buildSurfaceCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (route["route_id"] ?? "Unassigned").toString(),
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildRiskChip(riskLevel),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetaPill(
                Icons.local_hospital_outlined,
                "Clinics",
                _asInt(route["clinic_count"]).toString(),
              ),
              _buildMetaPill(
                Icons.pending_actions_outlined,
                "Pending Orders",
                _asInt(route["pending_orders"]).toString(),
              ),
              _buildMetaPill(
                Icons.speed_rounded,
                "Priority Score",
                _asInt(route["delivery_priority_score"]).toString(),
              ),
              _buildMetaPill(
                Icons.warning_amber_rounded,
                "Risk Clusters",
                _asInt(route["stockout_risk_clusters"]).toString(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: secondarySurfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Urgent Date: ${(route["urgent_date"] ?? "-").toString()}",
                  style: TextStyle(
                    color: headlineColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Average risk score: ${route["average_risk_score"] ?? "-"} • Monthly usage logs: ${route["total_monthly_usage_logs"] ?? 0}",
                  style: TextStyle(color: bodyColor, height: 1.4),
                ),
                if (clinicsInRoute.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Clinics: ${clinicsInRoute.join(", ")}",
                    style: TextStyle(color: bodyColor, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskChip(String riskLevel) {
    final color = riskColor(riskLevel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        riskLevel,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMetaPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: secondarySurfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: bodyColor, fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: headlineColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: headlineColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: headlineColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: bodyColor, height: 1.5),
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
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF5A5A),
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              style: TextStyle(color: bodyColor, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: refreshDashboard,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic rawValue) {
    if (rawValue == null) return "No update";

    final value = rawValue.toString();
    if (value.isEmpty) return "No update";

    final date = DateTime.tryParse(value);
    if (date == null) return value;

    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$year-$month-$day";
  }

  List<_NavItem> get _navigationItems => const [
    _NavItem("Overview", Icons.dashboard_customize_outlined),
    _NavItem("Clinics", Icons.local_hospital_outlined),
    _NavItem("Routes", Icons.route_outlined),
    _NavItem("Live Inventory", Icons.medication_outlined),
  ];
}

class _MetricCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCardData(this.label, this.value, this.icon, this.color);
}

class _NavItem {
  final String label;
  final IconData icon;

  const _NavItem(this.label, this.icon);
}
