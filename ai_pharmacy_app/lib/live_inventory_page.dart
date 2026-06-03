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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Inventory"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await SyncService.fullSync(widget.clinicId ?? '');
              _load();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Inventory"),
            Tab(text: "Dispense History"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInventoryTab(),
          DispenseHistoryPage(clinicId: widget.clinicId),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            "$count $label",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_isOffline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            color: Colors.orange.shade100,
            child: Row(
              children: [
                Icon(Icons.wifi_off, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Text(
                  "Offline Mode — showing local data",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: "Search medicine...",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    );
                  },
                ),
            ],
          ),
        ),
        // Filter chips + sort dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filterOptions.map((f) {
                      final active = _filterChip == f;
                      Color chipColor;
                      if (f == "Low Stock") {
                        chipColor = const Color(0xFFEF5A5A);
                      } else if (f == "Moderate") {
                        chipColor = const Color(0xFFF5A524);
                      } else if (f == "Adequate") {
                        chipColor = const Color(0xFF2FBF71);
                      } else {
                        chipColor = Colors.blueAccent;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(f, style: const TextStyle(fontSize: 12)),
                          selected: active,
                          onSelected: (_) {
                            setState(() {
                              _filterChip = f;
                              _applyFilter();
                            });
                          },
                          selectedColor: chipColor.withOpacity(0.2),
                          checkmarkColor: chipColor,
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortOption,
                    isDense: true,
                    items: _sortOptions.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 12)),
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
        const SizedBox(height: 4),
        // Inventory list
        if (_filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _search.isEmpty && _filterChip == "All"
                    ? "No inventory data"
                    : "No matches found",
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final item = _filtered[i];
                  final qty = ((item['quantity'] ?? 0) as num).toInt();
                  final color = _stockColor(qty);
                  final genericName =
                      (item['generic_name'] ?? '').toString().trim();
                  final dosageForm =
                      (item['dosage_form'] ?? '').toString().trim();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 60,
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                if (genericName.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      genericName,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                if (dosageForm.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Text(
                                      dosageForm,
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "$qty",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _stockLabel(qty),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
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
