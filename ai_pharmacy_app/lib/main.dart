import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'dart:typed_data';
import 'order_history_page.dart';

void main() {
  runApp(MaterialApp(home: LoginPage()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'AI Pharmacy', home: LoginPage());
  }
}

class MainScreen extends StatefulWidget {
  final String clinicId;

  const MainScreen({super.key, required this.clinicId});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String clinicName = "";

  final homeKey = GlobalKey<HomePageState>();
  final orderKey = GlobalKey<_OrderPageState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // 🔥 When user goes back to HomePage → refresh
    if (index == 0) {
      homeKey.currentState?.refreshAll();
    }

    if (index == 3) {
      orderKey.currentState?.refreshOrderPage();
    }
  }

  Future<void> fetchClinicName() async {
    final response = await http.get(
      Uri.parse(
        "http://localhost:5000/clinic_info?clinic_id=${widget.clinicId}",
      ),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        clinicName = data['clinic_name'];
      });
    }
  }

  void _showLogoutMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.logout),
                title: Text("Logout"),
                onTap: () {
                  Navigator.pop(context);
                  _confirmLogout(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Confirm Logout"),
        content: Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => LoginPage()),
                (route) => false,
              );
            },
            child: Text("Logout"),
          ),
        ],
      ),
    );
  }

  final List<String> _pageTitles = [
    "Inventory",
    "Stock Operations",
    "AI Insights",
    "Order Management",
  ];

  @override
  void initState() {
    super.initState();
    fetchClinicName();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(key: homeKey, clinicId: widget.clinicId),
      StockOperationsPage(clinicId: widget.clinicId),
      AIInsightsPage(clinicId: widget.clinicId),
      OrderPage(key: orderKey, clinicId: widget.clinicId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // 🔵 LEFT: Clinic Name
            GestureDetector(
              onTap: () {
                _showLogoutMenu(context);
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  clinicName.isEmpty ? widget.clinicId : clinicName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),

            // 🔥 CENTER TITLE
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "AI-Assisted Pharmacy Inventory System",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    _pageTitles[_selectedIndex],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // 🔥 RIGHT EMPTY (to balance center)
            SizedBox(width: 60),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.blueAccent,
      ),

      body: pages[_selectedIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: "Inventory",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz),
            label: "Operations",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights),
            label: "AI Insights",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: "Orders",
          ),
        ],
      ),
    );
  }
}

// ================= LOGIN PAGE =================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final String baseUrl = "http://localhost:5000";

  TextEditingController userController = TextEditingController();
  TextEditingController passController = TextEditingController();

  Future<void> login() async {
    final response = await http.post(
      Uri.parse("$baseUrl/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": userController.text,
        "password": passController.text,
      }),
    );

    final data = json.decode(response.body);

    if (response.statusCode == 200) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainScreen(clinicId: data['clinic_id']),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Login failed ❌")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Container(
          width: 350,
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔷 TITLE
              Text(
                "AI-Assisted Pharmacy Inventory System",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              SizedBox(height: 30),

              // 🔷 USERNAME
              TextField(
                controller: userController,
                decoration: InputDecoration(
                  labelText: "Username",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              SizedBox(height: 15),

              // 🔷 PASSWORD
              TextField(
                controller: passController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => login(),
                decoration: InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),

              SizedBox(height: 25),

              // 🔥 LOGIN BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: login,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text("Login", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= MAIN HOME PAGE =================

class HomePage extends StatefulWidget {
  final String clinicId;

  const HomePage({super.key, required this.clinicId});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final String baseUrl = "http://localhost:5000"; // ⚠️ Chrome OK, macOS NOT OK

  List inventory = [];
  List suggestions = [];
  String consolidatedDate = "";
  String recommendationMessage = "";
  String? selectedItem;
  bool isLoading = false;
  String clinicName = "";

  @override
  void initState() {
    super.initState();
    fetchInventory();
    fetchSuggestions();
    fetchConsolidation();
  }

  // ############## FETCH APIs ##############

  Future<void> fetchInventory() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/inventory?clinic_id=${widget.clinicId}"),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          inventory = data['inventory'];
          clinicName = data["clinic_name"];
        });
      }
    } catch (e) {
      print("ERROR: $e");
    }
  }

  Future<void> fetchSuggestions() async {
    final response = await http.get(
      Uri.parse("$baseUrl/order_suggestions?clinic_id=${widget.clinicId}"),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        suggestions = data['order_suggestions'];
      });
    }
  }

  Future<void> fetchConsolidation() async {
    final response = await http.get(
      Uri.parse("$baseUrl/consolidate?clinic_id=${widget.clinicId}"),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        consolidatedDate = data['consolidated_date'];
        recommendationMessage = data['recommendation_message'] ?? "";
      });
    }
  }

  void refreshAll() {
    fetchInventory();
    fetchSuggestions();
    fetchConsolidation();
  }

  // ############## UI ##############

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 🔷 INVENTORY CARD
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Inventory",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),

                    ...inventory.map(
                      (item) => Card(
                        color: item['current_stock'] < 100
                            ? Colors.red[50]
                            : Colors.grey[100],
                        child: ListTile(
                          title: Text(item['item_name']),
                          subtitle: item['current_stock'] < 100
                              ? Text(
                                  "⚠ Low Stock",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                          trailing: Text(
                            "Stock: ${item['current_stock']}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: item['current_stock'] < 100
                                  ? Colors.red
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 🔷 ORDER SUGGESTIONS
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Order Suggestions",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),

                    ...suggestions.map(
                      (item) => ListTile(
                        title: Text(item['item_name']),
                        subtitle: Text(
                          "Qty: ${item['suggested_qty']} | ${item['priority']}",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 🔷 NEXT ORDER DATE
            Card(
              elevation: 3,
              color: Colors.blue[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text("Next Order Date", style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      consolidatedDate.isEmpty ? "-" : consolidatedDate,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (recommendationMessage.isNotEmpty) ...[
              SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        recommendationMessage,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ================= STOCK OPERATIONS PAGE =================

class StockOperationsPage extends StatefulWidget {
  final String clinicId;

  const StockOperationsPage({super.key, required this.clinicId});

  @override
  _StockOperationsPageState createState() => _StockOperationsPageState();
}

class _StockOperationsPageState extends State<StockOperationsPage> {
  final String baseUrl = "http://localhost:5000";
  bool isLoading = false;
  List inventory = [];
  String? selectedItem;
  TextEditingController qtyController = TextEditingController();

  Future<void> stockIn(String item, int qty) async {
    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/stock_in"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "clinic_id": widget.clinicId,
          "item_name": item,
          "quantity_added": qty,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // ✅ SUCCESS MESSAGE (HERE, NOT IN BODY)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Stock-in successful ✅")));

        refreshAll();
      } else {
        // ❌ BACKEND ERROR
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Operation failed ❌")),
        );
      }
    } catch (e) {
      // ❌ NETWORK ERROR
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Connection error ❌")));
    }

    setState(() => isLoading = false);
  }

  Future<void> stockOut(String item, int qty) async {
    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/stock_out"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "clinic_id": widget.clinicId,
          "item_name": item,
          "quantity_used": qty,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // ✅ SUCCESS
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Stock-out successful ✅")));

        refreshAll();
      } else {
        // ❌ ERROR FROM BACKEND
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Operation failed ❌")),
        );
      }
    } catch (e) {
      // ❌ NETWORK ERROR
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Connection error ❌")));
    }
    setState(() => isLoading = false);
  }

  Future<void> fetchInventory() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/inventory?clinic_id=${widget.clinicId}"),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          inventory = data['inventory'];
        });
      }
    } catch (e) {
      print("ERROR: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchInventory();
  }

  void refreshAll() {
    // For now just placeholder
    //// Later we will connect to real data
    print("Refreshing data...");
  }

  // ############## DIALOG ##############

  void showStockDialog(String type) {
    TextEditingController itemController = TextEditingController();
    TextEditingController qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(type == "in" ? "Stock In" : "Stock Out"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                hint: Text("Select Item"),
                initialValue: selectedItem,
                items: inventory.map<DropdownMenuItem<String>>((item) {
                  return DropdownMenuItem<String>(
                    value: item['item_name'],
                    child: Text(item['item_name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedItem = value;
                  });
                },
              ),

              TextField(
                controller: qtyController,
                decoration: InputDecoration(labelText: "Quantity"),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final item = selectedItem;
                final qty = int.tryParse(qtyController.text) ?? 0;

                if (item == null || qty <= 0) return;

                if (type == "in") {
                  stockIn(item, qty);
                } else {
                  stockOut(item, qty);
                }

                selectedItem = null;
                Navigator.pop(context);
              },
              child: Text("Submit"),
            ),
          ],
        );
      },
    );
  }

  void showAddItemDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add New Medicine"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: "Item Name"),
              ),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: "Initial Stock"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text;
                final qty = int.tryParse(qtyController.text) ?? 0;

                if (name.isEmpty || qty <= 0) return;

                await stockIn(name, qty); // reuse existing API

                Navigator.pop(context);
              },
              child: Text("Add"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🔷 STOCK IN
            ElevatedButton(
              onPressed: () => showStockDialog("in"),
              child: Text("Stock In"),
            ),

            SizedBox(height: 10),

            // 🔷 STOCK OUT
            ElevatedButton(
              onPressed: () => showStockDialog("out"),
              child: Text("Stock Out"),
            ),

            SizedBox(height: 10),

            // 🔷 ADD NEW MEDICINE
            ElevatedButton(
              onPressed: showAddItemDialog,
              child: Text("➕ Add New Medicine"),
            ),

            SizedBox(height: 30),

            // 🔄 LOADING INDICATOR
            if (isLoading) Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

// ================= AI INSIGHTS PAGE ================= by Wafiy

class AIInsightsPage extends StatefulWidget {
  final String clinicId;

  const AIInsightsPage({Key? key, required this.clinicId}) : super(key: key);

  @override
  _AIInsightsPageState createState() => _AIInsightsPageState();
}

class _AIInsightsPageState extends State<AIInsightsPage> {
  final String baseUrl = "http://localhost:5000";
  bool isLoading = true;
  List<dynamic> smartInventory = [];
  int? selectedIndex;

  final List<Color> chartGradient = [
    const Color(0xff23b6e6),
    const Color(0xff02d39a),
  ];

  @override
  void initState() {
    super.initState();
    fetchSmartInventory();
  }

  Future<void> fetchSmartInventory() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("$baseUrl/ai/smart_inventory?clinic_id=${widget.clinicId}"));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          smartInventory = data['smart_inventory'] ?? [];
          if (smartInventory.isNotEmpty) selectedIndex = 0; // Auto select first
        });
      }
    } catch (e) {
      print("ERROR Smart Inventory: $e");
    }
    setState(() => isLoading = false);
  }

  Future<void> sendRequestToPKD(String itemName, int quantity) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/pkd/request_order"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "clinic_id": widget.clinicId,
          "orders": [
            {"item_name": itemName, "quantity": quantity}
          ]
        })
      );
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Order for $itemName sent to PKD! ✅"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to connect ❌"), backgroundColor: Colors.red),
      );
    }
  }

  void _showOrderConfirmDialog(String item, int recommendedQty) {
    TextEditingController qtyController = TextEditingController(text: recommendedQty.toString());
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Confirm Order to PKD", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("You are requesting stock for $item. Adjust the quantity if needed.", style: TextStyle(color: Colors.white70)),
              SizedBox(height: 20),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  labelText: "Quantity to order",
                  labelStyle: TextStyle(color: Colors.cyanAccent),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.cyanAccent, width: 2)),
                ),
              )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              ),
              onPressed: () {
                Navigator.pop(context);
                final q = int.tryParse(qtyController.text) ?? recommendedQty;
                sendRequestToPKD(item, q);
              },
              child: Text("Send to PKD", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        );
      }
    );
  }

  Future<void> sendRequestToTransfer(String itemName, int quantity, String donorClinicId) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/pkd/request_transfer"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "clinic_id": widget.clinicId,
          "from_clinic": donorClinicId,
          "item_name": itemName,
          "quantity": quantity
        })
      );
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Transfer Request sent to $donorClinicId! ✅"), backgroundColor: Colors.amber),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to connect ❌"), backgroundColor: Colors.red),
      );
    }
  }

  void _showTransferConfirmDialog(String item, int recommendedQty, String donorClinicId) {
    TextEditingController qtyController = TextEditingController(text: recommendedQty.toString());
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Cost-Saving Transfer", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Requesting $item from neighboring $donorClinicId instead of the main PKD warehouse. Adjust quantity if needed.", style: TextStyle(color: Colors.white70)),
              SizedBox(height: 20),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: Colors.amberAccent, fontSize: 18),
                decoration: InputDecoration(
                  labelText: "Transfer Quantity",
                  labelStyle: TextStyle(color: Colors.amberAccent),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.amberAccent, width: 2)),
                ),
              )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              ),
              onPressed: () {
                Navigator.pop(context);
                final q = int.tryParse(qtyController.text) ?? recommendedQty;
                sendRequestToTransfer(item, q, donorClinicId);
              },
              child: Text("Request Transfer", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        );
      }
    );
  }

  // ---- DESKTOP MASTER DETAIL LAYOUT ----
=======
class AIInsightsPage extends StatelessWidget {
  const AIInsightsPage({super.key});

>>>>>>> origin/main
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        color: const Color(0xFF0F172A),
        child: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }

    return Container(
      color: const Color(0xFF0F172A), // Space Blue Dark Theme
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT PANEL: MASTER LIST (35% Width)
          Expanded(
            flex: 35,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12)
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(20),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Medicines", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        Text("Sorted by depletion risk", style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.all(12),
                      itemCount: smartInventory.length,
                      itemBuilder: (context, index) {
                        return _buildListTile(index);
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
          
          SizedBox(width: 24),

          // RIGHT PANEL: DETAIL VIEW (65% Width)
          Expanded(
            flex: 65,
            child: selectedIndex == null 
                ? Center(child: Text("Select a medicine to view AI Insights", style: TextStyle(color: Colors.white54, fontSize: 18)))
                : _buildDetailPanel(),
          )
        ],
      ),
    );
  }

  Widget _buildListTile(int index) {
    var data = smartInventory[index];
    bool isSelected = selectedIndex == index;
    int runOutDays = data['run_out_days'];
    bool hasWarning = data['has_epidemic_warning'];

    Color statusColor = Colors.greenAccent;
    if (runOutDays > 0 && runOutDays <= 7) statusColor = Colors.redAccent;
    else if (runOutDays > 7 && runOutDays <= 14) statusColor = Colors.orangeAccent;

    return GestureDetector(
      onTap: () => setState(() => selectedIndex = index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent.withOpacity(0.5) : Colors.transparent,
            width: 1.5
          ),
          boxShadow: isSelected ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 10)] : []
        ),
        child: Row(
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 6)]),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(data['item_name'], style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ),
            if (hasWarning) Icon(Icons.bolt, color: Colors.yellowAccent, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
    var data = smartInventory[selectedIndex!];
    String itemName = data['item_name'];
    int currentStock = data['current_stock'];
    int runOutDays = data['run_out_days'];
    String runOutDate = data['run_out_date'];
    int recommendQty = data['recommend_order'];
    bool hasWarning = data['has_epidemic_warning'];
    String weatherWarning = data['weather_warning'] ?? "";
    bool hasWeatherWarning = weatherWarning.isNotEmpty;
    List<dynamic> transferCandidates = data['transfer_candidates'] ?? [];
    List<dynamic> forecastRaw = data['forecast_7_days'] ?? [];
    List<int> forecastData = List<int>.from(forecastRaw);

    bool hasTransferCandidate = transferCandidates.isNotEmpty;
    var bestDonor = hasTransferCandidate ? transferCandidates.first : null;

    Color statusColor = Colors.greenAccent;
    String daysText = "Safe Stock";
    if (runOutDays > 0 && runOutDays <= 7) { statusColor = Colors.redAccent; daysText = "$runOutDays Days Left!"; }
    else if (runOutDays > 7 && runOutDays <= 14) { statusColor = Colors.orangeAccent; daysText = "$runOutDays Days Left"; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BIG HEADER
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(itemName, style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                SizedBox(height: 4),
                Text("AI Forecast & Depletion Analysis", style: TextStyle(color: Colors.cyanAccent, fontSize: 14)),
              ],
            ),
            if (hasWarning)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.redAccent)),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text("Epidemic Spike Detected", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
          ],
        ),
        SizedBox(height: 30),

        // WEATHER WARNING BANNER
        if (hasWeatherWarning)
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: 24),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.1), blurRadius: 15)]
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_sync_rounded, color: Colors.blueAccent, size: 32),
                SizedBox(width: 16),
                Expanded(child: Text(weatherWarning, style: TextStyle(color: Colors.blue[100], fontSize: 16, fontWeight: FontWeight.bold))),
              ],
            ),
          ),

        // 3 METRIC CARDS
        Row(
          children: [
            Expanded(child: _buildMetricCard("Run-Out Date", runOutDate, daysText, statusColor)),
            SizedBox(width: 16),
            Expanded(child: _buildMetricCard("Current Stock", "$currentStock Units", "In Inventory", Colors.white)),
            SizedBox(width: 16),
            Expanded(child: _buildMetricCard("Recommended Order", "+$recommendQty", "To reach 30-day safety", Colors.cyanAccent)),
          ],
        ),
        SizedBox(height: 30),

        // CHART CONTAINER
        Expanded(
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("7-Day Trajectory", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 24),
                Expanded(child: _buildChart(forecastData)),
              ],
            ),
          ),
        ),
        
        SizedBox(height: 24),

        // AI TRANSFER RECOMMENDATION
        if (recommendQty > 0 && hasTransferCandidate) ...[
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withOpacity(0.4), width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.amber, size: 36),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("💡 Cost-Saving Transfer Available!", style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text("Neighboring clinic '${bestDonor['clinic_id']}' has a confirmed surplus of ${bestDonor['surplus_stock']} units.", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.compare_arrows),
                  label: Text("Request Transfer", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: () {
                    _showTransferConfirmDialog(itemName, recommendQty, bestDonor['clinic_id']);
                  },
                ),
                SizedBox(width: 12),
                OutlinedButton(
                  child: Text("Order PKD anyway", style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white24),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: () {
                    _showOrderConfirmDialog(itemName, recommendQty);
                  },
                )
              ],
            ),
          )
        ] else ...[
          // REGULAR ACTION BUTTON
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 10,
                shadowColor: Colors.cyanAccent.withOpacity(0.5)
              ),
              child: Text("Send PKD Order Request", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              onPressed: () {
                if (recommendQty > 0) {
                  _showOrderConfirmDialog(itemName, recommendQty);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Stock is perfectly healthy!")));
                }
              },
            ),
          )
        ]
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, Color glowColor) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: glowColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: glowColor.withOpacity(0.1), blurRadius: 20, spreadRadius: -5)
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.blueGrey[300], fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
          SizedBox(height: 8),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: glowColor, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildChart(List<int> forecastData) {
    if (forecastData.isEmpty || forecastData.every((e) => e == 0)) {
      return Center(child: Text("Insufficient historical data to graph.", style: TextStyle(color: Colors.white54)));
    }
    
    double maxY = forecastData.reduce((curr, next) => curr > next ? curr : next).toDouble();
    maxY = maxY < 50 ? 50 : maxY * 1.2;

    List<FlSpot> spots = [];
    for (int i = 0; i < forecastData.length; i++) {
      spots.add(FlSpot(i.toDouble(), forecastData[i].toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.white10, strokeWidth: 1, dashArray: [5, 5])
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 1,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("Day ${value.toInt() + 1}", style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(), style: const TextStyle(color: Colors.blueGrey, fontSize: 12));
              },
              reservedSize: 40,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            gradient: LinearGradient(colors: chartGradient),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4, color: Colors.cyanAccent, strokeWidth: 2, strokeColor: const Color(0xFF1E293B)
              )
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: chartGradient.map((c) => c.withOpacity(0.2)).toList(),
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter
              ),
            ),
          ),
        ],
      ),
    );
  }
} // End AIInsightsPage

// ================= ORDER PAGE =================

class OrderPage extends StatefulWidget {
  final String clinicId;

  const OrderPage({super.key, required this.clinicId});

  @override
  _OrderPageState createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final String baseUrl = "http://localhost:5000";

  List suggestions = [];
  String consolidatedDate = "";
  bool isLoading = false;
  String basedOn = "";
  List details = [];
  List generatedOrders = [];
  Map<String, dynamic>? lastSubmittedOrder;
  Map<String, dynamic> routeSummary = {
    "total_clinics": 0,
    "high_priority_count": 0,
    "medium_priority_count": 0,
    "low_priority_count": 0,
  };
  String mostUrgentClinic = "";
  String recommendationMessage = "";
  String clinicDisplayName = "";
  String generatedOrderDate = "";

  // 🔥 GENERATE ORDER
  Future<void> generateOrder() async {
    if (isLoading) return;
    try {
      final generatedItems = suggestions.map<Map<String, dynamic>>((item) {
        return {"item_name": item['item_name'], "qty": item['suggested_qty']};
      }).toList();
      final orderDate = DateTime.now().toIso8601String().split('T').first;

      final url = Uri.parse('$baseUrl/generate_order');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "clinic_id": widget.clinicId,
          "items": generatedItems,
        }),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode == 200) {
        setState(() {
          generatedOrders = generatedItems;
          generatedOrderDate = orderDate;
        });

        await refreshOrderPage();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Order generated successfully ✅")),
        );
      } else {
        throw Exception("Failed");
      }
    } catch (e) {
      print("ERROR: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to generate order ❌")));
    }
  }

  // GENERATE ORDER CONFIRMATION
  void confirmGenerateOrder() {
    showDialog(
      context: context,
      builder: (context) {
        int totalQty = suggestions.fold(
          0,
          (sum, item) => sum + (item['suggested_qty'] as int),
        );
        return AlertDialog(
          title: Text("Confirm Order"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("You are about to order:\n"),

              ...suggestions.map(
                (item) =>
                    Text("• ${item['item_name']} — ${item['suggested_qty']}"),
              ),
              Text("Total: $totalQty items"),

              SizedBox(height: 10),
              Text("Proceed?"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                generateOrder(); // proceed
              },
              child: Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  Color getPriorityColor(String priority) {
    switch (priority) {
      case "HIGH":
        return Colors.red;
      case "MEDIUM":
        return Colors.orange;
      case "LOW":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void clearConsolidationState() {
    setState(() {
      consolidatedDate = "";
      basedOn = "";
      details = [];
      routeSummary = {
        "total_clinics": 0,
        "high_priority_count": 0,
        "medium_priority_count": 0,
        "low_priority_count": 0,
      };
      mostUrgentClinic = "";
      recommendationMessage = "";
    });
  }

  @override
  void initState() {
    super.initState();
    fetchClinicName();
    refreshOrderPage();
  }

  Future<void> fetchClinicName() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/clinic_info?clinic_id=${widget.clinicId}"),
      );

      if (response.statusCode != 200) return;

      final data = json.decode(response.body);

      if (!mounted) return;

      setState(() {
        clinicDisplayName = data['clinic_name'] ?? widget.clinicId;
      });
    } catch (e) {
      print("ERROR fetching clinic name: $e");
    }
  }

  Future<void> refreshOrderPage() async {
    await Future.wait([
      fetchSuggestions(),
      fetchConsolidation(),
      fetchLastSubmittedOrder(),
    ]);
  }

  Future<void> fetchAll() async {
    await refreshOrderPage();
  }

  Future<void> fetchSuggestions() async {
    final response = await http.get(
      Uri.parse("$baseUrl/order_suggestions?clinic_id=${widget.clinicId}"),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      setState(() {
        suggestions = data['order_suggestions'];
      });
    }
  }

  Future<void> fetchConsolidation() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/consolidate?clinic_id=${widget.clinicId}"),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          consolidatedDate = data['consolidated_date'] ?? "";
          basedOn = data['based_on'] ?? "";
          details = data['details'] ?? [];
          routeSummary = Map<String, dynamic>.from(
            data['summary'] ??
                {
                  "total_clinics": 0,
                  "high_priority_count": 0,
                  "medium_priority_count": 0,
                  "low_priority_count": 0,
                },
          );
          mostUrgentClinic = data['most_urgent_clinic'] ?? "";
          recommendationMessage = data['recommendation_message'] ?? "";
        });
      } else {
        clearConsolidationState();
      }
    } catch (e) {
      print("ERROR fetching consolidation: $e");
      clearConsolidationState();
    }
  }

  Future<void> markOrderReceived() async {
    if (lastSubmittedOrder == null) return;

    final url = Uri.parse('$baseUrl/complete_order');

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({"clinic_id": widget.clinicId}),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Order marked as received ✅")));

      await refreshOrderPage();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed ❌")));
    }
  }

  DateTime _parseOrderDate(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> fetchLastSubmittedOrder() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/orders?clinic_id=${widget.clinicId}'),
      );

      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      final List<Map<String, dynamic>> submittedOrders =
          (data['orders'] as List<dynamic>)
              .where((order) => order['status'] == "SUBMITTED")
              .map((order) => Map<String, dynamic>.from(order))
              .toList();

      submittedOrders.sort(
        (a, b) => _parseOrderDate(
          b['created_at'],
        ).compareTo(_parseOrderDate(a['created_at'])),
      );

      if (!mounted) return;

      setState(() {
        lastSubmittedOrder = submittedOrders.isNotEmpty
            ? submittedOrders.first
            : null;
      });
    } catch (e) {
      print("ERROR fetching last submitted order: $e");

      if (!mounted) return;

      setState(() {
        lastSubmittedOrder = null;
      });
    }
  }

  Widget buildInsightRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> buildOrderPdf() async {
    final pdf = pw.Document();
    final orderDate = generatedOrderDate.isEmpty
        ? DateTime.now().toIso8601String().split('T').first
        : generatedOrderDate;
    final clinicLabel = clinicDisplayName.isEmpty
        ? widget.clinicId
        : clinicDisplayName;

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "AI-Assisted Pharmacy System",
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Text(
                  "Clinic: $clinicLabel",
                  style: pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                pw.Text("Date: $orderDate", style: pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 24),
                pw.Text(
                  "Items",
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                ...generatedOrders.map((item) {
                  final qty = item['qty'] ?? item['suggested_qty'] ?? 0;

                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Text(
                      "- ${item['item_name']}: $qty",
                      style: const pw.TextStyle(fontSize: 13),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> exportOrderAsPdf() async {
    if (generatedOrders.isEmpty) return;

    final clinicLabel = clinicDisplayName.isEmpty
        ? widget.clinicId
        : clinicDisplayName;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text("Order PDF Preview")),
          body: PdfPreview(
            build: (format) => buildOrderPdf(),
            pdfFileName:
                "order_${clinicLabel.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf",
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 🔷 ORDER SUGGESTIONS
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Suggested Orders",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),

                    ...suggestions.map(
                      (item) => ListTile(
                        leading: Icon(Icons.medication),
                        title: Text(item['item_name']),
                        subtitle: Text("Priority: ${item['priority']}"),
                        trailing: Text(
                          "Qty: ${item['suggested_qty']}",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 🔷 CONSOLIDATED DATE
            Card(
              elevation: 3,
              color: Colors.blue[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text("Next Order Date", style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      consolidatedDate.isEmpty ? "-" : consolidatedDate,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (recommendationMessage.isNotEmpty) ...[
              SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        recommendationMessage,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 20),

            // REASON CARD
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  basedOn.isEmpty
                      ? "Based on: -"
                      : "Based on: $basedOn priority",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            SizedBox(height: 16),

            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Route Insight",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    buildInsightRow(
                      icon: Icons.groups_rounded,
                      color: Colors.indigo,
                      label: "Total clinics",
                      value: "${routeSummary['total_clinics'] ?? 0}",
                    ),
                    buildInsightRow(
                      icon: Icons.priority_high_rounded,
                      color: Colors.red,
                      label: "High priority",
                      value: "${routeSummary['high_priority_count'] ?? 0}",
                    ),
                    buildInsightRow(
                      icon: Icons.warning_amber_rounded,
                      color: Colors.orange,
                      label: "Medium priority",
                      value: "${routeSummary['medium_priority_count'] ?? 0}",
                    ),
                    buildInsightRow(
                      icon: Icons.check_circle_outline_rounded,
                      color: Colors.green,
                      label: "Low priority",
                      value: "${routeSummary['low_priority_count'] ?? 0}",
                    ),
                    Divider(height: 24),
                    buildInsightRow(
                      icon: Icons.local_hospital_rounded,
                      color: Colors.blueAccent,
                      label: "Most urgent clinic",
                      value: mostUrgentClinic.isEmpty ? "-" : mostUrgentClinic,
                    ),
                  ],
                ),
              ),
            ),

            // DETAILS LIST
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Clinic Breakdown",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),

                    ...details.map(
                      (d) => ListTile(
                        title: Text(d['clinic']),
                        subtitle: Text("Date: ${d['date'] ?? '-'}"),
                        trailing: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: getPriorityColor(
                              d['priority'],
                            ).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            d['priority'],
                            style: TextStyle(
                              color: getPriorityColor(d['priority']),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (details.isEmpty)
                      Text(
                        "No route comparison available right now.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            ),

            // VIEW ORDER HISTORY BUTTON
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderHistoryPage(clinicId: widget.clinicId),
                  ),
                ).then((_) {
                  fetchLastSubmittedOrder(); // 🔥 REFRESH HERE
                });
              },
              child: Text("View Order History"),
            ),

            // 🔥 GENERATE BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: suggestions.isEmpty ? null : confirmGenerateOrder,
                icon: Icon(Icons.shopping_cart),
                label: Text(
                  "Generate Order",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            SizedBox(height: 20),

            if (lastSubmittedOrder != null)
              Card(
                margin: EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Last Submitted Order",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 5),
                      Text("Date: ${lastSubmittedOrder!['created_at']}"),
                      SizedBox(height: 5),

                      ...lastSubmittedOrder!['items'].map<Widget>((item) {
                        return Text("• ${item['item_name']} — ${item['qty']}");
                      }).toList(),
                    ],
                  ),
                ),
              ),

            // MARK AS RECEIVED BUTTON
            if (lastSubmittedOrder != null)
              ElevatedButton.icon(
                onPressed: markOrderReceived,
                icon: Icon(Icons.check),
                label: Text("Mark as Received"),
              ),

            // DISPLAY ORDER LIST
            if (generatedOrders.isNotEmpty)
              Card(
                margin: EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Generated Order (APPL)",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),

                      ...generatedOrders.map(
                        (item) => ListTile(
                          title: Text(item['item_name']),
                          trailing: Text(
                            "Qty: ${item['qty'] ?? item['suggested_qty']}",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: exportOrderAsPdf,
                          icon: Icon(Icons.picture_as_pdf_outlined),
                          label: Text("Export as PDF"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 🔄 LOADING
            if (isLoading) Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
