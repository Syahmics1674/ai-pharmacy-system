import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'order_history_page.dart';

void main() {
  runApp(MaterialApp(
    home: LoginPage(),
  ));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Pharmacy',
      home: LoginPage(),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String clinicId;

  const MainScreen({Key? key, required this.clinicId}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String clinicName = "";

  final homeKey = GlobalKey<HomePageState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // 🔥 When user goes back to HomePage → refresh
    if (index == 0) {
      homeKey.currentState?.refreshAll();
    }
  }

  Future<void> fetchClinicName() async {
    final response = await http.get(
      Uri.parse("http://localhost:5000/clinic_info?clinic_id=${widget.clinicId}")
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
    
    final List<Widget> _pages = [
      HomePage(key: homeKey, clinicId: widget.clinicId),
      StockOperationsPage(clinicId: widget.clinicId),
      AIInsightsPage(),
      OrderPage(clinicId: widget.clinicId),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
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

      body: _pages[_selectedIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Inventory"),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: "Operations"),
          BottomNavigationBarItem(icon: Icon(Icons.insights), label: "AI Insights"),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Orders"),
        ],
      ),
    );
  }
}

// ================= LOGIN PAGE =================
class LoginPage extends StatefulWidget {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed ❌")),
      );
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
                  child: Text(
                    "Login",
                    style: TextStyle(fontSize: 16),
                  ),
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

  const HomePage({Key? key, required this.clinicId}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {

  final String baseUrl = "http://localhost:5000"; // ⚠️ Chrome OK, macOS NOT OK

  List inventory = [];
  List suggestions = [];
  String consolidatedDate = "";
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
    final response = await http.get(Uri.parse("$baseUrl/order_suggestions?clinic_id=${widget.clinicId}"));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        suggestions = data['order_suggestions'];
      });
    }
  }

  Future<void> fetchConsolidation() async {
    final response = await http.get(Uri.parse("$baseUrl/consolidate?clinic_id=${widget.clinicId}"));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        consolidatedDate = data['consolidated_date'];
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Inventory", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),

                    ...inventory.map((item) => Card(
                      color: item['current_stock'] < 100 ? Colors.red[50] : Colors.grey[100],
                      child: ListTile(
                        title: Text(item['item_name']),
                        subtitle: item['current_stock'] < 100
                          ? Text(
                            "⚠ Low Stock",
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            )
                          : null,
                        trailing: Text(
                          "Stock: ${item['current_stock']}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: item['current_stock'] < 100 ? Colors.red : Colors.black,
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 🔷 ORDER SUGGESTIONS
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Order Suggestions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),

                    ...suggestions.map((item) => ListTile(
                      title: Text(item['item_name']),
                      subtitle: Text("Qty: ${item['suggested_qty']} | ${item['priority']}"),
                    )),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 🔷 NEXT ORDER DATE
            Card(
              elevation: 3,
              color: Colors.blue[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text("Next Order Date", style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      consolidatedDate,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
}

// ================= STOCK OPERATIONS PAGE =================

class StockOperationsPage extends StatefulWidget {
  final String clinicId;

  const StockOperationsPage({Key? key, required this.clinicId}) : super(key: key);

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Stock-in successful ✅")),
        );

        refreshAll();

      } else {
        // ❌ BACKEND ERROR
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Operation failed ❌")),
        );
      }

    } catch (e) {
      // ❌ NETWORK ERROR
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection error ❌")),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Stock-out successful ✅")),
        );

        refreshAll();
      
      } else {
        // ❌ ERROR FROM BACKEND
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Operation failed ❌")),
        );
      }
    } catch (e) {
      // ❌ NETWORK ERROR
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection error ❌")),
      );
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
                value: selectedItem,
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
            if (isLoading)
              Center(child: CircularProgressIndicator()),

          ],
        ),
      ),
    );
  }
}

// ================= AI INSIGHTS PAGE ================= by Wafiy

class AIInsightsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text("AI Insights Page"));
  }
}

// ================= ORDER PAGE =================

class OrderPage extends StatefulWidget {
  final String clinicId;

  const OrderPage({Key? key, required this.clinicId}) : super(key: key);

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

  // 🔥 GENERATE ORDER
  Future<void> generateOrder() async {
    if (isLoading) return;
    try {
      final url = Uri.parse('$baseUrl/generate_order');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "clinic_id": widget.clinicId,
          "items": suggestions.map((item) {
            return {
              "item_name": item['item_name'],
              "qty": item['suggested_qty'],
            };
          }).toList()
        }),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode == 200) {
        setState(() {
          suggestions = [];   // ✅ CLEAR LIST
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Order generated successfully ✅")),
        );
      } 
      else {
        throw Exception("Failed");
      }

    } catch (e) {
      print("ERROR: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to generate order ❌")),
      );
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
              
              ...suggestions.map((item) => Text(
                "• ${item['item_name']} — ${item['suggested_qty']}"
              )),
              Text("Total: $totalQty items"),

              SizedBox(height: 10),
              Text("Proceed?")
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

  @override
  void initState() {
    super.initState();
    fetchAll();
  }

  Future<void> fetchAll() async {
    await fetchSuggestions();
    await fetchConsolidation();
  }

  Future<void> fetchSuggestions() async {
    final response = await http.get(
      Uri.parse("$baseUrl/order_suggestions?clinic_id=${widget.clinicId}"));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      setState(() {
        suggestions = data['order_suggestions'];
      });
    }
  }

  Future<void> fetchConsolidation() async {
    final response = await http.get(
      Uri.parse("$baseUrl/consolidate?clinic_id=${widget.clinicId}"));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      setState(() {
        consolidatedDate = data['consolidated_date'];
        basedOn = data['based_on'];
        details = data['details'];
      });
    }
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Suggested Orders",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),

                    ...suggestions.map((item) => ListTile(
                      leading: Icon(Icons.medication),
                      title: Text(item['item_name']),
                      subtitle: Text("Priority: ${item['priority']}"),
                      trailing: Text(
                        "Qty: ${item['suggested_qty']}",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // 🔷 CONSOLIDATED DATE
            Card(
              elevation: 3,
              color: Colors.blue[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text("Next Order Date", style: TextStyle(fontSize: 18)),
                    SizedBox(height: 8),
                    Text(
                      consolidatedDate,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // REASON CARD
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Based on: $basedOn priority",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    Text("Clinic Breakdown",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),

                    ...details.map((d) => ListTile(
                          title: Text(d['clinic']),
                          subtitle: Text("Date: ${d['date']}"),
                          trailing: Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: getPriorityColor(d['priority']).withOpacity(0.2),
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
                        )),
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
                    builder: (_) => OrderHistoryPage(
                      clinicId: widget.clinicId,
                    ),
                  ),
                );
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
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 10),

                      ...generatedOrders.map((item) => ListTile(
                            title: Text(item['item_name']),
                            trailing: Text(
                              "Qty: ${item['suggested_qty']}",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          )),
                    ],
                  ),
                ),
              ),

            // 🔄 LOADING
            if (isLoading)
              Center(child: CircularProgressIndicator()),

          ],
        ),
      ),
    );
  }
}

