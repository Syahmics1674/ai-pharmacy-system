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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_transactions.isEmpty) {
      return Center(
        child: Text(
          "No dispense history",
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _transactions.length,
        itemBuilder: (_, i) {
          final t = _transactions[i];
          final qty = t['quantity_change'] ?? t['quantity'] ?? 0;
          final qtyNum = (qty is num) ? qty.toDouble() : 0.0;
          final isNegative = qtyNum < 0;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: Icon(
                isNegative ? Icons.trending_down : Icons.trending_up,
                color: isNegative ? Colors.red : Colors.green,
              ),
              title: Text(
                (t['medicine_name'] ?? t['item_name'] ?? 'Unknown').toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t['device_id'] != null)
                    Text(
                      "Device: ${t['device_id']}",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  if (t['confidence'] != null)
                    Text(
                      "Confidence: ${t['confidence']}",
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isNegative ? "${qtyNum.toInt()}" : "+${qtyNum.toInt()}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isNegative ? Colors.red : Colors.green,
                      fontSize: 16,
                    ),
                  ),
                  if (t['created_at'] != null || t['timestamp'] != null)
                    Text(
                      (t['created_at'] ?? t['timestamp'] ?? '').toString(),
                      style: TextStyle(color: Colors.grey[500], fontSize: 10),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
