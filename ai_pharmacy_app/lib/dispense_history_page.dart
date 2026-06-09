import 'package:flutter/material.dart';
import 'services/live_inventory_service.dart';
import 'services/time_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';

class DispenseHistoryPage extends StatefulWidget {
  final String? clinicId;

  const DispenseHistoryPage({super.key, this.clinicId});

  @override
  State<DispenseHistoryPage> createState() => _DispenseHistoryPageState();
}

class _DispenseHistoryPageState extends State<DispenseHistoryPage> {
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  bool _sortAscending = false;
  String _filterAction = 'all';

  List<dynamic> get _filteredSorted {
    var items = _transactions;

    if (_filterAction != 'all') {
      items = items.where((t) {
        final a = (t['action'] ?? '').toString().toLowerCase();
        return a == _filterAction;
      }).toList();
    }

    items = List.from(items);
    items.sort((a, b) {
      final ats = (a['created_at'] ?? a['timestamp'] ?? '').toString();
      final bts = (b['created_at'] ?? b['timestamp'] ?? '').toString();
      final cmp = ats.compareTo(bts);
      return _sortAscending ? cmp : -cmp;
    });

    return items;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await LiveInventoryService.fetchDispenseHistory(
      clinicId: widget.clinicId,
    );
    if (!mounted) return;
    setState(() {
      _transactions = data;
      _isLoading = false;
    });
  }

  Widget _buildActionBadge(bool isDispense, bool isDark) {
    final c = isDispense ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isDispense ? "DISPENSE" : "STOCK OUT",
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: c,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildControls(isDark),
        const Divider(height: 1),
        Expanded(
          child: _transactions.isEmpty
              ? Center(
                  child: Text(
                    "No dispense history",
                    style: TextStyle(
                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    itemCount: _filteredSorted.length,
                    itemBuilder: (_, i) {
                      final t = _filteredSorted[i];
                      final qty = t['quantity_change'] ?? t['quantity'] ?? 0;
                      final qtyNum = (qty is num) ? qty.toDouble() : 0.0;
                      final isNegative = qtyNum < 0;

                      final action = (t['action'] ?? '').toString().toLowerCase();
                      final isDispense = action == 'dispense';

                      final name = (t['_display_name'] ?? t['matched_name'] ?? t['item_name'] ?? t['item_code'] ?? 'Unknown').toString();

                      final rawTs = (t['created_at'] ?? t['timestamp'] ?? '').toString();
                      final formattedTs = rawTs.isNotEmpty ? TimeService.formatDateTimeShort(rawTs) : '';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                isNegative ? Icons.trending_down : Icons.trending_up,
                                color: isNegative ? AppColors.danger : AppColors.success,
                                size: 28,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        _buildActionBadge(isDispense, isDark),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (formattedTs.isNotEmpty)
                                      Text(
                                        formattedTs,
                                        style: TextStyle(
                                          color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (t['device_id'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          "Device: ${t['device_id']}",
                                          style: TextStyle(
                                            color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    if (t['confidence'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Text(
                                          "Confidence: ${t['confidence']}",
                                          style: TextStyle(
                                            color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Text(
                                isNegative ? "${qtyNum.toInt()}" : "+${qtyNum.toInt()}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isNegative ? AppColors.danger : AppColors.success,
                                  fontSize: 20,
                                ),
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

  Widget _buildControls(bool isDark) {
    const filters = ['all', 'dispense', 'stock_out'];
    const filterLabels = ['All', 'Dispense', 'Stock Out'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          ...List.generate(filters.length, (i) {
            final active = _filterAction == filters[i];
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _filterAction = filters[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : (isDark ? AppColors.surfaceDark : AppColors.backgroundLight),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    filterLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : (isDark ? AppColors.textOnDark : AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _sortAscending = !_sortAscending),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _sortAscending ? 'Oldest First' : 'Latest First',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
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
