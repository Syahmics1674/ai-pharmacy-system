import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'order_history_page.dart';
import 'pkd_dashboard_page.dart';
import 'dashboard_page.dart';
import 'live_inventory_page.dart';
import 'services/sync_service.dart';

// Client-side API response cache
final _apiCache = <String, _CacheEntry>{};
final _inflightRequests = <String, Future<Map<String, dynamic>>>{};
const _defaultCacheTtl = Duration(seconds: 30);

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}

Map<String, dynamic>? _getCached(String key) {
  final entry = _apiCache[key];
  if (entry == null) return null;
  if (DateTime.now().isAfter(entry.expiresAt)) {
    _apiCache.remove(key);
    return null;
  }
  return entry.data;
}

void _setCache(String key, Map<String, dynamic> data, {Duration ttl = _defaultCacheTtl}) {
  _apiCache[key] = _CacheEntry(data, DateTime.now().add(ttl));
}

String _cacheKey(String url) => url;

Future<Map<String, dynamic>> safeApiGet(String url, {Duration timeout = const Duration(seconds: 8), Duration? cacheTtl}) async {
  final key = _cacheKey(url);
  final cached = _getCached(key);
  if (cached != null) return cached;

  final inflight = _inflightRequests[key];
  if (inflight != null) return inflight;

  final future = _doApiGet(url, timeout);
  _inflightRequests[key] = future;
  try {
    final result = await future;
    if (cacheTtl != null) {
      _setCache(key, result, ttl: cacheTtl);
    }
    return result;
  } finally {
    _inflightRequests.remove(key);
  }
}

Future<Map<String, dynamic>> _doApiGet(String url, Duration timeout) async {
  final response = await http.get(Uri.parse(url)).timeout(timeout);
  if (response.statusCode == 200) {
    return json.decode(response.body) as Map<String, dynamic>;
  }
  final body = json.decode(response.body);
  throw Exception(body['error'] ?? "HTTP ${response.statusCode}");
}

String medicineIdOf(dynamic item) {
  if (item is Map) {
    return (
      item['item_code'] ??
      item['medicine_id'] ??
      ''
    ).toString();
  }
  return '';
}

String itemNameOf(dynamic item) {
  if (item is Map) {
    return (item['item_name'] ?? item['name'] ?? 'Unknown Medicine').toString();
  }
  return 'Unknown Medicine';
}

String liveInventoryDisplayName(Map item) {
  final fullBrandName = (item['full_brand_name'] ?? '').toString().trim();
  if (fullBrandName.isNotEmpty) return fullBrandName;

  final brandName = (item['brand_name'] ?? '').toString().trim();
  if (brandName.isNotEmpty) return brandName;

  final matchName = (item['match_name'] ?? '').toString().trim();
  if (matchName.isNotEmpty) return matchName;

  final genericName = (item['generic_name'] ?? '').toString().trim();
  if (genericName.isNotEmpty) {
    final strength = (item['strength'] ?? '').toString().trim();
    final dosageForm = (item['dosage_form'] ?? '').toString().trim();
    return [genericName, strength, dosageForm]
        .where((p) => p.isNotEmpty)
        .join(' ');
  }

  final itemCode = (item['item_code'] ?? '').toString().trim();
  if (itemCode.isNotEmpty) return itemCode;

  return 'Unknown';
}

String itemCategoryOf(dynamic item) {
  if (item is Map) {
    return (item['category'] ?? 'Uncategorized').toString();
  }
  return 'Uncategorized';
}

int itemQuantityOf(dynamic item, {List<String> keys = const ['qty']}) {
  if (item is! Map) return 0;

  for (final key in keys) {
    final value = item[key];
    if (value is int) return value;
    if (value != null) {
      return int.tryParse(value.toString()) ?? 0;
    }
  }
  return 0;
}

Future<Map<String, dynamic>> safeApiPost(String url, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 8)}) async {
  final response = await http
      .post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      )
      .timeout(timeout);
  if (response.statusCode == 200) {
    return json.decode(response.body) as Map<String, dynamic>;
  }
  final errBody = json.decode(response.body);
  throw Exception(errBody['error'] ?? "HTTP ${response.statusCode}");
}

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

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String clinicName = "";
  String clinicDistrict = "";
  bool _isSyncing = false;

  final homeKey = GlobalKey<_InventoryPageState>();
  final orderKey = GlobalKey<_OrderPageState>();
  final dashboardKey = GlobalKey<DashboardPageState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      dashboardKey.currentState?.fetchDashboardData();
    }

    if (index == 2) {
      homeKey.currentState?.refreshAll();
    }

    if (index == 5) {
      orderKey.currentState?.refreshOrderPage();
    }
  }

  Future<void> fetchClinicInfo() async {
    final response = await http.get(
      Uri.parse(
        "http://localhost:5000/clinic_info?clinic_id=${widget.clinicId}",
      ),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        clinicName = data['clinic_name'] ?? widget.clinicId;
        clinicDistrict = data['district'] ?? "";
      });
    }
  }

  void _performLogout() {
    _apiCache.clear();
    _inflightRequests.clear();
    SyncService.clear();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
      (route) => false,
    );
  }

  final List<String> _pageTitles = [
    "Dashboard",
    "Live Inventory",
    "Inventory",
    "Stock Operations",
    "AI Insights",
    "Order Management",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchClinicInfo();
    _initSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSync();
    }
  }

  Future<void> _initSync() async {
    await SyncService.initialize(widget.clinicId);
    await _runSync();
  }

  Future<void> _runSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    await SyncService.fullSync(widget.clinicId);
    if (mounted) setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardPage(
        key: dashboardKey,
        clinicId: widget.clinicId,
        onLogout: _performLogout,
        onNavigateInventory: () => setState(() => _selectedIndex = 2),
        onNavigateOperations: () => setState(() => _selectedIndex = 3),
        onNavigateOrders: () => setState(() => _selectedIndex = 5),
        onNavigateReports: () => setState(() => _selectedIndex = 4),
      ),
      LiveInventoryPage(clinicId: widget.clinicId),
      InventoryPage(key: homeKey, clinicId: widget.clinicId),
      StockOperationsPage(clinicId: widget.clinicId),
      AIInsightsPage(clinicId: widget.clinicId),
      OrderPage(key: orderKey, clinicId: widget.clinicId),
    ];

    return Scaffold(
      appBar: _selectedIndex == 0
          ? null
          : AppBar(
              title: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _selectedIndex = 0),
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
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: "Dashboard",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.medication),
            label: "Live",
          ),
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
  final List<String> loginRoles = ["Clinic", "PKD"];

  TextEditingController userController = TextEditingController();
  TextEditingController passController = TextEditingController();
  bool isLoading = false;
  bool isPasswordVisible = false;
  String selectedRole = "Clinic";

  Future<void> login() async {
    final userId = userController.text.trim();
    final password = passController.text;

    if (userId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter user ID and password")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/login"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"user_id": userId, "password": password}),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (!mounted) return;

      if (response.statusCode == 200 && data["success"] == true) {
        final role = (data["role"] ?? "").toString().toLowerCase();
        final expectedRole = selectedRole.toLowerCase();

        if (role != expectedRole) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Incorrect role selected")));
          return;
        }

        if (role == "pkd") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PKDDashboardPage(
                district: (data["district"] ?? "").toString(),
              ),
            ),
          );
          return;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MainScreen(clinicId: (data["clinic_id"] ?? "").toString()),
          ),
        );
      } else {
        final errorMessage = (data["error"] ?? "Login failed").toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$errorMessage ❌")));
      }
    } catch (e) {
      if (!mounted) return;
      String message = "Unable to connect to backend ❌";
      if (e.toString().contains("Timeout")) {
        message = "Server timeout. Please try again ⏳";
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
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
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 30),

              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: InputDecoration(
                  labelText: "Role",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: loginRoles
                    .map(
                      (role) => DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    selectedRole = value;
                  });
                },
              ),

              SizedBox(height: 15),

              // 🔷 USERNAME
              TextField(
                controller: userController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: selectedRole == "PKD"
                      ? "PKD User ID"
                      : "Clinic User ID",
                  hintText: selectedRole == "PKD"
                      ? "pkd_kapit"
                      : "clinic_bangkit",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              SizedBox(height: 15),

              // 🔷 PASSWORD
              TextField(
                controller: passController,
                obscureText: !isPasswordVisible,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => login(),
                decoration: InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        isPasswordVisible = !isPasswordVisible;
                      });
                    },
                  ),
                ),
              ),

              SizedBox(height: 25),

              // 🔥 LOGIN BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : login,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text("Login", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= INVENTORY PAGE (ENHANCED) =================

class InventoryPage extends StatefulWidget {
  final String clinicId;

  const InventoryPage({super.key, required this.clinicId});

  @override
  _InventoryPageState createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final String baseUrl = "http://localhost:5000";

  List inventory = [];
  bool isLoading = false;
  String clinicName = "";

  String searchQuery = "";
  String _filterOption = "All";

  List<String> filterOptions = [
    "All",
    "Low Stock",
    "Expired",
    "Expiring Soon",
    "Safe",
  ];

  @override
  void initState() {
    super.initState();
    fetchInventory();
  }

  Future<void> fetchInventory() async {
    setState(() => isLoading = true);
    try {
      final data = await safeApiGet("$baseUrl/inventory?clinic_id=${widget.clinicId}");
      setState(() {
        inventory = data['inventory'] ?? [];
        clinicName = data["clinic_name"] ?? widget.clinicId;
      });
    } catch (e) {
      print("ERROR: $e");
    }
    if (mounted) setState(() => isLoading = false);
  }

  void refreshAll() {
    fetchInventory();
  }

  List get _filteredInventory {
    var items = inventory;

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      items = items.where((item) {
        return itemNameOf(item).toLowerCase().contains(q) ||
            medicineIdOf(item).toLowerCase().contains(q) ||
            (item['category'] ?? '').toString().toLowerCase().contains(q) ||
            (item['batch_no'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }

    switch (_filterOption) {
      case "Low Stock":
        items = items.where((i) => (i['current_stock'] ?? 0) < 100).toList();
        break;
      case "Expired":
        items = items.where((i) => i['expiry_status'] == 'expired').toList();
        break;
      case "Expiring Soon":
        items = items.where(
            (i) => i['expiry_status'] == 'expiring_soon').toList();
        break;
      case "Safe":
        items = items.where(
            (i) => i['expiry_status'] == 'safe' || i['expiry_status'] == 'warning').toList();
        break;
    }

    items.sort((a, b) {
      final aExp = a['expiry_status'] ?? 'safe';
      final bExp = b['expiry_status'] ?? 'safe';
      if (aExp == 'expired' && bExp != 'expired') return -1;
      if (aExp != 'expired' && bExp == 'expired') return 1;
      if (aExp == 'expiring_soon' && bExp != 'expiring_soon' && bExp != 'expired') return -1;
      if (aExp != 'expiring_soon' && aExp != 'expired' && bExp == 'expiring_soon') return 1;
      return (a['current_stock'] ?? 0).compareTo(b['current_stock'] ?? 0);
    });

    return items;
  }

  int get _expiredCount =>
      inventory.where((i) => i['expiry_status'] == 'expired').length;
  int get _expiringSoonCount =>
      inventory.where((i) => i['expiry_status'] == 'expiring_soon').length;
  int get _safeCount =>
      inventory.where((i) => i['expiry_status'] == 'safe' || i['expiry_status'] == 'warning' || i['expiry_status'] == 'unknown').length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredInventory;
    final expiredCount = _expiredCount;
    final expiringSoonCount = _expiringSoonCount;
    final safeCount = _safeCount;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: fetchInventory,
        child: Column(
          children: [
            // Search bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search by name, ID, category, batch...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
            ),

            // Filters row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  ...filterOptions.map((f) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(f, style: const TextStyle(fontSize: 11)),
                          selected: _filterOption == f,
                          onSelected: (_) => setState(() => _filterOption = f),
                          selectedColor: Colors.blueAccent.withOpacity(0.2),
                          checkmarkColor: Colors.blueAccent,
                          visualDensity: VisualDensity.compact,
                        ),
                      )),
                ],
              ),
            ),

            // Expiry summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _expiryChip("Expired", expiredCount, Colors.red.shade700),
                  const SizedBox(width: 8),
                  _expiryChip("Expiring Soon", expiringSoonCount, Colors.orange),
                  const SizedBox(width: 8),
                  _expiryChip("Safe", safeCount, Colors.green),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Inventory list
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2,
                                  size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                searchQuery.isNotEmpty ||
                                        _filterOption != "All"
                                    ? "No medicines match your filter."
                                    : "No inventory data available.",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final item = filtered[i];
                            final stock = item['current_stock'] ?? 0;
                            final expiryStatus =
                                item['expiry_status'] ?? 'unknown';
                            final daysRemaining =
                                item['days_remaining'];
                            final batchNo =
                                item['batch_no'] ?? '';

                            Color riskColor;
                            String riskLabel;
                            if (expiryStatus == 'expired') {
                              riskColor = Colors.red.shade700;
                              riskLabel = "Expired";
                            } else if (expiryStatus == 'expiring_soon') {
                              riskColor = Colors.red;
                              riskLabel =
                                  "$daysRemaining days";
                            } else if (expiryStatus == 'warning') {
                              riskColor = Colors.orange;
                              riskLabel =
                                  "$daysRemaining days";
                            } else {
                              riskColor = Colors.green;
                              riskLabel = expiryStatus == 'unknown'
                                  ? "No expiry data"
                                  : "Safe";
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            itemNameOf(item),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (batchNo.isNotEmpty) ...[
                                                Text(
                                                  "Batch: $batchNo",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                              ],
                                              Text(
                                                itemCategoryOf(item),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (stock < 100)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                "⚠ Low Stock",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: riskColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            riskLabel,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: riskColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "Stock: $stock",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: stock < 100
                                                ? Colors.red
                                                : Colors.black87,
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
          ],
        ),
      ),
    );
  }

  Widget _expiryChip(String label, int count, Color color) {
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
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
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

  Map<String, dynamic>? findInventoryItem(String? itemKey) {
    if (itemKey == null) return null;

    for (final dynamic entry in inventory) {
      final key = medicineIdOf(entry);
      if (key == itemKey) {
        return Map<String, dynamic>.from(entry as Map);
      }
    }
    return null;
  }

  Future<void> stockIn(Map<String, dynamic> item, int qty) async {
    setState(() => isLoading = true);
    try {
      await safeApiPost("$baseUrl/stock_in", {
        "clinic_id": widget.clinicId,
        "item_code": medicineIdOf(item),
        "item_name": itemNameOf(item),
        "quantity_added": qty,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Stock-in successful ✅")),
        );
      }
      refreshAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll("Exception: ", "") + " ❌")),
        );
      }
    }
    setState(() => isLoading = false);
  }

  Future<void> stockOut(Map<String, dynamic> item, int qty) async {
    setState(() => isLoading = true);
    try {
      await safeApiPost("$baseUrl/stock_out", {
        "clinic_id": widget.clinicId,
        "item_code": medicineIdOf(item),
        "item_name": itemNameOf(item),
        "quantity_used": qty,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Stock-out successful ✅")),
        );
      }
      refreshAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll("Exception: ", "") + " ❌")),
        );
      }
    }
    setState(() => isLoading = false);
  }

  Future<void> fetchInventory() async {
    try {
      final data = await safeApiGet("$baseUrl/inventory?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          inventory = data['inventory'] ?? [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load inventory: $e")),
        );
      }
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
                    value: medicineIdOf(item),
                    child: Text(itemNameOf(item)),
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
                final item = findInventoryItem(selectedItem);
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

                await stockIn({
                  "item_name": name,
                  "item_code": "",
                }, qty); // reuse existing API

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

// ================= AI INSIGHTS PAGE (MAIN DASHBOARD) =================

class AIInsightsPage extends StatefulWidget {
  final String clinicId;

  const AIInsightsPage({super.key, required this.clinicId});

  @override
  _AIInsightsPageState createState() => _AIInsightsPageState();
}

class _AIInsightsPageState extends State<AIInsightsPage> {
  final String baseUrl = "http://localhost:5000";
  final List<Color> chartGradient = [
    const Color(0xff23b6e6),
    const Color(0xff02d39a),
  ];

  bool isLoading = true;

  // Dashboard data
  List<int> dailyUsage = [];
  List<int> weeklyUsage = [];
  List<int> monthlyUsage = [];
  Map<String, dynamic> stockSummary = {};
  List<Map<String, dynamic>> topProducts = [];
  String insightMessage = "";

  // Medicine list data
  List<dynamic> smartInventory = [];
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    fetchAll();
  }

  Future<void> fetchAll() async {
    setState(() => isLoading = true);
    await Future.wait([
      fetchUsage(),
      fetchStockSummary(),
      fetchTopProducts(),
      fetchInsightMessage(),
      fetchSmartInventory(),
    ]);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> fetchUsage() async {
    try {
      final data = await safeApiGet("$baseUrl/ai/overall_usage?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          dailyUsage = List<int>.from(data['daily'] ?? []);
          weeklyUsage = List<int>.from(data['weekly'] ?? []);
          monthlyUsage = List<int>.from(data['monthly'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> fetchStockSummary() async {
    try {
      final data = await safeApiGet("$baseUrl/ai/stock_summary?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          stockSummary = Map<String, dynamic>.from(data);
        });
      }
    } catch (_) {}
  }

  Future<void> fetchTopProducts() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/ai/top_products?clinic_id=${widget.clinicId}"),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final raw = json.decode(response.body) as List;
        if (mounted) {
          setState(() {
            topProducts = raw.cast<Map<String, dynamic>>();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> fetchInsightMessage() async {
    try {
      final data = await safeApiGet("$baseUrl/ai/insight_message?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          insightMessage = data['message'] ?? "";
        });
      }
    } catch (_) {}
  }

  Future<void> fetchSmartInventory() async {
    try {
      final data = await safeApiGet("$baseUrl/ai/smart_inventory?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          smartInventory = data['smart_inventory'] ?? [];
        });
      }
    } catch (e) {
      print("ERROR Smart Inventory: $e");
    }
  }

  List<dynamic> get _filteredInventory {
    if (searchQuery.isEmpty) return smartInventory;
    return smartInventory.where((item) {
      return itemNameOf(item).toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
  }

  // ---- BUILD ----
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        color: const Color(0xFF0F172A),
        child: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0F172A),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔷 SECTION TITLE
            Text(
              "AI Insights Dashboard",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Overall analytics, trends, and medicine insights",
              style: TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // ═══════════════════════════════════
            // PART 2: OVERALL USAGE CHART
            // ═══════════════════════════════════
            _buildOverallUsageSection(),

            const SizedBox(height: 20),

            // ═══════════════════════════════════
            // STOCK SUMMARY CARDS
            // ═══════════════════════════════════
            _buildStockSummarySection(),

            const SizedBox(height: 20),

            // ═══════════════════════════════════
            // TOP PRODUCTS + INSIGHT MESSAGE
            // ═══════════════════════════════════
            _buildTopProductsSection(),

            const SizedBox(height: 20),

            // ═══════════════════════════════════
            // INSIGHT MESSAGE CARD
            // ═══════════════════════════════════
            if (insightMessage.isNotEmpty) ...[
              _buildInsightMessageCard(),
              const SizedBox(height: 20),
            ],

            // ═══════════════════════════════════
            // PART 3: SEARCH BAR
            // ═══════════════════════════════════
            _buildSearchBar(),

            const SizedBox(height: 12),

            // ═══════════════════════════════════
            // PART 4: MEDICINE LIST
            // ═══════════════════════════════════
            Text(
              "Medicines (${_filteredInventory.length})",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Sorted by depletion risk — tap for details",
              style: TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
            const SizedBox(height: 12),

            ..._filteredInventory.map((item) => _buildMedicineTile(item)),

            if (_filteredInventory.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                child: Text(
                  "No medicines match your search.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- OVERALL USAGE SECTION ----
  Widget _buildOverallUsageSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                "Usage Trends",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildMiniChart("Daily (7 days)", dailyUsage, Colors.cyanAccent)),
              const SizedBox(width: 12),
              Expanded(child: _buildMiniChart("Weekly (4 weeks)", weeklyUsage, Colors.amberAccent)),
              const SizedBox(width: 12),
              Expanded(child: _buildMiniChart("Monthly (3 months)", monthlyUsage, Colors.greenAccent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChart(String label, List<int> values, Color color) {
    if (values.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text("No data", style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
      );
    }

    final maxVal = values.reduce((a, b) => a > b ? a : b).toDouble();
    final effectiveMax = maxVal < 1 ? 1.0 : maxVal * 1.2;

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: effectiveMax,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              barGroups: List.generate(values.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i].toDouble(),
                      color: color,
                      width: 8,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ---- STOCK SUMMARY SECTION ----
  Widget _buildStockSummarySection() {
    final critical = stockSummary['critical'] ?? 0;
    final low = stockSummary['low'] ?? 0;
    final safe = stockSummary['safe'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            "Critical",
            "$critical",
            "Items at risk",
            Colors.redAccent,
            Icons.error_outline_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            "Low Stock",
            "$low",
            "Items running low",
            Colors.orangeAccent,
            Icons.warning_amber_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            "Safe",
            "$safe",
            "Items well-stocked",
            Colors.greenAccent,
            Icons.check_circle_outline_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ---- TOP PRODUCTS ----
  Widget _buildTopProductsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                "Top Dispensed Products",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (topProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                "No usage data available yet.",
                style: TextStyle(color: Colors.white38),
              ),
            )
          else
            ...topProducts.asMap().entries.map((entry) {
              final i = entry.key;
              final product = entry.value;
              final name = product['item_name'] ?? 'Unknown';
              final totalUsed = product['total_used'] ?? 0;
              final isTop = i == 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isTop ? Colors.cyanAccent.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isTop ? Border.all(color: Colors.cyanAccent.withOpacity(0.3)) : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTop ? Colors.cyanAccent : Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "#${i + 1}",
                        style: TextStyle(
                          color: isTop ? Colors.black : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: isTop ? Colors.cyanAccent : Colors.white,
                          fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      "$totalUsed used",
                      style: TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ---- INSIGHT MESSAGE ----
  Widget _buildInsightMessageCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyanAccent.withOpacity(0.08),
            const Color(0xFF1E293B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.cyanAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "AI Recommendation",
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  insightMessage,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- SEARCH BAR ----
  Widget _buildSearchBar() {
    return TextField(
      onChanged: (v) => setState(() => searchQuery = v.trim()),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search medicine...",
        hintStyle: TextStyle(color: Colors.blueGrey),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.blueGrey),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
        ),
      ),
    );
  }

  // ---- MEDICINE LIST TILE ----
  Widget _buildMedicineTile(dynamic data) {
    final name = itemNameOf(data);
    final runOutDays = data['run_out_days'] ?? -1;
    final hasWarning = data['has_epidemic_warning'] ?? false;

    Color statusColor = Colors.greenAccent;
    if (runOutDays > 0 && runOutDays <= 7) {
      statusColor = Colors.redAccent;
    } else if (runOutDays > 7 && runOutDays <= 14) {
      statusColor = Colors.orangeAccent;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MedicineDetailPage(
              itemData: Map<String, dynamic>.from(data as Map),
              clinicId: widget.clinicId,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
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
                  BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (hasWarning)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.bolt, color: Colors.yellowAccent, size: 18),
              ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
} // End AIInsightsPage

// ================= MEDICINE DETAIL SUBPAGE =================

class MedicineDetailPage extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final String clinicId;

  const MedicineDetailPage({
    super.key,
    required this.itemData,
    required this.clinicId,
  });

  @override
  State<MedicineDetailPage> createState() => _MedicineDetailPageState();
}

class _MedicineDetailPageState extends State<MedicineDetailPage> {
  final List<Color> chartGradient = [
    const Color(0xff23b6e6),
    const Color(0xff02d39a),
  ];

  late Map<String, dynamic> data;

  @override
  void initState() {
    super.initState();
    data = widget.itemData;
  }

  @override
  Widget build(BuildContext context) {
    final itemName = itemNameOf(data);
    final currentStock = data['current_stock'] ?? 0;
    final runOutDays = data['run_out_days'] ?? -1;
    final runOutDate = data['run_out_date'] ?? "-";
    final recommendQty = data['recommend_order'] ?? 0;
    final surplusStock = data['surplus_stock'] ?? 0;
    final hasWarning = data['has_epidemic_warning'] ?? false;
    final weatherWarning = data['weather_warning'] ?? "";
    final hasWeatherWarning = weatherWarning.isNotEmpty;
    final forecastRaw = data['forecast_7_days'] ?? [];
    final forecastData = List<int>.from(forecastRaw);

    Color statusColor = Colors.greenAccent;
    String daysText = "Safe Stock";
    IconData statusIcon = Icons.check_circle_rounded;

    if (runOutDays > 0 && runOutDays <= 7) {
      statusColor = Colors.redAccent;
      daysText = "$runOutDays Days Left!";
      statusIcon = Icons.emergency_rounded;
    } else if (runOutDays > 7 && runOutDays <= 14) {
      statusColor = Colors.orangeAccent;
      daysText = "$runOutDays Days Left";
      statusIcon = Icons.warning_rounded;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(itemName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "AI Forecast & Depletion Analysis",
                        style: TextStyle(color: Colors.cyanAccent, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (surplusStock > 0)
                  _buildBadge("Surplus: +$surplusStock", Colors.greenAccent, Icons.inventory_2_rounded),
                if (hasWarning) ...[
                  const SizedBox(width: 8),
                  _buildBadge("Epidemic Spike", Colors.redAccent, Icons.bolt_rounded),
                ],
                if (runOutDays > 0 && runOutDays <= 14) ...[
                  const SizedBox(width: 8),
                  _buildBadge(daysText, statusColor, statusIcon),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Weather warning
            if (hasWeatherWarning) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_sync_rounded, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        weatherWarning,
                        style: TextStyle(color: Colors.blue[200], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Metric cards
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildMetricCard("Run-Out Date", runOutDate, daysText, statusColor)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard("Current Stock", "$currentStock Units", "In Inventory", Colors.white70)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard("Recommended Order", "+$recommendQty", "30-day safety stock", Colors.cyanAccent)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 7-Day Forecast Chart
            Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.show_chart_rounded, color: Colors.cyanAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        "7-Day Demand Trajectory",
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                        ),
                        child: const Text(
                          "AI Forecast",
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildChart(forecastData)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, Color glowColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glowColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.blueGrey[400], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: glowColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildChart(List<int> forecastData) {
    if (forecastData.isEmpty || forecastData.every((e) => e == 0)) {
      return Center(
        child: Text("Insufficient historical data to graph.", style: TextStyle(color: Colors.white54)),
      );
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
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.white10, strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
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
                radius: 4,
                color: Colors.cyanAccent,
                strokeWidth: 2,
                strokeColor: const Color(0xFF1E293B),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: chartGradient.map((c) => c.withOpacity(0.2)).toList(),
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
} // End MedicineDetailPage

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
        return {
          "item_code": medicineIdOf(item),
          "item_name": itemNameOf(item),
          "qty": item['suggested_qty'],
          "suggested_qty": item['suggested_qty'],
        };
      }).toList();
      await safeApiPost("$baseUrl/generate_order", {
        "clinic_id": widget.clinicId,
        "items": generatedItems,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Order generated successfully ✅")),
        );
      }
      await refreshOrderPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to generate order ❌")),
        );
      }
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
                    Text("• ${itemNameOf(item)} — ${item['suggested_qty']}"),
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
      final data = await safeApiGet("$baseUrl/clinic_info?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          clinicDisplayName = data['clinic_name'] ?? widget.clinicId;
        });
      }
    } catch (_) {}
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
    try {
      final data = await safeApiGet("$baseUrl/order_suggestions?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          suggestions = data['order_suggestions'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> fetchConsolidation() async {
    try {
      final data = await safeApiGet("$baseUrl/consolidate?clinic_id=${widget.clinicId}");
      if (mounted) {
        setState(() {
          consolidatedDate = data['consolidated_date'] ?? "";
          basedOn = data['based_on'] ?? "";
          details = data['details'] ?? [];
          routeSummary = Map<String, dynamic>.from(
            data['summary'] ?? {
              "total_clinics": 0,
              "high_priority_count": 0,
              "medium_priority_count": 0,
              "low_priority_count": 0,
            },
          );
          mostUrgentClinic = data['most_urgent_clinic'] ?? "";
          recommendationMessage = data['recommendation_message'] ?? "";
        });
      }
    } catch (e) {
      clearConsolidationState();
    }
  }

  Future<void> markOrderReceived() async {
    if (lastSubmittedOrder == null) return;
    try {
      await safeApiPost("$baseUrl/complete_order", {"clinic_id": widget.clinicId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Order marked as received ✅")),
        );
      }
      await refreshOrderPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: $e")),
        );
      }
    }
  }

  DateTime _parseOrderDate(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> fetchLastSubmittedOrder() async {
    try {
      final data = await safeApiGet('$baseUrl/orders?clinic_id=${widget.clinicId}');
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
                      "- ${itemNameOf(item)}: $qty",
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
                        title: Text(itemNameOf(item)),
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
                        return Text(
                          "• ${itemNameOf(item)} — ${itemQuantityOf(item, keys: ['qty', 'suggested_qty'])}",
                        );
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
                          title: Text(itemNameOf(item)),
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
