import 'package:flutter/material.dart';
import 'main.dart';
import 'services/live_inventory_service.dart';
import 'services/sync_service.dart';
import 'services/time_service.dart';
import 'dispense_history_page.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'widgets/common/empty_state.dart';
import 'widgets/common/loading_state.dart';

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
    "Quantity Low \u2192 High",
    "Quantity High \u2192 Low",
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

    if (_sortOption == "Name A-Z") {
      items.sort(
          (a, b) => liveInventoryDisplayName(a).compareTo(liveInventoryDisplayName(b)));
    } else if (_sortOption == "Name Z-A") {
      items.sort(
          (a, b) => liveInventoryDisplayName(b).compareTo(liveInventoryDisplayName(a)));
    } else if (_sortOption == "Quantity Low \u2192 High") {
      items.sort((a, b) =>
          ((a['quantity'] ?? 0) as num).compareTo((b['quantity'] ?? 0) as num));
    } else if (_sortOption == "Quantity High \u2192 Low") {
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
    if (qty > 50) return AppColors.success;
    if (qty >= 20) return AppColors.warning;
    return AppColors.danger;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.primaryLight : AppColors.primary;

    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const SizedBox.shrink(),
          toolbarHeight: _isOffline ? 90 : 50,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              margin: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: accentColor,
                unselectedLabelColor: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? AppColors.primaryLight : AppColors.primary;

    if (_isLoading) {
      return const LoadingState(message: "Loading live stock counts...");
    }

    return Column(
      children: [
        if (_isOffline)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "Offline Mode \u2014 Displaying local database backup",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.warningLight : AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: TextField(
            style: TextStyle(color: isDark ? AppColors.textOnDark : AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Search catalog or code...",
              hintStyle: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, size: 20),
              filled: true,
              fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: accentColor),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: Row(
            children: [
              _buildSummaryChip("Low Stock", _lowStockCount, AppColors.danger),
              const SizedBox(width: AppSpacing.sm),
              _buildSummaryChip("Moderate", _moderateCount, AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              _buildSummaryChip("Adequate", _adequateCount, AppColors.success),
              const Spacer(),
              if (!_isOffline)
                FutureBuilder<String>(
                  future: SyncService.lastSyncTime(),
                  builder: (_, snap) {
                    final label = snap.data ?? '';
                    final formatted = label.isNotEmpty ? TimeService.formatDateTime(label) : '';
                    return Text(
                      "Sync: $formatted",
                      style: TextStyle(fontSize: 10, color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
                    );
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filterOptions.map((f) {
                      final active = _filterChip == f;
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
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: active ? accentColor : (isDark ? AppColors.borderDark : AppColors.borderLight),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active ? accentColor : (isDark ? AppColors.borderDark : AppColors.borderLight),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: active ? Colors.white : (isDark ? AppColors.textOnDark : AppColors.textPrimary),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                  border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortOption,
                    isDense: true,
                    dropdownColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    icon: Icon(Icons.arrow_drop_down_rounded, color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
                    items: _sortOptions.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
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
        const SizedBox(height: AppSpacing.sm),
        if (_filtered.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.medication_rounded,
              title: "No medicines found",
              subtitle: "Adjust search or filter to see results",
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: accentColor,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.xxl),
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
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 64,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (genericName.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    genericName,
                                    style: TextStyle(
                                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
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
                                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.sm),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 4,
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                                      valueColor: AlwaysStoppedAnimation<Color>(color),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "$qty",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: color.withValues(alpha: 0.2)),
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
