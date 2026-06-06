import 'package:flutter/material.dart';
import 'main.dart';
import 'services/live_inventory_service.dart';
import 'services/sync_service.dart';
import 'dispense_history_page.dart';

class LiveInventoryPage extends StatefulWidget {
  final String? clinicId;

  const LiveInventoryPage({super.key, this.clinicId});

  @override
  State<LiveInventoryPage> createState() => _LiveInventoryPageState();
}

class _LiveInventoryPageState extends State<LiveInventoryPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> _inventory = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  bool _isOffline = false;
  String _search = "";
  String _filterChip = "All";
  String _sortOption = "Name A-Z";
  late TabController _tabController;

  static const List<String> _filterOptions = [
    "All",
    "Low Stock",
    "Moderate",
    "Adequate",
  ];

  static const List<String> _sortOptions = [
    "Name A-Z",
    "Name Z-A",
    "Quantity Low → High",
    "Quantity High → Low",
    "Recently Updated",
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    bool loaded = false;
    try {
      final data = await LiveInventoryService.fetchLiveInventory(
        clinicId: widget.clinicId,
      );
      if (!mounted) return;
      if (data.isNotEmpty) {
        setState(() {
          _inventory = data;
          _applyFilter();
          _isLoading = false;
        });
        loaded = true;
      }
    } catch (_) {}

    if (!loaded && mounted) {
      final localData = await SyncService.getLocalInventory(
        clinicId: widget.clinicId,
      );
      if (!mounted) return;
      setState(() {
        _inventory = localData;
        _isOffline = true;
        _applyFilter();
        _isLoading = false;
      });
    } else if (!loaded) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    var items = List<Map<String, dynamic>>.from(_inventory);

    // Search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      items = items.where((item) {
        final displayName = liveInventoryDisplayName(item).toLowerCase();
        final generic = (item['generic_name'] ?? '').toString().toLowerCase();
        final brand = (item['brand_name'] ?? '').toString().toLowerCase();
        final fullBrand =
            (item['full_brand_name'] ?? '').toString().toLowerCase();
        final matchName =
            (item['match_name'] ?? '').toString().toLowerCase();
        final itemCode = (item['item_code'] ?? '').toString().toLowerCase();
        return displayName.contains(q) ||
            generic.contains(q) ||
            brand.contains(q) ||
            fullBrand.contains(q) ||
            matchName.contains(q) ||
            itemCode.contains(q);
      }).toList();
    }

    // Filter chip
    if (_filterChip == "Low Stock") {
      items = items
          .where((item) =>
              ((item['quantity'] ?? 0) as num).toInt() < 20)
          .toList();
    } else if (_filterChip == "Moderate") {
      items = items
          .where((item) {
            final qty = ((item['quantity'] ?? 0) as num).toInt();
            return qty >= 20 && qty < 50;
          })
          .toList();
    } else if (_filterChip == "Adequate") {
      items = items
          .where((item) =>
              ((item['quantity'] ?? 0) as num).toInt() >= 50)
          .toList();
    }

    // Sort
    if (_sortOption == "Name A-Z") {
      items.sort(
          (a, b) => liveInventoryDisplayName(a).compareTo(liveInventoryDisplayName(b)));
    } else if (_sortOption == "Name Z-A") {
      items.sort(
          (a, b) => liveInventoryDisplayName(b).compareTo(liveInventoryDisplayName(a)));
    } else if (_sortOption == "Quantity Low → High") {
      items.sort((a, b) =>
          ((a['quantity'] ?? 0) as num).compareTo((b['quantity'] ?? 0) as num));
    } else if (_sortOption == "Quantity High → Low") {
      items.sort((a, b) =>
          ((b['quantity'] ?? 0) as num).compareTo((a['quantity'] ?? 0) as num));
    } else if (_sortOption == "Recently Updated") {
      items.sort((a, b) {
        final aDate = (a['updated_at'] ?? '').toString();
        final bDate = (b['updated_at'] ?? '').toString();
        return bDate.compareTo(aDate);
      });
    }

    _filtered = items;
  }

  Color _stockColor(int qty) {
    if (qty > 50) return const Color(0xFF2FBF71);
    if (qty >= 20) return const Color(0xFFF5A524);
    return const Color(0xFFEF5A5A);
  }

  String _stockLabel(int qty) {
    if (qty > 50) return "Adequate";
    if (qty >= 20) return "Moderate";
    return "Low Stock";
  }

  int get _lowStockCount =>
      _inventory.where((i) => ((i['quantity'] ?? 0) as num).toInt() < 20).length;

  int get _moderateCount =>
      _inventory.where((i) {
        final qty = ((i['quantity'] ?? 0) as num).toInt();
        return qty >= 20 && qty < 50;
      }).length;

  int get _adequateCount =>
      _inventory.where((i) => ((i['quantity'] ?? 0) as num).toInt() >= 50).length;

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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            "Live Inventory Status",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.cyanAccent),
              onPressed: () async {
                await SyncService.fullSync(widget.clinicId ?? '');
                _load();
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1.5),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.3),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.3),
                tabs: const [
                  Tab(text: "Inventory"),
                  Tab(text: "Dispense History"),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildInventoryTab(),
            DispenseHistoryPage(clinicId: widget.clinicId),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "$count $label",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            const SizedBox(height: 16),
            Text(
              "Loading live stock counts...",
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_isOffline)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.orangeAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Offline Mode — Displaying local database backup",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orangeAccent.shade100,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Search catalog or code...",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5), size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.cyanAccent),
              ),
            ),
            onChanged: (v) {
              setState(() {
                _search = v;
                _applyFilter();
              });
            },
          ),
        ),
        // Summary counters
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              _buildSummaryChip("Low Stock", _lowStockCount, const Color(0xFFEF5A5A)),
              const SizedBox(width: 8),
              _buildSummaryChip("Moderate", _moderateCount, const Color(0xFFF5A524)),
              const SizedBox(width: 8),
              _buildSummaryChip("Adequate", _adequateCount, const Color(0xFF2FBF71)),
              const Spacer(),
              if (!_isOffline)
                FutureBuilder<String>(
                  future: SyncService.lastSyncTime(),
                  builder: (_, snap) {
                    final label = snap.data ?? '';
                    final short = label.length > 19
                        ? label.substring(0, 19).replaceFirst('T', ' ')
                        : label;
                    return Text(
                      "Sync: $short",
                      style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4)),
                    );
                  },
                ),
            ],
          ),
        ),
        // Filter chips + sort dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filterOptions.map((f) {
                      final active = _filterChip == f;
                      Color chipColor;
                      Color textColor;
                      if (f == "Low Stock") {
                        chipColor = const Color(0xFFEF5A5A);
                        textColor = Colors.white;
                      } else if (f == "Moderate") {
                        chipColor = const Color(0xFFF5A524);
                        textColor = Colors.white;
                      } else if (f == "Adequate") {
                        chipColor = const Color(0xFF2FBF71);
                        textColor = Colors.white;
                      } else {
                        chipColor = Colors.cyanAccent;
                        textColor = const Color(0xFF090D1A);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _filterChip = f;
                              _applyFilter();
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: active ? chipColor : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active ? chipColor : Colors.white.withOpacity(0.12),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: active ? textColor : Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortOption,
                    isDense: true,
                    dropdownColor: const Color(0xFF1E293B),
                    icon: Icon(Icons.arrow_drop_down_rounded, color: Colors.white.withOpacity(0.6)),
                    items: _sortOptions.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _sortOption = val;
                        _applyFilter();
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Inventory list
        if (_filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _search.isEmpty && _filterChip == "All"
                    ? "No inventory data found"
                    : "No matching medicines found",
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              backgroundColor: const Color(0xFF1E293B),
              color: Colors.cyanAccent,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final item = _filtered[i];
                  final qty = ((item['quantity'] ?? 0) as num).toInt();
                  final color = _stockColor(qty);
                  final genericName = (item['generic_name'] ?? '').toString().trim();
                  final dosageForm = (item['dosage_form'] ?? '').toString().trim();
                  final displayName = liveInventoryDisplayName(item);
                  final ratio = (qty.toDouble() / 100.0).clamp(0.0, 1.0);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 64,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (genericName.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    genericName,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (dosageForm.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    dosageForm,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 4,
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      backgroundColor: Colors.white.withOpacity(0.04),
                                      valueColor: AlwaysStoppedAnimation<Color>(color),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "$qty",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                  shadows: [
                                    Shadow(color: color.withOpacity(0.3), blurRadius: 6),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withOpacity(0.2)),
                                ),
                                child: Text(
                                  _stockLabel(qty),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
