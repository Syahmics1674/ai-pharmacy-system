import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' as pw_core;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'order_history_page.dart';
import 'pkd_dashboard_page.dart';
import 'dashboard_page.dart';
import 'live_inventory_page.dart';
import 'settings_page.dart';
import 'services/sync_service.dart';
import 'services/live_inventory_service.dart';
import 'services/time_service.dart';
import 'config/api_config.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_theme.dart';
import 'widgets/common/app_top_bar.dart';
import 'widgets/common/app_sidebar.dart';
import 'widgets/common/page_header.dart';
import 'widgets/common/status_badge.dart';
import 'widgets/common/section_card.dart';
import 'widgets/common/loading_state.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String themeModeStr = prefs.getString("theme_mode") ?? "system";

  ThemeMode initialTheme = ThemeMode.system;
  if (themeModeStr == "light") initialTheme = ThemeMode.light;
  if (themeModeStr == "dark") initialTheme = ThemeMode.dark;

  runApp(PharmacyApp(initialTheme: initialTheme));
}

class PharmacyApp extends StatefulWidget {
  final ThemeMode initialTheme;

  const PharmacyApp({super.key, required this.initialTheme});

  static _PharmacyAppState of(BuildContext context) {
    return context.findAncestorStateOfType<_PharmacyAppState>()!;
  }

  @override
  State<PharmacyApp> createState() => _PharmacyAppState();
}

class _PharmacyAppState extends State<PharmacyApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialTheme;
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Pharmacy',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: const _AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  @override
  void initState() {
    super.initState();
    _determineInitialPage();
  }

  Future<void> _determineInitialPage() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? role = prefs.getString("role");
    if (!mounted) return;

    if (role == "pkd") {
      final String district = prefs.getString("district") ?? "";
      if (district.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PKDDashboardPage(district: district)),
        );
      }
    } else if (role == "clinic") {
      final String clinicId = prefs.getString("clinic_id") ?? "";
      if (clinicId.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainScreen(clinicId: clinicId)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoginPage();
  }
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
  bool _sidebarCollapsed = false;

  final orderKey = GlobalKey<_OrderPageState>();
  final dashboardKey = GlobalKey<DashboardPageState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      dashboardKey.currentState?.fetchDashboardData();
    }

    if (index == 4) {
      orderKey.currentState?.refreshOrderPage();
    }
  }

  Future<void> fetchClinicInfo() async {
    final response = await http.get(
      Uri.parse(
        "${ApiConfig.baseUrl}/clinic_info?clinic_id=${widget.clinicId}",
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

  Future<void> _performLogout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _apiCache.clear();
    _inflightRequests.clear();
    SyncService.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
      (route) => false,
    );
  }

  final List<String> _pageTitles = [
    "Dashboard",
    "Inventory",
    "Stock Operations",
    "AI Insights",
    "Order Management",
    "Settings",
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
    final isWide = MediaQuery.of(context).size.width >= 768;

    final List<Widget> pages = [
      DashboardPage(
        key: dashboardKey,
        clinicId: widget.clinicId,
        onNavigateInventory: () => setState(() => _selectedIndex = 1),
        onNavigateOperations: () => setState(() => _selectedIndex = 2),
        onNavigateOrders: () => setState(() => _selectedIndex = 4),
        onNavigateReports: () => setState(() => _selectedIndex = 3),
      ),
      LiveInventoryPage(clinicId: widget.clinicId),
      StockOperationsPage(clinicId: widget.clinicId),
      AIInsightsPage(clinicId: widget.clinicId),
      OrderPage(key: orderKey, clinicId: widget.clinicId),
      SettingsPage(
        currentTheme: Theme.of(context).brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        onThemeChanged: (mode) {
          PharmacyApp.of(context).setThemeMode(mode);
        },
      ),
    ];

    return Scaffold(
      appBar: _selectedIndex == 0 && !isWide
          ? null
          : AppTopBar(
              clinicName: clinicName.isEmpty ? widget.clinicId : clinicName,
              subtitle: _pageTitles[_selectedIndex],
              syncStatus: _isSyncing ? "Syncing..." : "Online",
              isSyncing: _isSyncing,
              onSettingsTap: () => _onItemTapped(5),
              onClinicTap: () => _onItemTapped(0),
            ),
      body: isWide
          ? Row(
              children: [
                AppSidebar(
                  selectedIndex: _selectedIndex,
                  onItemSelected: _onItemTapped,
                  collapsed: _sidebarCollapsed,
                  onToggleCollapse: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  clinicName: clinicName.isEmpty ? widget.clinicId : clinicName,
                  clinicDistrict: clinicDistrict,
                  onLogout: _performLogout,
                ),
                Expanded(child: pages[_selectedIndex]),
              ],
            )
          : pages[_selectedIndex],
      bottomNavigationBar: isWide
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex.clamp(0, 4),
              onTap: (i) => _onItemTapped(i),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
                BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: "Inventory"),
                BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_rounded), label: "Operations"),
                BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: "AI Insights"),
                BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_rounded), label: "Orders"),
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
  final String baseUrl = ApiConfig.baseUrl;
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
            body: json.encode({
              "user_id": userId,
              "password": password,
              "role": selectedRole.toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
      }

      final data = json.decode(response.body);
      final role = (data["role"] ?? "").toString().toLowerCase();

      if (data.containsKey("success") &&
          (data["success"] == true || data["success"] == "true")) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString("role", role);

        if (role == "pkd") {
          await prefs.setString("district", (data["district"] ?? "").toString());
          if (!mounted) return;
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

        await prefs.setString("clinic_id", (data["clinic_id"] ?? "").toString());
        if (!mounted) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF0D1B2A), const Color(0xFF1B2838)]
                        : [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.local_hospital_rounded,
                            size: 64,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          "AI-Assisted Pharmacy\nInventory System",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Efficient inventory management\npowered by artificial intelligence",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.8),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isWide)
                        Column(
                          children: [
                            Icon(
                              Icons.local_hospital_rounded,
                              size: 48,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "AI-Assisted Pharmacy\nInventory System",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Sign in to your account",
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      Card(
                        elevation: isDark ? 0 : 2,
                        color: isDark ? AppColors.surfaceDark : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Sign In",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 24),
                              DropdownButtonFormField<String>(
                                initialValue: selectedRole,
                                decoration: InputDecoration(
                                  labelText: "Role",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.badge_outlined),
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
                              const SizedBox(height: 16),
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
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.person),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: passController,
                                obscureText: !isPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => login(),
                                decoration: InputDecoration(
                                  labelText: "Password",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.lock),
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
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : login,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text("Login", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
  final String baseUrl = ApiConfig.baseUrl;
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
          SnackBar(content: Text("${e.toString().replaceAll("Exception: ", "")} ❌")),
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
          SnackBar(content: Text("${e.toString().replaceAll("Exception: ", "")} ❌")),
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
    fetchInventory();
    SyncService.fullSync(widget.clinicId);
  }

  // ############## DIALOG ##############

  void showStockDialog(String type) {
    TextEditingController itemController = TextEditingController();
    TextEditingController qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        value: medicineIdOf(item),
                        child: Text(itemNameOf(item)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: "Stock Operations",
              subtitle: "Manage inventory stock levels",
              icon: Icons.swap_horiz_rounded,
            ),
            SectionCard(
              title: "Quick Actions",
              icon: Icons.flash_on_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => showStockDialog("in"),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                      label: const Text("Stock In"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => showStockDialog("out"),
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                      label: const Text("Stock Out"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: showAddItemDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text("Add New Medicine"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        foregroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                        side: BorderSide(color: isDark ? AppColors.primaryLight : AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final response = await http.post(
                            Uri.parse("${ApiConfig.baseUrl}/start_mediscan"),
                            headers: {"Content-Type": "application/json"},
                            body: jsonEncode({"mode": "stock_out"}),
                          );
                          if (response.statusCode == 200) {
                            debugPrint("MedScan started for dispense");
                          } else {
                            debugPrint("Failed to start MedScan: ${response.body}");
                          }
                        } catch (e) {
                          debugPrint("Error starting MedScan: $e");
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text("MedScan Dispense"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        foregroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                        side: BorderSide(color: isDark ? AppColors.primaryLight : AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: LoadingState(message: "Processing..."),
              ),
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
  final String baseUrl = ApiConfig.baseUrl;
  final List<Color> chartGradient = [
    AppColors.primary,
    AppColors.success,
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
  int currentPage = 1;
  static const int itemsPerPage = 10;

  // Historical Inventory Trend data
  Map<String, List<double>> inventoryHistory = {};
  List<String> historyDates = [];
  String? selectedHistoryMedicine;

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
      fetchInventoryHistory(),
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
          currentPage = 1;
        });
      }
    } catch (e) {
      print("ERROR Smart Inventory: $e");
    }
  }

  Future<void> fetchInventoryHistory() async {
    try {
      final data = await safeApiGet("$baseUrl/ai/inventory_history?clinic_id=${widget.clinicId}");
      if (mounted && data['success'] == true) {
        final rawHistory = data['history'] as Map<String, dynamic>? ?? {};
        final dates = List<String>.from(data['dates'] ?? []);
        
        final parsedHistory = <String, List<double>>{};
        rawHistory.forEach((key, val) {
          if (val is List) {
            parsedHistory[key] = val.map((e) => (e as num).toDouble()).toList();
          }
        });

        setState(() {
          inventoryHistory = parsedHistory;
          historyDates = dates;
          if (parsedHistory.isNotEmpty && (selectedHistoryMedicine == null || !parsedHistory.containsKey(selectedHistoryMedicine))) {
            selectedHistoryMedicine = parsedHistory.keys.first;
          }
        });
      }
    } catch (e) {
      print("ERROR Fetching Inventory History: $e");
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isLoading) {
      return Container(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        child: const LoadingState(message: "Loading AI insights..."),
      );
    }

    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: "AI Insights Dashboard",
              subtitle: "Overall analytics, trends, and medicine insights",
              icon: Icons.insights_rounded,
            ),

            // AI Status Card
            SectionCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.success, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "AI Model Active",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const StatusBadge(
                              label: "Online",
                              style: BadgeStyle.success,
                              showDot: true,
                              fontSize: 10,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Confidence: High  |  Last Updated: ${TimeService.formatDateTime(TimeService.nowMYT())}  |  Model: Gradient Boosting v1",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ═══════════════════════════════════
            // PART 2: OVERALL USAGE CHART
            // ═══════════════════════════════════
            _buildOverallUsageSection(),

            const SizedBox(height: 20),

            // ═══════════════════════════════════
            // 30-DAY HISTORICAL INVENTORY
            // ═══════════════════════════════════
            _buildHistoricalTrendsSection(),

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
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Sorted by depletion risk — tap for details",
              style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 12),
            ),
            Builder(
              builder: (context) {
                final totalFilteredItems = _filteredInventory.length;
                final totalPages = (totalFilteredItems / itemsPerPage).ceil() == 0 ? 1 : (totalFilteredItems / itemsPerPage).ceil();
                final safePage = currentPage.clamp(1, totalPages);
                final startIndex = (safePage - 1) * itemsPerPage;
                final endIndex = startIndex + itemsPerPage > totalFilteredItems ? totalFilteredItems : startIndex + itemsPerPage;
                final paginatedItems = _filteredInventory.isEmpty ? [] : _filteredInventory.sublist(startIndex, endIndex);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...paginatedItems.map((item) => _buildMedicineTile(item)),
                    if (totalFilteredItems > itemsPerPage) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                            color: safePage > 1 ? (isDark ? Colors.cyanAccent : Colors.blueAccent) : Colors.grey,
                            onPressed: safePage > 1
                                ? () => setState(() => currentPage = safePage - 1)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              "Page $safePage of $totalPages",
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                            color: safePage < totalPages ? (isDark ? Colors.cyanAccent : Colors.blueAccent) : Colors.grey,
                            onPressed: safePage < totalPages
                                ? () => setState(() => currentPage = safePage + 1)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),

            if (_filteredInventory.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                child: Text(
                  "No medicines match your search.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8), fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- OVERALL USAGE SECTION ----
  Widget _buildOverallUsageSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = TimeService.nowMYT();

    List<String> dailyLabels = List.generate(7, (i) {
      final date = today.subtract(Duration(days: 6 - i));
      return TimeService.getDayOfWeekName(date.weekday);
    });

    List<String> weeklyLabels = const ["3w ago", "2w ago", "1w ago", "This Week"];

    List<String> monthlyLabels = List.generate(3, (i) {
      final date = DateTime(today.year, today.month - (2 - i), 1);
      return TimeService.getMonthName(date.month);
    });

    // Calculate period totals
    int total7d = dailyUsage.isNotEmpty ? dailyUsage.reduce((a, b) => a + b) : 0;
    int total4w = weeklyUsage.isNotEmpty ? weeklyUsage.reduce((a, b) => a + b) : 0;
    int total3m = monthlyUsage.isNotEmpty ? monthlyUsage.reduce((a, b) => a + b) : 0;

    return SectionCard(
      title: "Consolidated Medicine Usage",
      icon: Icons.bar_chart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Total units of all medicines dispensed across the entire clinic.",
            style: TextStyle(
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          Row(
            children: [
              Expanded(
                child: _buildMetricBadge(
                  "7-Day Total",
                  "$total7d units",
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildMetricBadge(
                  "4-Week Total",
                  "$total4w units",
                  AppColors.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildMetricBadge(
                  "3-Month Total",
                  "$total3m units",
                  AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildMiniChart("Daily (7 days)", dailyUsage, dailyLabels, AppColors.primary)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildMiniChart("Weekly (4 weeks)", weeklyUsage, weeklyLabels, AppColors.warning)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildMiniChart("Monthly (3 months)", monthlyUsage, monthlyLabels, AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String label, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ---- HISTORICAL TRENDS SECTION ----
  Widget _buildHistoricalTrendsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (inventoryHistory.isEmpty || historyDates.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedPoints = inventoryHistory[selectedHistoryMedicine] ?? [];
    
    double maxY = 10;
    if (selectedPoints.isNotEmpty) {
      final maxVal = selectedPoints.reduce((a, b) => a > b ? a : b);
      maxY = maxVal < 50 ? 50.0 : maxVal * 1.2;
    }

    List<FlSpot> spots = [];
    for (int i = 0; i < selectedPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), selectedPoints[i]));
    }

    const double safetyThreshold = 20.0;

    final accentColor = isDark ? AppColors.primaryLight : AppColors.primary;

    return SectionCard(
      title: "30-Day Inventory History",
      icon: Icons.history_toggle_off_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: accentColor.withOpacity(0.3)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedHistoryMedicine,
            dropdownColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: accentColor, size: 16),
            style: TextStyle(color: isDark ? AppColors.textOnDark : AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
            items: inventoryHistory.keys.map((String key) {
              return DropdownMenuItem<String>(
                value: key,
                child: SizedBox(
                  width: 130,
                  child: Text(
                    key,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? val) {
              if (val != null) {
                setState(() {
                  selectedHistoryMedicine = val;
                });
              }
            },
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.lg),
          if (spots.isEmpty)
            Container(
              height: 180,
              alignment: Alignment.center,
              child: Text(
                "No historical data for selected medicine.",
                style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) => FlLine(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0), strokeWidth: 1, dashArray: [5, 5]),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 5,
                        getTitlesWidget: (value, meta) {
                          int idx = value.toInt();
                          if (idx < 0 || idx >= historyDates.length) {
                            return const SizedBox.shrink();
                          }
                          final rawDate = historyDates[idx];
                          try {
                            final formatted = TimeService.formatCustom(rawDate, 'dd/MM');
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(formatted, style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 9)),
                            );
                          } catch (_) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(rawDate.length > 5 ? rawDate.substring(5) : rawDate, style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 9)),
                            );
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: maxY / 4 > 0 ? maxY / 4 : 10,
                        getTitlesWidget: (value, meta) {
                          return Text(value.toInt().toString(), style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 9));
                        },
                        reservedSize: 28,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (selectedPoints.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: safetyThreshold,
                        color: Colors.redAccent.withOpacity(0.4),
                        strokeWidth: 1.2,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: TextStyle(
                            color: Colors.redAccent.withOpacity(0.6),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          labelResolver: (line) => "Safety Limit (20)",
                        ),
                      ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      gradient: LinearGradient(colors: chartGradient),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          bool showDot = index == 0 || index == spots.length - 1 || index % 5 == 0;
                          return FlDotCirclePainter(
                            radius: showDot ? 3 : 0,
                            color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                            strokeWidth: showDot ? 2 : 0,
                            strokeColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: chartGradient.map((c) => c.withOpacity(0.12)).toList(),
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
    );
  }

  Widget _buildMiniChart(String label, List<int> values, List<String> xLabels, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (values.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Center(
          child: Text("No data", style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 11)),
        ),
      );
    }

    final maxVal = values.reduce((a, b) => a > b ? a : b).toDouble();
    final effectiveMax = maxVal < 1 ? 1.0 : maxVal * 1.25;

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: effectiveMax,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  tooltipBorder: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                  tooltipMargin: 4,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      "${rod.toY.toInt()} units",
                      TextStyle(color: isDark ? AppColors.textOnDark : AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 0 && idx < xLabels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(xLabels[idx], style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 8, fontWeight: FontWeight.bold)),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: effectiveMax / 2 > 0 ? effectiveMax / 2 : 10,
                    getTitlesWidget: (value, meta) {
                      return Text(value.toInt().toString(), style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 8));
                    },
                  ),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(color: isDark ? AppColors.borderDark : AppColors.borderLight, strokeWidth: 0.8),
              ),
              barGroups: List.generate(values.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i].toDouble(),
                      color: color,
                      width: 10,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(color: isDark ? AppColors.textOnDark : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
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
            "Low Stock",
            "$critical",
            "Items below threshold",
            Colors.redAccent,
            Icons.error_outline_rounded,
            () {
              _showStockTrendPopup(
                "Low Stock",
                Colors.redAccent,
                (item) {
                  final stock = item['current_stock'] ?? 0;
                  return stock < 20;
                },
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            "Moderate",
            "$low",
            "Items at moderate level",
            Colors.orangeAccent,
            Icons.warning_amber_rounded,
            () {
              _showStockTrendPopup(
                "Moderate Stock",
                Colors.orangeAccent,
                (item) {
                  final stock = item['current_stock'] ?? 0;
                  return stock >= 20 && stock < 50;
                },
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            "Adequate",
            "$safe",
            "Items well-stocked",
            Colors.greenAccent,
            Icons.check_circle_outline_rounded,
            () {
              _showStockTrendPopup(
                "Adequate Stock",
                Colors.greenAccent,
                (item) {
                  final stock = item['current_stock'] ?? 0;
                  return stock >= 50;
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, Color color, IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: color.withOpacity(0.12),
        highlightColor: color.withOpacity(0.06),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
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
                                      style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
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
                style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStockTrendPopup(String categoryName, Color categoryColor, bool Function(dynamic) filterFn) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredList = smartInventory.where(filterFn).toList();

    final List<Color> lineColors = [
      isDark ? Colors.cyanAccent : Colors.blueAccent,
      Colors.pinkAccent,
      Colors.amberAccent,
      Colors.lightGreenAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
      Colors.blueAccent,
      Colors.tealAccent,
    ];

    String? selectedPopupMed = filteredList.isNotEmpty ? itemNameOf(filteredList.first) : null;
    int legendPage = 0;
    const int legendItemsPerPage = 12;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: categoryColor.withOpacity(0.3), width: 1.5),
              ),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: categoryColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.trending_up_rounded, color: categoryColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$categoryName Medicines",
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${filteredList.length} items total",
                                style: TextStyle(
                                  color: isDark ? Colors.blueGrey : const Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 24),

                    if (filteredList.isNotEmpty) ...[
                      Builder(
                        builder: (context) {
                          final totalLegendPages = (filteredList.length / legendItemsPerPage).ceil();
                          final correctedLegendPage = legendPage.clamp(0, totalLegendPages - 1 >= 0 ? totalLegendPages - 1 : 0);
                          final startIndex = correctedLegendPage * legendItemsPerPage;
                          final endIndex = (startIndex + legendItemsPerPage).clamp(0, filteredList.length);
                          final pageItems = filteredList.sublist(startIndex, endIndex);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Consolidated 30-Day Inventory History Row with Dropdown selector
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.history_toggle_off_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 12),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Consolidated 30-Day History",
                                        style: TextStyle(color: categoryColor, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                      decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.3), width: 1),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: selectedPopupMed,
                                          isDense: true,
                                          dropdownColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 16),
                                          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 11, fontWeight: FontWeight.w600),
                                          borderRadius: BorderRadius.circular(12),
                                          onChanged: (String? newValue) {
                                            setDialogState(() {
                                              selectedPopupMed = newValue;
                                              if (newValue != null) {
                                                final index = filteredList.indexWhere((item) => itemNameOf(item) == newValue);
                                                if (index != -1) {
                                                  legendPage = index ~/ legendItemsPerPage;
                                                }
                                              }
                                            });
                                          },
                                          items: filteredList.map<DropdownMenuItem<String>>((dynamic item) {
                                            final name = itemNameOf(item);
                                            return DropdownMenuItem<String>(
                                              value: name,
                                              child: ConstrainedBox(
                                                constraints: const BoxConstraints(maxWidth: 150),
                                                child: Text(
                                                  name,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white : const Color(0xFF1E293B)),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                height: 300,
                                padding: const EdgeInsets.fromLTRB(4, 12, 12, 4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                ),
                                child: _buildPopupChartAll(filteredList, lineColors, selectedPopupMed),
                              ),
                              const SizedBox(height: 16),

                              // Interactive Legend Wrap
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: List.generate(pageItems.length, (pageIndex) {
                                  final actualIndex = startIndex + pageIndex;
                                  final item = pageItems[pageIndex];
                                  final name = itemNameOf(item);
                                  final color = lineColors[actualIndex % lineColors.length];
                                  final isSelected = selectedPopupMed == name;
                                  return GestureDetector(
                                    onTap: () {
                                      setDialogState(() {
                                        selectedPopupMed = name;
                                      });
                                    },
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isSelected ? color.withOpacity(0.4) : Colors.transparent,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: isSelected ? color : color.withOpacity(0.4),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              name,
                                              style: TextStyle(
                                                color: isSelected ? (isDark ? Colors.white : const Color(0xFF1E293B)) : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                                                fontSize: 11,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),

                              // Legend pagination buttons
                              if (totalLegendPages > 1) ...[
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(Icons.arrow_left_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 28),
                                      onPressed: correctedLegendPage > 0
                                          ? () {
                                              setDialogState(() {
                                                legendPage = correctedLegendPage - 1;
                                              });
                                            }
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Legend Page ${correctedLegendPage + 1} of $totalLegendPages",
                    style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(Icons.arrow_right_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 28),
                                      onPressed: correctedLegendPage < totalLegendPages - 1
                                          ? () {
                                              setDialogState(() {
                                                legendPage = correctedLegendPage + 1;
                                              });
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPopupChartAll(List<dynamic> filteredList, List<Color> assignedColors, String? selectedPopupMed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<LineChartBarData> fadedLines = [];
    LineChartBarData? highlightedLine;
    double overallMaxY = 10;

    for (int i = 0; i < filteredList.length; i++) {
      final item = filteredList[i];
      final name = itemNameOf(item);
      final points = inventoryHistory[name] ?? [];
      final color = assignedColors[i % assignedColors.length];
      final isSelected = selectedPopupMed == null || name == selectedPopupMed;

      if (points.isNotEmpty) {
        final maxVal = points.reduce((a, b) => a > b ? a : b);
        if (maxVal > overallMaxY) {
          overallMaxY = maxVal;
        }
      }

      List<FlSpot> spots = [];
      for (int day = 0; day < points.length; day++) {
        spots.add(FlSpot(day.toDouble(), points[day]));
      }

      if (spots.isNotEmpty) {
        final lineBar = LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.2,
          color: isSelected ? color : color.withOpacity(0.08),
          barWidth: isSelected ? 4 : 1.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: isSelected,
            getDotPainter: (spot, percent, barData, index) {
              bool showDot = index == 0 || index == spots.length - 1 || index % 5 == 0;
              return FlDotCirclePainter(
                radius: showDot ? 2.5 : 0,
                color: color,
                strokeWidth: showDot ? 1.5 : 0,
                strokeColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(show: false),
        );

        if (isSelected) {
          highlightedLine = lineBar;
        } else {
          fadedLines.add(lineBar);
        }
      }
    }

    if (fadedLines.isEmpty && highlightedLine == null) {
      return Center(
        child: Text(
          "Insufficient historical data to graph 30-day history.",
          style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF94A3B8), fontSize: 12),
        ),
      );
    }

    final List<LineChartBarData> linesData = [...fadedLines];
    if (highlightedLine != null) {
      linesData.add(highlightedLine);
    }

    final maxY = overallMaxY * 1.2 > 10 ? overallMaxY * 1.2 : 10.0;
    const double safetyThreshold = 20.0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0), strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 5,
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx < 0 || idx >= historyDates.length) {
                  return const SizedBox.shrink();
                }
                final rawDate = historyDates[idx];
                try {
                  final formatted = TimeService.formatCustom(rawDate, 'dd/MM');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(formatted, style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 9)),
                  );
                } catch (_) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(rawDate.length > 5 ? rawDate.substring(5) : rawDate, style: TextStyle(color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary, fontSize: 9)),
                  );
                }
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 4 > 0 ? maxY / 4 : 10,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(), style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 9));
              },
              reservedSize: 28,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (historyDates.length - 1).toDouble() > 0 ? (historyDates.length - 1).toDouble() : 29,
        minY: 0,
        maxY: maxY,
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: safetyThreshold,
              color: Colors.redAccent.withOpacity(0.4),
              strokeWidth: 1.2,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: TextStyle(
                  color: Colors.redAccent.withOpacity(0.6),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                labelResolver: (line) => "Safety Limit (20)",
              ),
            ),
          ],
        ),
        lineBarsData: linesData,
      ),
    );
  }

  // ---- TOP PRODUCTS ----
  Widget _buildTopProductsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                "Top Dispensed Products",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
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
                style: TextStyle(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
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
                  color: isTop ? (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isTop ? Border.all(color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.3)) : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTop ? (isDark ? Colors.cyanAccent : Colors.blueAccent) : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "#${i + 1}",
                        style: TextStyle(
                          color: isTop ? Colors.black : (isDark ? Colors.white70 : const Color(0xFF64748B)),
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
                          color: isTop ? (isDark ? Colors.cyanAccent : Colors.blueAccent) : (isDark ? Colors.white : const Color(0xFF1E293B)),
                          fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      "$totalUsed used",
                      style: TextStyle(
                        color: isDark ? Colors.blueGrey : const Color(0xFF64748B),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.08),
            isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AI Recommendation",
                  style: TextStyle(
                    color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  insightMessage,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      onChanged: (v) => setState(() {
        searchQuery = v.trim();
        currentPage = 1;
      }),
      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B)),
      decoration: InputDecoration(
        hintText: "Search medicine...",
        hintStyle: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B)),
        prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.blueGrey : const Color(0xFF64748B)),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? Colors.cyanAccent : Colors.blueAccent, width: 1.5),
        ),
      ),
    );
  }

  // ---- MEDICINE LIST TILE ----
  Widget _buildMedicineTile(dynamic data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          color: (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)).withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
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
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
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
            Icon(Icons.chevron_right, color: isDark ? Colors.white24 : const Color(0xFF94A3B8), size: 20),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(itemName, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B))),
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1E293B)),
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
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "AI Forecast & Depletion Analysis",
                        style: TextStyle(color: isDark ? Colors.cyanAccent : Colors.blueAccent, fontSize: 13),
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
                  Expanded(child: _buildMetricCard("Current Stock", "$currentStock Units", "In Inventory", isDark ? Colors.white70 : const Color(0xFF64748B))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard("Recommended Order", "+$recommendQty", "30-day safety stock", isDark ? Colors.cyanAccent : Colors.blueAccent)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 7-Day Forecast Chart
            Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.show_chart_rounded, color: isDark ? Colors.cyanAccent : Colors.blueAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "7-Day Demand Trajectory",
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: (isDark ? Colors.cyanAccent : Colors.blueAccent).withOpacity(0.3)),
                        ),
                        child: Text(
                          "AI Forecast",
                          style: TextStyle(color: isDark ? Colors.cyanAccent : Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildChart(forecastData)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Cumulative Stock Burn-Down Chart
            Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.trending_down_rounded, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "7-Day Stock Depletion (Burn-Down)",
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: const Text(
                          "Depletion Curve",
                          style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildBurnDownChart(currentStock, forecastData)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glowColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: isDark ? Colors.blueGrey[400] : const Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: glowColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildChart(List<int> forecastData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (forecastData.isEmpty || forecastData.every((e) => e == 0)) {
      return Center(
        child: Text("Insufficient historical data to graph.", style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF94A3B8))),
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
          getDrawingHorizontalLine: (v) => FlLine(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0), strokeWidth: 1, dashArray: [5, 5]),
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
                  child: Text("Day ${value.toInt() + 1}", style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 12)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(), style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 12));
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
                color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                strokeWidth: 2,
                strokeColor: isDark ? const Color(0xFF1E293B) : Colors.white,
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

  Widget _buildBurnDownChart(int currentStock, List<int> forecastData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (forecastData.isEmpty) {
      return Center(
        child: Text("No forecast data to calculate depletion.", style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF94A3B8))),
      );
    }

    // Calculate burn down points starting from currentStock
    List<double> burnDownValues = [currentStock.toDouble()];
    double runningStock = currentStock.toDouble();
    for (int i = 0; i < forecastData.length; i++) {
      runningStock = runningStock - forecastData[i];
      if (runningStock < 0) runningStock = 0;
      burnDownValues.add(runningStock);
    }

    double maxY = currentStock.toDouble();
    maxY = maxY < 50 ? 50 : maxY * 1.2;

    List<FlSpot> spots = [];
    for (int i = 0; i < burnDownValues.length; i++) {
      spots.add(FlSpot(i.toDouble(), burnDownValues[i]));
    }

    // Draw safety threshold line at Y = 20
    const double safetyThreshold = 20.0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0), strokeWidth: 1, dashArray: [5, 5]),
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
                if (value.toInt() == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text("Today", style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold)),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("Day ${value.toInt()}", style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(), style: TextStyle(color: isDark ? Colors.blueGrey : const Color(0xFF64748B), fontSize: 10));
              },
              reservedSize: 30,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: forecastData.length.toDouble(),
        minY: 0,
        maxY: maxY,
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: safetyThreshold,
              color: Colors.amberAccent.withOpacity(0.6),
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: TextStyle(
                  color: Colors.amberAccent.withOpacity(0.8),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                labelResolver: (line) => "Safety Limit (20)",
              ),
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false, // Depletion is linear/stepwise
            color: Colors.redAccent,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.redAccent,
                strokeWidth: 2,
                strokeColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.redAccent.withOpacity(0.2),
                  Colors.redAccent.withOpacity(0.0),
                ],
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
  final String baseUrl = ApiConfig.baseUrl;

  List suggestions = [];
  String consolidatedDate = "";
  bool isLoading = false;
  String basedOn = "";
  List details = [];
  List generatedOrders = [];
  Map<String, dynamic>? lastSubmittedOrder;
  Map<String, dynamic>? pendingOrder;
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

  List _cartItems = [];
  List _inventoryItems = [];
  Map<String, dynamic>? _selectedMedicine;
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  int _lowStockCount = 0;
  bool _hasPendingOrderFromBackend = false;
  bool _suggestionsExpanded = true;
  bool _showAllItems = false;
  int _draftCount = 0;
  int _submittedCount = 0;
  final Map<String, int> _editableQtys = {};

  // 🔥 GENERATE ORDER
  Future<void> generateOrder() async {
    if (isLoading) return;
    try {
      final generatedItems = suggestions.map<Map<String, dynamic>>((item) {
        final code = medicineIdOf(item);
        final qty = _editableQtys[code] ?? (item['suggested_qty'] as int);
        return {
          "item_code": code,
          "item_name": itemNameOf(item),
          "qty": qty,
          "suggested_qty": qty,
        };
      }).toList();
      await safeApiPost("$baseUrl/generate_order", {
        "clinic_id": widget.clinicId,
        "items": generatedItems,
        "status": "DRAFT",
      });
      if (mounted) {
        setState(() {
          generatedOrders = generatedItems;
          generatedOrderDate = TimeService.formatDate(TimeService.nowMYT());
        });
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
          (sum, item) => sum + (_editableQtys[medicineIdOf(item)] ?? (item['suggested_qty'] as int)),
        );
        return AlertDialog(
          title: Text("Confirm Order"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("You are about to order:\n"),

              ...suggestions.map((item) {
                final code = medicineIdOf(item);
                final suggestedQty = item['suggested_qty'] as int;
                final qty = _editableQtys[code] ?? suggestedQty;
                final modified = qty != suggestedQty;
                return Text(
                  "• ${itemNameOf(item)} — $qty"
                  "${modified ? '  [Modified: AI was $suggestedQty]' : ''}",
                );
              }),
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
    _fetchInventoryItems();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _searchController.dispose();
    super.dispose();
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
      final data = await safeApiGet(
        "$baseUrl/order_suggestions?clinic_id=${widget.clinicId}",
        timeout: const Duration(seconds: 45),
      );
      if (mounted) {
        final suggested = data['order_suggestions'] ?? [];
        debugPrint("DEBUG[order]: fetchSuggestions response keys=${data.keys}");
        debugPrint("DEBUG[order]: suggestions count=${suggested.length}");
        if (suggested.isEmpty) {
          debugPrint("DEBUG[order]: EMPTY suggestions - checking error/block");
          debugPrint("DEBUG[order]: data has error? ${data.containsKey('error')}");
        } else {
          debugPrint("DEBUG[order]: first item keys=${suggested.first is Map ? (suggested.first as Map).keys : 'not-map'}");
        }
        setState(() {
          suggestions = suggested;
          _hasPendingOrderFromBackend = data['has_pending_order'] == true;
          _showAllItems = false;
          _editableQtys.clear();
          for (final item in suggestions) {
            final code = medicineIdOf(item);
            _editableQtys[code] = item['suggested_qty'] as int;
          }
        });
      }
    } catch (e) {
      debugPrint("DEBUG[order]: fetchSuggestions failed: $e");
    }
  }

  Future<void> fetchConsolidation() async {
    try {
      final data = await safeApiGet(
        "$baseUrl/consolidate?clinic_id=${widget.clinicId}",
        timeout: const Duration(seconds: 45),
      );
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
      debugPrint("DEBUG: fetchConsolidation failed: $e");
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

  Future<void> cancelDraftOrder() async {
    if (pendingOrder == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Draft Order?"),
        content: const Text(
          "This will permanently remove the current draft order.\n"
          "You can generate a new order again later.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Yes, Cancel Draft"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await safeApiPost("$baseUrl/update_order_status", {
        "order_id": pendingOrder!['id'],
        "status": "CANCELLED",
      });
      if (mounted) {
        setState(() {
          pendingOrder = null;
          generatedOrders = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Draft order cancelled")),
        );
      }
      await refreshOrderPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to cancel draft: $e")),
        );
      }
    }
  }

  // DEMO MODE ONLY
  // Real deployment should disable submitted order cancellation.
  Future<void> cancelSubmittedOrder() async {
    if (lastSubmittedOrder == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Submitted Order?"),
        content: const Text(
          "This order has already been submitted.\n\n"
          "Demo/Test mode only.\n\n"
          "Are you sure you want to cancel it?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Yes, Cancel"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await safeApiPost("$baseUrl/update_order_status", {
        "order_id": lastSubmittedOrder!['id'],
        "status": "CANCELLED",
      });
      if (mounted) {
        setState(() {
          lastSubmittedOrder = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Submitted order cancelled")),
        );
      }
      await refreshOrderPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to cancel: $e")),
        );
      }
    }
  }

  Future<void> submitOrder() async {
    if (pendingOrder == null) return;
    try {
      await safeApiPost("$baseUrl/update_order_status", {
        "order_id": pendingOrder!['id'],
        "status": "SUBMITTED",
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Order submitted ✅")),
        );
      }
      await refreshOrderPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to submit: $e")),
        );
      }
    }
  }

  DateTime _parseOrderDate(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is String && value.isNotEmpty) {
      return TimeService.parseToMYT(value);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> fetchLastSubmittedOrder() async {
    try {
      final data = await safeApiGet('$baseUrl/orders?clinic_id=${widget.clinicId}');
      final List<Map<String, dynamic>> allOrders =
          (data['orders'] as List<dynamic>)
              .map((order) => Map<String, dynamic>.from(order))
              .toList();
      allOrders.sort(
        (a, b) => _parseOrderDate(
          b['created_at'],
        ).compareTo(_parseOrderDate(a['created_at'])),
      );
      final draftOrders = allOrders
          .where((o) => o['status'] == "DRAFT")
          .toList();
      final submittedOrders = allOrders
          .where((o) => o['status'] == "SUBMITTED")
          .toList();
      if (!mounted) return;
      setState(() {
        _draftCount = draftOrders.length;
        _submittedCount = submittedOrders.length;
        pendingOrder = draftOrders.isNotEmpty
            ? draftOrders.first
            : null;
        lastSubmittedOrder = submittedOrders.isNotEmpty
            ? submittedOrders.first
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        pendingOrder = null;
        lastSubmittedOrder = null;
        _draftCount = 0;
        _submittedCount = 0;
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

  int _sumOrderItems(List items) {
    int total = 0;
    for (final item in items) {
      total += itemQuantityOf(item, keys: ['qty', 'suggested_qty']);
    }
    return total;
  }

  Widget _buildOrderStatusCard({
    required IconData icon,
    required String statusLabel,
    required Color statusColor,
    required List<dynamic> items,
    required String createdDate,
    required int totalQty,
  }) {
    final totalItems = items.length;
    final formattedDate = createdDate.isNotEmpty
        ? TimeService.formatDate(createdDate)
        : createdDate;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "$totalItems Item${totalItems == 1 ? '' : 's'}",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text("Created: $formattedDate",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 16),
                Icon(Icons.inventory_2, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text("Total: $totalQty",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                "View Order List ($totalItems item${totalItems == 1 ? '' : 's'})",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              collapsedIconColor: Theme.of(context).colorScheme.primary,
              iconColor: Theme.of(context).colorScheme.primary,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 8),
                // Header row
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text("Medicine",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                      ),
                    ),
                    Text("Qty",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const Divider(height: 8),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Icon(Icons.medication, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          itemNameOf(item),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        "${itemQuantityOf(item, keys: ['qty', 'suggested_qty'])}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                )),
                const SizedBox(height: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> get _activeOrderItems {
    if (generatedOrders.isNotEmpty) return generatedOrders;
    if (pendingOrder != null) {
      final items = pendingOrder!['items'];
      if (items is List) return items;
    }
    if (lastSubmittedOrder != null) {
      final items = lastSubmittedOrder!['items'];
      if (items is List) return items;
    }
    return [];
  }

  Future<Uint8List> buildOrderPdf() async {
    final pdf = pw.Document();
    final orderDate = generatedOrderDate.isEmpty
        ? TimeService.formatDate(TimeService.nowMYT())
        : generatedOrderDate;
    final clinicLabel = clinicDisplayName.isEmpty
        ? widget.clinicId
        : clinicDisplayName;
    final activeItems = _activeOrderItems;
    final totalItems = activeItems.length;
    final lowStockCount = _lowStockCount;
    final priority = basedOn.isEmpty ? "N/A" : basedOn;
    final timestamp = TimeService.formatDate(TimeService.nowMYT());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pw_core.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Column(
            children: [
              pw.Text(
                "AI-Assisted Pharmacy Inventory System",
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                "Order Document",
                style: pw.TextStyle(
                  fontSize: 13,
                  color: const pw_core.PdfColor.fromInt(0xFF666666),
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            "Generated by AI-Assisted Pharmacy Inventory System",
            style: pw.TextStyle(
              fontSize: 9,
              color: const pw_core.PdfColor.fromInt(0xFF999999),
            ),
          ),
        ),
        build: (context) => [
          // Clinic Info
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const pw_core.PdfColor.fromInt(0xFFCCCCCC)),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Clinic Name: $clinicLabel",
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.SizedBox(height: 4),
                    pw.Text("Clinic ID: ${widget.clinicId}",
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.SizedBox(height: 4),
                    pw.Text("Order Date: $orderDate",
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Priority Level: $priority",
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: priority == "HIGH"
                                ? const pw_core.PdfColor.fromInt(0xFFCC0000)
                                : priority == "MEDIUM"
                                    ? const pw_core.PdfColor.fromInt(0xFFCC6600)
                                    : const pw_core.PdfColor.fromInt(0xFF333333))),
                    pw.SizedBox(height: 8),
                    pw.Text("Prepared By: __________",
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.SizedBox(height: 4),
                    pw.Text("Approved By: __________",
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Order Summary
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const pw_core.PdfColor.fromInt(0xFFF5F5F5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(children: [
                  pw.Text("$totalItems",
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Total Items",
                      style: const pw.TextStyle(fontSize: 10)),
                ]),
                pw.Column(children: [
                  pw.Text("$lowStockCount",
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Low Stock Count",
                      style: const pw.TextStyle(fontSize: 10)),
                ]),
                pw.Column(children: [
                  pw.Text(priority,
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Priority",
                      style: const pw.TextStyle(fontSize: 10)),
                ]),
                pw.Column(children: [
                  pw.Text(timestamp,
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Generated",
                      style: const pw.TextStyle(fontSize: 10)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Medicine Table Header
          pw.Text(
            "Medicine List",
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),

          // Table
          pw.Table(
            border: pw.TableBorder.all(
              color: const pw_core.PdfColor.fromInt(0xFFCCCCCC),
              width: 0.5,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(6),
              2: pw.FlexColumnWidth(2),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: pw_core.PdfColor.fromInt(0xFF333333),
                ),
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("No",
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const pw_core.PdfColor.fromInt(0xFFFFFFFF))),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("Medicine",
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const pw_core.PdfColor.fromInt(0xFFFFFFFF))),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text("Quantity",
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const pw_core.PdfColor.fromInt(0xFFFFFFFF)),
                        textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
              // Data rows
              ...activeItems.asMap().entries.map(
                    (entry) => pw.TableRow(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text("${entry.key + 1}",
                              style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(itemNameOf(entry.value),
                              style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                              "${entry.value['qty'] ?? entry.value['suggested_qty'] ?? 0}",
                              style: const pw.TextStyle(fontSize: 10),
                              textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          pw.SizedBox(height: 20),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> exportOrderAsPdf() async {
    final activeItems = _activeOrderItems;
    if (activeItems.isEmpty) return;

    final dateStr = TimeService.formatDate(TimeService.nowMYT());

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text("Order PDF Preview")),
          body: PdfPreview(
            build: (format) => buildOrderPdf(),
            pdfFileName:
                "order_${widget.clinicId}_$dateStr.pdf",
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  Future<void> exportOrderAsCsv() async {
    final activeItems = _activeOrderItems;
    if (activeItems.isEmpty) return;

    final dateStr = TimeService.formatDate(TimeService.nowMYT());
    final buffer = StringBuffer();
    buffer.writeln("item_code,item_name,qty");
    for (final item in activeItems) {
      final code = medicineIdOf(item);
      final name = itemNameOf(item).replaceAll(",", " ");
      final qty = item['qty'] ?? item['suggested_qty'] ?? 0;
      buffer.writeln("$code,$name,$qty");
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File("${directory.path}/order_${widget.clinicId}_$dateStr.csv");
    await file.writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("CSV saved: ${file.path}")),
      );
    }
  }

  // ================= QUICK ORDER =================

  Future<void> _fetchInventoryItems() async {
    final items = await LiveInventoryService.fetchLiveInventory(clinicId: widget.clinicId);
    if (!mounted) return;
    int lowStock = 0;
    for (final item in items) {
      final qty = (item['quantity'] ?? 0) as num;
      if (qty < 20) lowStock++;
    }
    debugPrint("DEBUG[order]: _fetchInventoryItems total=${items.length} lowStock=$lowStock");
    setState(() {
      _inventoryItems = items;
      _lowStockCount = lowStock;
    });
  }

  Future<void> _showMedicinePicker() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = query.isEmpty
                ? _inventoryItems
                : _inventoryItems.where((item) {
                    final name = liveInventoryDisplayName(item).toLowerCase();
                    final code = (item['item_code'] ?? '').toString().toLowerCase();
                    return name.contains(query.toLowerCase()) ||
                        code.contains(query.toLowerCase());
                  }).toList();
            return AlertDialog(
              title: const Text('Select Medicine'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search medicine...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.medication),
                            title: Text(
                              liveInventoryDisplayName(item),
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              'Stock: ${item['quantity'] ?? 0}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            onTap: () => Navigator.pop(ctx, item as Map<String, dynamic>),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _selectedMedicine = selected);
    }
  }

  void _addToCart() {
    if (_selectedMedicine == null) return;
    final qtyText = _qtyController.text.trim();
    final qty = int.tryParse(qtyText);
    if (qty == null || qty <= 0) return;
    final itemCode = _selectedMedicine!['item_code'] ?? '';
    final itemName = _selectedMedicine!['medicine_name'] ?? liveInventoryDisplayName(_selectedMedicine!);
    if (itemCode.toString().isEmpty) return;
    setState(() {
      _cartItems.add({
        'item_code': itemCode,
        'item_name': itemName,
        'qty': qty,
      });
      _selectedMedicine = null;
      _qtyController.clear();
    });
  }

  void _removeFromCart(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  Future<void> _generateQuickOrder() async {
    if (_cartItems.isEmpty) return;
    setState(() => isLoading = true);
    try {
      await safeApiPost("$baseUrl/generate_order", {
        "clinic_id": widget.clinicId,
        "items": _cartItems,
        "status": "SUBMITTED",
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Quick order submitted ✅")),
        );
      }
      setState(() {
        _cartItems = [];
        _selectedMedicine = null;
        _qtyController.clear();
      });
      await refreshOrderPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ================= SMART AI RECOMMENDATION BANNER =================

  Widget _buildRecommendationBanner() {
    String title;
    String subtitle;
    String actionLabel;
    String severityLabel;
    IconData icon;
    Color bgColor;
    Color iconColor;
    Color accentColor;

    final highCount = routeSummary['high_priority_count'] ?? 0;
    debugPrint("DEBUG[order]: banner pendingOrder=${pendingOrder != null} lowStock=$_lowStockCount lastSubmitted=${lastSubmittedOrder != null} highCount=$highCount suggestions=${suggestions.length}");

    if (pendingOrder != null) {
      severityLabel = "DRAFT";
      title = "Draft order awaiting submission";
      subtitle = "Review and submit to PKD.";
      actionLabel = "Recommended: Submit within 24 hours.";
      icon = Icons.edit_note_rounded;
      bgColor = Colors.orange.shade50;
      iconColor = Colors.orange.shade700;
      accentColor = Colors.orange;
    } else if (_lowStockCount > 0) {
      severityLabel = "HIGH";
      title = "Immediate action recommended";
      subtitle = "Your clinic has critical shortages.";
      if (highCount > 0) {
        subtitle += "\nOther clinics on this route are also preparing orders.";
      }
      actionLabel = "Recommended: Generate and submit order within 24 hours.";
      icon = Icons.warning_amber_rounded;
      bgColor = Colors.red.shade50;
      iconColor = Colors.red.shade700;
      accentColor = Colors.red;
    } else if (lastSubmittedOrder != null) {
      severityLabel = "SUBMITTED";
      title = "Order submitted to PKD";
      subtitle = "Awaiting delivery and stock receipt confirmation.";
      actionLabel = "Mark as received when stock arrives.";
      icon = Icons.schedule_rounded;
      bgColor = Colors.blue.shade50;
      iconColor = Colors.blue.shade700;
      accentColor = Colors.blue;
    } else if (highCount > 0) {
      severityLabel = "INFO";
      title = "Inventory healthy";
      subtitle = "Your inventory levels are adequate.\n"
          "$highCount clinic${highCount > 1 ? 's' : ''} on this route currently "
          "ha${highCount > 1 ? 've' : 's'} shortages,\n"
          "but no order is required for your clinic at this time.";
      actionLabel = "Routine monitoring recommended.";
      icon = Icons.info_outline_rounded;
      bgColor = Colors.blue.shade50;
      iconColor = Colors.blue.shade700;
      accentColor = Colors.blue;
    } else {
      severityLabel = "HEALTHY";
      title = "Inventory status healthy";
      subtitle = "No shortages detected.\nNo replenishment action required.";
      actionLabel = "Routine monitoring recommended.";
      icon = Icons.check_circle_rounded;
      bgColor = Colors.green.shade50;
      iconColor = Colors.green.shade700;
      accentColor = Colors.green;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        severityLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= SUGGESTION ITEMS =================

  List<Widget> _buildSuggestionItems() {
    final displayItems = _showAllItems ? suggestions : suggestions.take(10).toList();
    final items = <Widget>[];

    for (final item in displayItems) {
      final code = medicineIdOf(item);
      final name = itemNameOf(item);
      final priority = item['priority'] as String? ?? '';
      final suggestedQty = item['suggested_qty'] as int? ?? 0;
      final currentQty = _editableQtys[code] ?? suggestedQty;

      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              // Medicine info
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: getPriorityColor(priority).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        priority,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: getPriorityColor(priority),
                        ),
                      ),
                    ),
                    if (currentQty != suggestedQty) ...[
                      const SizedBox(height: 2),
                      Text(
                        "AI: $suggestedQty → Final: $currentQty",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Quantity controls: [-] Qty [+]
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        if (currentQty > 1) {
                          setState(() {
                            _editableQtys[code] = currentQty - 1;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: const Icon(Icons.remove, size: 16),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: TextEditingController(text: "$currentQty")
                          ..selection = TextSelection.collapsed(offset: "$currentQty".length),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed >= 1) {
                            setState(() {
                              _editableQtys[code] = parsed;
                            });
                          }
                        },
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _editableQtys[code] = currentQty + 1;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: const Icon(Icons.add, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_showAllItems && suggestions.length > 10) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _showAllItems = true;
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text("View All Items (${suggestions.length})"),
            ),
          ),
        ),
      );
    } else if (_showAllItems && suggestions.length > 10) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showAllItems = false;
                });
              },
              child: Text("Show fewer items"),
            ),
          ),
        ),
      );
    }

    return items;
  }

  // ================= ORDER HISTORY CARD =================

  Widget _buildOrderHistoryCard() {
    final lastOrder = lastSubmittedOrder;
    final hasHistory = lastOrder != null;

    String lastDate = '';
    String lastStatus = '';
    int itemCount = 0;
    int totalQty = 0;

    if (hasHistory) {
      lastDate = lastOrder!['created_at']?.toString() ?? '';
      if (lastDate.isNotEmpty) {
        lastDate = TimeService.formatDate(lastDate);
      }
      lastStatus = lastOrder!['status']?.toString() ?? '';
      final items = lastOrder!['items'] as List<dynamic>? ?? [];
      itemCount = items.length;
      totalQty = _sumOrderItems(items);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "Order History",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasHistory) ...[
                  // LAST ORDER DATE
                  _buildHistoryRow(Icons.calendar_today, "Last Order", lastDate),
                  const SizedBox(height: 8),
                  // STATUS
                  _buildHistoryRow(Icons.info_outline, "Status", lastStatus),
                  const SizedBox(height: 8),
                  // ITEMS
                  _buildHistoryRow(Icons.medication, "Items", "$itemCount"),
                  const SizedBox(height: 8),
                  // TOTAL QTY
                  _buildHistoryRow(Icons.inventory_2, "Total Quantity", "$totalQty"),
                ] else ...[
                  // FALLBACK
                  Row(
                    children: [
                      Icon(Icons.history, size: 20, color: Colors.grey.shade500),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "No previous orders found.",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      "Create your first order to start building history.",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderHistoryPage(clinicId: widget.clinicId),
                        ),
                      ).then((_) {
                        fetchLastSubmittedOrder();
                      });
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text("View Full Order History"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(
          "$label:  ",
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ================= SUMMARY CHIP =================

  Widget _buildSummaryChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= KPI DASHBOARD =================

  Widget _buildDashboardGrid() {
    final draftCount = _draftCount;
    final submittedCount = _submittedCount;

    final nextOrderDate = consolidatedDate.isEmpty ? "-" : consolidatedDate;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 500;
        final kpis = [
          _KpiCard(
            icon: Icons.edit_note_rounded,
            label: "Draft Orders",
            value: "$draftCount",
            color: Colors.orange,
          ),
          _KpiCard(
            icon: Icons.send_rounded,
            label: "Submitted Orders",
            value: "$submittedCount",
            color: Colors.blue,
          ),
          _KpiCard(
            icon: Icons.inventory_2,
            label: "Low Stock Items",
            value: "$_lowStockCount",
            color: _lowStockCount > 0 ? Colors.red : Colors.green,
          ),
          _KpiCard(
            icon: Icons.calendar_today,
            label: "Next Order Date",
            value: nextOrderDate,
            color: Colors.indigo,
          ),
        ];

        if (isWide) {
          return SizedBox(
            height: 90,
            child: Row(
              children: kpis
                  .map((kpi) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: kpi,
                        ),
                      ))
                  .toList(),
            ),
          );
        }

        return Wrap(
          children: kpis
              .map((kpi) => SizedBox(
                    width: (constraints.maxWidth - 12) / 2,
                    height: 82,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: kpi,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refreshOrderPage,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // ================= SECTION 1: ORDER DASHBOARD =================
              PageHeader(
                title: "Order Dashboard",
                subtitle: "Manage stock orders, view recommendations, and track submissions",
                icon: Icons.shopping_cart_rounded,
              ),

              _buildDashboardGrid(),

              const SizedBox(height: 16),

              // ================= SMART NOTIFICATION BANNER =================
              _buildRecommendationBanner(),

              const SizedBox(height: 20),

              // ================= SECTION 2: SUGGESTED ORDERS =================
              if (suggestions.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Suggested Orders",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // GENERATE ORDER LIST BUTTON — PROMINENT CTA
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (pendingOrder != null) ? null : confirmGenerateOrder,
                            icon: const Icon(Icons.auto_awesome, size: 22),
                            label: const Text(
                              "Generate Order List",
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),

                        if (_hasPendingOrderFromBackend)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "A pending draft or submitted order exists. "
                                    "Recommendations below are for reference only.",
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 16),

                        // SUMMARY ROW
                        Row(
                          children: [
                            _buildSummaryChip(
                              Icons.medication_rounded,
                              "Total items",
                              "${suggestions.length}",
                              Colors.indigo,
                            ),
                            const SizedBox(width: 10),
                            _buildSummaryChip(
                              Icons.priority_high_rounded,
                              "Priority",
                              basedOn.isEmpty ? "-" : basedOn,
                              basedOn == "HIGH"
                                  ? Colors.red
                                  : basedOn == "MEDIUM"
                                      ? Colors.orange
                                      : Colors.green,
                            ),
                            const SizedBox(width: 10),
                            _buildSummaryChip(
                              Icons.inventory_rounded,
                              "Low stock",
                              "$_lowStockCount",
                              _lowStockCount > 0 ? Colors.red : Colors.green,
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // COLLAPSIBLE MEDICINE LIST
                        InkWell(
                          onTap: () {
                            setState(() {
                              _suggestionsExpanded = !_suggestionsExpanded;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _suggestionsExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _suggestionsExpanded
                                      ? "Hide medicine list"
                                      : "Show medicine list (${suggestions.length} items)",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_suggestionsExpanded) ...[
                          const Divider(height: 16),
                          ..._buildSuggestionItems(),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ================= ORDER HISTORY (always visible) =================
              _buildOrderHistoryCard(),

              const SizedBox(height: 24),

              // ================= SECTION 3: QUICK ORDER =================
              Text(
                "Quick Order",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Medicine selector
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _showMedicinePicker,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.medication, size: 20, color: Colors.grey),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedMedicine != null
                                            ? liveInventoryDisplayName(_selectedMedicine!)
                                            : "Select medicine...",
                                        style: TextStyle(
                                          color: _selectedMedicine != null ? Colors.black87 : Colors.grey,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _qtyController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: "Qty",
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _addToCart,
                            icon: const Icon(Icons.add),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Cart items
                      if (_cartItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            "No items in cart. Select a medicine and add quantity.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      else ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        ...List.generate(_cartItems.length, (index) {
                          final item = _cartItems[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['item_name'] ?? 'Unknown',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Text(
                                  "Qty: ${item['qty']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                  onPressed: () => _removeFromCart(index),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _cartItems.isEmpty ? null : _generateQuickOrder,
                            icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                            label: Text(
                              "Generate Quick Order (${_cartItems.length} items)",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ================= SECTION 4: ROUTE INSIGHT =================
              if (routeSummary['total_clinics'] != 0 || details.isNotEmpty) ...[
                Text(
                  "Route Insight",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const Divider(height: 24),
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

                if (details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Clinic Breakdown",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...details.map(
                            (d) => ListTile(
                              dense: true,
                              title: Text(d['clinic'] ?? ''),
                              subtitle: Text("Date: ${d['date'] ?? '-'}"),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: getPriorityColor(d['priority']).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  d['priority'] ?? '',
                                  style: TextStyle(
                                    color: getPriorityColor(d['priority']),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],

              // ================= SECTION 5: ORDER STATUS =================
              if (pendingOrder != null || lastSubmittedOrder != null || generatedOrders.isNotEmpty) ...[
                Text(
                  "Order Status",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // ---- DRAFT / PENDING ORDER CARD ----
                if (pendingOrder != null) _buildOrderStatusCard(
                  icon: Icons.schedule,
                  statusLabel: "DRAFT",
                  statusColor: Colors.orange,
                  items: (pendingOrder!['items'] as List<dynamic>?) ?? [],
                  createdDate: pendingOrder!['created_at']?.toString() ?? '',
                  totalQty: _sumOrderItems(pendingOrder!['items'] as List? ?? []),
                ),

                // ---- GENERATED ORDER CARD (local draft from generateOrder) ----
                if (generatedOrders.isNotEmpty && pendingOrder == null) _buildOrderStatusCard(
                  icon: Icons.description_rounded,
                  statusLabel: "DRAFT",
                  statusColor: Colors.orange,
                  items: generatedOrders,
                  createdDate: generatedOrderDate,
                  totalQty: _sumOrderItems(generatedOrders),
                ),

                if (pendingOrder != null && lastSubmittedOrder != null)
                  const SizedBox(height: 12),

                // ---- SUBMITTED ORDER CARD ----
                if (lastSubmittedOrder != null) _buildOrderStatusCard(
                  icon: Icons.check_circle,
                  statusLabel: "SUBMITTED",
                  statusColor: Colors.blue,
                  items: (lastSubmittedOrder!['items'] as List<dynamic>?) ?? [],
                  createdDate: lastSubmittedOrder!['created_at']?.toString() ?? '',
                  totalQty: _sumOrderItems(lastSubmittedOrder!['items'] as List? ?? []),
                ),

                const SizedBox(height: 16),

                // ---- CURRENT ORDER ACTIONS CARD ----
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 20, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            Text(
                              "Current Order Actions",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Export buttons (always visible for any active order)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: exportOrderAsPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                label: const Text("Export PDF"),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: exportOrderAsCsv,
                                icon: const Icon(Icons.table_chart_outlined, size: 18),
                                label: const Text("Export CSV"),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Submit to PKD (for DRAFT / pendingOrder)
                        if (pendingOrder != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: submitOrder,
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: const Text(
                                "Submit to PKD",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // Mark as Received (for SUBMITTED)
                        if (lastSubmittedOrder != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: markOrderReceived,
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text(
                                "Mark as Received",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // DEMO MODE ONLY
                          // Real deployment should disable submitted order cancellation.
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: cancelSubmittedOrder,
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text(
                                "Cancel Submitted Order",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],

                        // Cancel Draft Order (for DRAFT / pendingOrder)
                        if (pendingOrder != null) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: cancelDraftOrder,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text(
                                "Cancel Draft Order",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],

              // 🔄 LOADING
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= KPI CARD WIDGET =================

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
