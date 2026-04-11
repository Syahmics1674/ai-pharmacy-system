import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OrderHistoryPage extends StatefulWidget {
  final String clinicId;

  const OrderHistoryPage({super.key, required this.clinicId});

  @override
  _OrderHistoryPageState createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  List orders = [];
  bool isLoading = true;

  final String baseUrl = "http://127.0.0.1:5000";

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders?clinic_id=${widget.clinicId}'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<Map<String, dynamic>> fetchedOrders =
          (data['orders'] as List<dynamic>)
              .map((order) => Map<String, dynamic>.from(order))
              .toList();

      fetchedOrders.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['created_at'].toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB =
            DateTime.tryParse(b['created_at'].toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      setState(() {
        orders = fetchedOrders;
        isLoading = false;
      });
    }
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    final url = Uri.parse('$baseUrl/update_order_status');

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({"order_id": orderId, "status": status}),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Status updated to $status ✅")));

      await fetchOrders();

      if (!mounted) return;

      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed ❌")));
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case "PENDING":
        return Colors.orange;
      case "SUBMITTED":
        return Colors.blue;
      case "RECEIVED":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Order History")),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : orders.isEmpty
          ? Center(child: Text("No orders yet"))
          : ListView.builder(
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];

                return Card(
                  margin: EdgeInsets.all(10),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Status: ${order['status']}",
                          style: TextStyle(
                            color: getStatusColor(order['status']),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text("Date: ${order['created_at']}"),
                        SizedBox(height: 10),

                        ...order['items'].map<Widget>((item) {
                          return Text(
                            "• ${item['item_name']} — ${item['qty']}",
                          );
                        }).toList(),

                        SizedBox(height: 10),

                        Row(
                          children: [
                            if (order['status'] == "PENDING")
                              ElevatedButton(
                                onPressed: () =>
                                    updateOrderStatus(order['id'], "SUBMITTED"),
                                child: Text("Submit"),
                              ),
                          ],
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
