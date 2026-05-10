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

  const AIInsightsPage({super.key, required this.clinicId});

  @override
  _AIInsightsPageState createState() => _AIInsightsPageState();
}

class _AIInsightsPageState extends State<AIInsightsPage> {
  final String baseUrl = "http://localhost:5000";
  final TextEditingController searchController = TextEditingController();
  bool isLoading = true;
  String errorMessage = "";
  List<dynamic> smartInventory = [];
  Map<String, List<int>> overallUsage = {
    "daily": [10, 12, 8, 15, 20, 18, 22],
    "weekly": [80, 95, 70, 110],
    "monthly": [300, 420, 390],
  };
  Map<String, int> stockSummary = {"critical": 0, "low": 0, "safe": 0};
  List<dynamic> topProducts = [];
  String insightMessage = "";
  String searchQuery = "";
  String selectedTrend = "daily";

  final List<Color> chartGradient = [
    const Color(0xff23b6e6),
    const Color(0xff02d39a),
  ];

  static const Color pageBackground = Color(0xFF0F172A);
  static const Color surfaceColor = Color(0xFF1E293B);
  static const Color surfaceColorAlt = Color(0xFF111827);

  @override
  void initState() {
    super.initState();
    fetchAIInsights();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchAIInsights() async {
    setState(() => isLoading = true);

    try {
      final responses = await Future.wait([
        http.get(
          Uri.parse("$baseUrl/ai/smart_inventory?clinic_id=${widget.clinicId}"),
        ),
        http.get(
          Uri.parse("$baseUrl/ai/overall_usage?clinic_id=${widget.clinicId}"),
        ),
        http.get(
          Uri.parse("$baseUrl/ai/stock_summary?clinic_id=${widget.clinicId}"),
        ),
        http.get(
          Uri.parse("$baseUrl/ai/top_products?clinic_id=${widget.clinicId}"),
        ),
        http.get(
          Uri.parse("$baseUrl/ai/insight_message?clinic_id=${widget.clinicId}"),
        ),
      ]);

      if (!mounted) return;

      final smartInventoryResponse = responses[0];
      final overallUsageResponse = responses[1];
      final stockSummaryResponse = responses[2];
      final topProductsResponse = responses[3];
      final insightMessageResponse = responses[4];

      if (smartInventoryResponse.statusCode != 200) {
        final data = json.decode(smartInventoryResponse.body);
        setState(() {
          errorMessage =
              data['details'] ??
              data['error'] ??
              "Unable to load AI insights right now.";
          smartInventory = [];
        });
      } else {
        final smartData = json.decode(smartInventoryResponse.body);
        final overallData = overallUsageResponse.statusCode == 200
            ? json.decode(overallUsageResponse.body)
            : {};
        final stockData = stockSummaryResponse.statusCode == 200
            ? json.decode(stockSummaryResponse.body)
            : {};
        final topData = topProductsResponse.statusCode == 200
            ? json.decode(topProductsResponse.body)
            : [];
        final messageData = insightMessageResponse.statusCode == 200
            ? json.decode(insightMessageResponse.body)
            : {};

        setState(() {
          errorMessage = "";
          smartInventory = smartData['smart_inventory'] ?? [];
          overallUsage = {
            "daily": _parseIntList(overallData['daily']),
            "weekly": _parseIntList(overallData['weekly']),
            "monthly": _parseIntList(overallData['monthly']),
          };
          stockSummary = {
            "critical": stockData['critical'] ?? 0,
            "low": stockData['low'] ?? 0,
            "safe": stockData['safe'] ?? 0,
          };
          topProducts = topData is List ? topData : [];
          insightMessage =
              messageData['message'] ?? "No AI message available right now.";
        });
      }
    } catch (e) {
      print("ERROR AI Insights: $e");

      if (!mounted) return;

      setState(() {
        errorMessage = "Unable to load AI insights right now.";
        smartInventory = [];
      });
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  List<int> _parseIntList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => int.tryParse(item.toString()) ?? 0).toList();
  }

  List<dynamic> get filteredInventory {
    if (searchQuery.trim().isEmpty) {
      return smartInventory;
    }

    final query = searchQuery.trim().toLowerCase();
    return smartInventory.where((item) {
      final itemName = (item['item_name'] ?? "").toString().toLowerCase();
      return itemName.contains(query);
    }).toList();
  }

  Color _statusColorForItem(Map<String, dynamic> item) {
    final runOutDays = item['run_out_days'] ?? -1;
    if (runOutDays > 0 && runOutDays <= 7) return Colors.redAccent;
    if (runOutDays > 7 && runOutDays <= 14) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _trendLabel(String trend) {
    switch (trend) {
      case "weekly":
        return "Weekly usage";
      case "monthly":
        return "Monthly usage";
      default:
        return "Daily usage";
    }
  }

  List<int> get selectedTrendData {
    final data = overallUsage[selectedTrend] ?? [];
    if (data.isEmpty) {
      return selectedTrend == "daily"
          ? [10, 12, 8, 15, 20, 18, 22]
          : selectedTrend == "weekly"
          ? [80, 95, 70, 110]
          : [300, 420, 390];
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        color: pageBackground,
        child: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return Container(
      color: pageBackground,
      child: RefreshIndicator(
        color: Colors.cyanAccent,
        backgroundColor: surfaceColor,
        onRefresh: fetchAIInsights,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildPageHeader(),
            const SizedBox(height: 20),
            if (errorMessage.isNotEmpty) _buildErrorCard(),
            _buildOverallUsageChartCard(),
            const SizedBox(height: 16),
            _buildStockSummaryCard(),
            const SizedBox(height: 16),
            _buildTopProductsCard(),
            const SizedBox(height: 16),
            _buildInsightMessageCard(),
            const SizedBox(height: 20),
            _buildSearchCard(),
            const SizedBox(height: 16),
            _buildMedicineListCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceColorAlt,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.psychology_alt_outlined, color: Colors.cyanAccent),
              SizedBox(width: 12),
              Text(
                "AI Insights Dashboard",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Overall analytics, smart medicine monitoring, and fast drill-down by product.",
            style: TextStyle(color: Colors.blueGrey[200], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallUsageChartCard() {
    final trendData = selectedTrendData;
    final maxValue = trendData.isEmpty
        ? 10.0
        : trendData.reduce((a, b) => a > b ? a : b).toDouble();
    final maxY = maxValue < 10 ? 10.0 : maxValue * 1.25;
    final labels = selectedTrend == "daily"
        ? ["D1", "D2", "D3", "D4", "D5", "D6", "D7"]
        : selectedTrend == "weekly"
        ? ["W1", "W2", "W3", "W4"]
        : ["M1", "M2", "M3"];

    final spots = List.generate(
      trendData.length,
      (index) => FlSpot(index.toDouble(), trendData[index].toDouble()),
    );

    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart_rounded, color: Colors.cyanAccent),
                const SizedBox(width: 10),
                const Text(
                  "Overall Usage Trend",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _trendLabel(selectedTrend),
              style: TextStyle(color: Colors.blueGrey[300], fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _buildTrendChip("daily", "Daily"),
                _buildTrendChip("weekly", "Weekly"),
                _buildTrendChip("monthly", "Monthly"),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (trendData.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= labels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              labels[index],
                              style: const TextStyle(
                                color: Colors.blueGrey,
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
                      gradient: LinearGradient(colors: chartGradient),
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: Colors.cyanAccent,
                              strokeWidth: 2,
                              strokeColor: surfaceColor,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: chartGradient
                              .map((color) => color.withOpacity(0.18))
                              .toList(),
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
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

  Widget _buildTrendChip(String key, String label) {
    final isSelected = selectedTrend == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : Colors.white70,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: Colors.cyanAccent,
      backgroundColor: surfaceColorAlt,
      side: BorderSide(color: isSelected ? Colors.cyanAccent : Colors.white12),
      onSelected: (_) {
        setState(() {
          selectedTrend = key;
        });
      },
    );
  }

  Widget _buildStockSummaryCard() {
    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                SizedBox(width: 10),
                Text(
                  "Stock Summary",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  title: "Critical",
                  value: "${stockSummary['critical'] ?? 0}",
                  subtitle: "Needs attention now",
                  accentColor: Colors.redAccent,
                ),
                _SummaryCard(
                  title: "Low",
                  value: "${stockSummary['low'] ?? 0}",
                  subtitle: "Plan replenishment",
                  accentColor: Colors.orangeAccent,
                ),
                _SummaryCard(
                  title: "Safe",
                  value: "${stockSummary['safe'] ?? 0}",
                  subtitle: "Healthy inventory",
                  accentColor: Colors.greenAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsCard() {
    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.local_fire_department, color: Colors.orangeAccent),
                SizedBox(width: 10),
                Text(
                  "Top Dispensed Products",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (topProducts.isEmpty)
              Text(
                "No usage data available yet.",
                style: TextStyle(color: Colors.blueGrey[300]),
              )
            else
              ...List.generate(topProducts.length, (index) {
                final product = topProducts[index];
                final isTopItem = index == 0;

                return Container(
                  margin: EdgeInsets.only(
                    bottom: index == topProducts.length - 1 ? 0 : 10,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isTopItem
                        ? Colors.cyanAccent.withOpacity(0.12)
                        : surfaceColorAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isTopItem ? Colors.cyanAccent : Colors.white10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isTopItem ? Colors.cyanAccent : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "#${index + 1}",
                          style: TextStyle(
                            color: isTopItem ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          product['item_name'] ?? "Unknown",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        "${product['total_used'] ?? 0}",
                        style: TextStyle(
                          color: isTopItem
                              ? Colors.cyanAccent
                              : Colors.blueGrey[200],
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightMessageCard() {
    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.psychology_alt_outlined,
                color: Colors.cyanAccent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Smart AI Insight",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    insightMessage.isEmpty
                        ? "No AI message available right now."
                        : insightMessage,
                    style: TextStyle(color: Colors.blueGrey[100], height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Search Medicines",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search by medicine name",
                hintStyle: TextStyle(color: Colors.blueGrey[400]),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.cyanAccent,
                ),
                filled: true,
                fillColor: surfaceColorAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicineListCard() {
    final items = filteredInventory;

    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Medicines",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Sorted by depletion risk and searchable in real time.",
              style: TextStyle(color: Colors.blueGrey[300], fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surfaceColorAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  "No medicines match your search.",
                  style: TextStyle(color: Colors.blueGrey[200]),
                ),
              )
            else
              ListView.separated(
                itemCount: items.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = items[index];
                  final statusColor = _statusColorForItem(data);
                  final hasWarning = data['has_epidemic_warning'] == true;

                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MedicineDetailPage(
                            clinicId: widget.clinicId,
                            itemData: Map<String, dynamic>.from(data),
                            chartGradient: chartGradient,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surfaceColorAlt,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withOpacity(0.45),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['item_name'] ?? "Unknown",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Current stock: ${data['current_stock'] ?? 0}",
                                  style: TextStyle(
                                    color: Colors.blueGrey[300],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasWarning)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: Icon(
                                Icons.bolt_rounded,
                                color: Colors.yellowAccent,
                              ),
                            ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white38,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
} // End AIInsightsPage

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color accentColor;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _AIInsightsPageState.surfaceColorAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.blueGrey[200],
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.blueGrey[300], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class MedicineDetailPage extends StatefulWidget {
  final String clinicId;
  final Map<String, dynamic> itemData;
  final List<Color> chartGradient;

  const MedicineDetailPage({
    super.key,
    required this.clinicId,
    required this.itemData,
    required this.chartGradient,
  });

  @override
  State<MedicineDetailPage> createState() => _MedicineDetailPageState();
}

class _MedicineDetailPageState extends State<MedicineDetailPage> {
  final String baseUrl = "http://localhost:5000";

  Future<void> sendRequestToTransfer(
    String itemName,
    int quantity,
    String donorClinicId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/pkd/request_transfer"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "clinic_id": widget.clinicId,
          "from_clinic": donorClinicId,
          "item_name": itemName,
          "quantity": quantity,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Transfer request sent to $donorClinicId."),
            backgroundColor: Colors.amber,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Unable to send transfer request."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      print("ERROR transfer request: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to connect."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void showTransferConfirmDialog(
    String itemName,
    int recommendedQty,
    String donorClinicId,
  ) {
    final qtyController = TextEditingController(
      text: recommendedQty.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _AIInsightsPageState.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          "Confirm Transfer Request",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Request $itemName from $donorClinicId instead of placing a fresh order.",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Transfer quantity",
                labelStyle: const TextStyle(color: Colors.amberAccent),
                filled: true,
                fillColor: _AIInsightsPageState.surfaceColorAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final quantity =
                  int.tryParse(qtyController.text) ?? recommendedQty;
              sendRequestToTransfer(itemName, quantity, donorClinicId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text(
              "Request Transfer",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Color getStatusColor(int runOutDays) {
    if (runOutDays > 0 && runOutDays <= 7) return Colors.redAccent;
    if (runOutDays > 7 && runOutDays <= 14) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  Widget buildMetricCard(
    String title,
    String value,
    String subtitle,
    Color glowColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _AIInsightsPageState.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: glowColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.12),
            blurRadius: 18,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.blueGrey[300],
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: glowColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildChart(List<int> forecastData) {
    if (forecastData.isEmpty || forecastData.every((value) => value == 0)) {
      return const Center(
        child: Text(
          "Insufficient historical data to graph.",
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    double maxY = forecastData
        .reduce((current, next) => current > next ? current : next)
        .toDouble();
    maxY = maxY < 50 ? 50 : maxY * 1.2;

    final spots = List.generate(
      forecastData.length,
      (index) => FlSpot(index.toDouble(), forecastData[index].toDouble()),
    );

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white10, strokeWidth: 1, dashArray: [5, 5]),
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
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Day ${value.toInt() + 1}",
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 4,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (forecastData.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            gradient: LinearGradient(colors: widget.chartGradient),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 4,
                    color: Colors.cyanAccent,
                    strokeWidth: 2,
                    strokeColor: _AIInsightsPageState.surfaceColor,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: widget.chartGradient
                    .map((color) => color.withOpacity(0.2))
                    .toList(),
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.itemData;
    final isCompact = MediaQuery.of(context).size.width < 760;
    final itemName = data['item_name'] ?? "Unknown";
    final currentStock = data['current_stock'] ?? 0;
    final runOutDays = data['run_out_days'] ?? -1;
    final runOutDate = data['run_out_date'] ?? "Safe (>30 Days)";
    final recommendQty = data['recommend_order'] ?? 0;
    final hasWarning = data['has_epidemic_warning'] == true;
    final weatherWarning = data['weather_warning'] ?? "";
    final hasWeatherWarning = weatherWarning.isNotEmpty;
    final transferCandidates = data['transfer_candidates'] ?? [];
    final forecastData = List<int>.from(data['forecast_7_days'] ?? []);

    final hasTransferCandidate = transferCandidates.isNotEmpty;
    final bestDonor = hasTransferCandidate ? transferCandidates.first : null;

    var statusColor = getStatusColor(runOutDays);
    var daysText = "Safe Stock";
    if (runOutDays > 0 && runOutDays <= 7) {
      daysText = "$runOutDays Days Left!";
    } else if (runOutDays > 7 && runOutDays <= 14) {
      daysText = "$runOutDays Days Left";
    }

    return Scaffold(
      backgroundColor: _AIInsightsPageState.pageBackground,
      appBar: AppBar(
        backgroundColor: _AIInsightsPageState.pageBackground,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text("Medicine Insight"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "AI Forecast and depletion analysis",
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 14),
                ),
                if (hasWarning) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "Epidemic Spike Detected",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            if (hasWeatherWarning)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_sync_rounded,
                      color: Colors.blueAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        weatherWarning,
                        style: TextStyle(
                          color: Colors.blue[100],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 260,
                  child: buildMetricCard(
                    "Run-Out Date",
                    runOutDate,
                    daysText,
                    statusColor,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: buildMetricCard(
                    "Current Stock",
                    "$currentStock Units",
                    "In inventory",
                    Colors.white,
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: buildMetricCard(
                    "Recommended Order",
                    "+$recommendQty",
                    "To reach 30-day safety",
                    Colors.cyanAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _AIInsightsPageState.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "7-Day Trajectory",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(height: 280, child: buildChart(forecastData)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (recommendQty > 0 && hasTransferCandidate)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.amber.withOpacity(0.35)),
                ),
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.compare_arrows_rounded,
                            color: Colors.amber,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            "Transfer Recommendation",
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Neighboring clinic '${bestDonor['clinic_id']}' has a surplus of ${bestDonor['surplus_stock']} units.",
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                showTransferConfirmDialog(
                                  itemName,
                                  recommendQty,
                                  bestDonor['clinic_id'],
                                );
                              },
                              icon: const Icon(Icons.outbond_rounded),
                              label: const Text("Request Transfer"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Icon(
                            Icons.compare_arrows_rounded,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Transfer Recommendation",
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Neighboring clinic '${bestDonor['clinic_id']}' has a surplus of ${bestDonor['surplus_stock']} units.",
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              showTransferConfirmDialog(
                                itemName,
                                recommendQty,
                                bestDonor['clinic_id'],
                              );
                            },
                            icon: const Icon(Icons.outbond_rounded),
                            label: const Text("Request Transfer"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _AIInsightsPageState.surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Text(
                  "Order generation now happens in the Suggested Orders tab. Use this page for monitoring and analysis.",
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
