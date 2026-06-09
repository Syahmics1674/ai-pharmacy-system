import 'package:flutter/material.dart';
import 'services/live_inventory_service.dart';

class DispenseHistoryPage extends StatefulWidget {
  final String? clinicId;

  const DispenseHistoryPage({super.key, this.clinicId});

  @override
  State<DispenseHistoryPage> createState() => _DispenseHistoryPageState();
}

class _DispenseHistoryPageState extends State<DispenseHistoryPage> {
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  bool _sortAscending = false; // false = Latest First (default)
  String _filterAction = 'all'; // 'all', 'dispense', 'stock_out'

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<dynamic> get _filteredSorted {
    var items = _transactions;

    // Filter
    if (_filterAction != 'all') {
      items = items.where((t) {
        final a = (t['action'] ?? '').toString().toLowerCase();
        return a == _filterAction;
      }).toList();
    }

    // Sort by created_at
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDispense
            ? (isDark ? Colors.green.withOpacity(0.2) : Colors.green.withOpacity(0.1))
            : (isDark ? Colors.deepOrange.withOpacity(0.2) : Colors.deepOrange.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isDispense ? "DISPENSE" : "STOCK OUT",
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isDispense
              ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
              : (isDark ? Colors.deepOrange.shade300 : Colors.deepOrange.shade800),
        ),
      ),
    );
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return '';
    try {
      final clean = raw
          .replaceFirst(RegExp(r'\.\d+'), '')
          .replaceFirst('Z', '')
          .replaceFirst('+00:00', '');
      final dt = DateTime.parse(clean);
      final day = dt.day.toString().padLeft(2, '0');
      final mon = _months[dt.month - 1];
      final yr = dt.year.toString();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$day $mon $yr, $hh:$mm';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? Colors.white.withOpacity(0.6) : const Color(0xFF64748B);
    final textMuted = isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF94A3B8);
    final chipBg = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final chipText = isDark ? Colors.white : Colors.grey.shade700;
    final badgeDispenseBg = isDark ? Colors.green.withOpacity(0.2) : Colors.green.withOpacity(0.1);
    final badgeStockOutBg = isDark ? Colors.deepOrange.withOpacity(0.2) : Colors.deepOrange.withOpacity(0.1);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Filter and sort controls
        _buildControls(isDark),
        const Divider(height: 1),
        Expanded(
          child: _transactions.isEmpty
              ? Center(
                  child: Text(
                    "No dispense history",
                    style: TextStyle(color: textMuted),
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
                      final formattedTs = _formatTimestamp(rawTs);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                isNegative ? Icons.trending_down : Icons.trending_up,
                                color: isNegative ? Colors.red : Colors.green,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
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
                                        const SizedBox(width: 8),
                                        _buildActionBadge(isDispense, isDark),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (formattedTs.isNotEmpty)
                                      Text(
                                        formattedTs,
                                        style: TextStyle(color: textMuted, fontSize: 12),
                                      ),
                                    if (t['device_id'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          "Device: ${t['device_id']}",
                                          style: TextStyle(color: textSecondary, fontSize: 11),
                                        ),
                                      ),
                                    if (t['confidence'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Text(
                                          "Confidence: ${t['confidence']}",
                                          style: TextStyle(color: textSecondary, fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isNegative ? "${qtyNum.toInt()}" : "+${qtyNum.toInt()}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isNegative ? Colors.red : Colors.green,
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
    final chipBg = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final chipText = isDark ? Colors.white : Colors.grey.shade700;
    const filters = ['all', 'dispense', 'stock_out'];
    const filterLabels = ['All', 'Dispense', 'Stock Out'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Filter chips
          ...List.generate(filters.length, (i) {
            final active = _filterAction == filters[i];
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _filterAction = filters[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : chipBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    filterLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : chipText,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Sort button
          GestureDetector(
            onTap: () => setState(() => _sortAscending = !_sortAscending),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: chipText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _sortAscending ? 'Oldest First' : 'Latest First',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: chipText,
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
