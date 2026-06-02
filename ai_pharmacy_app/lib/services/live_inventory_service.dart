import 'dart:convert';
import 'package:http/http.dart' as http;

class LiveInventoryService {
  static const String baseUrl = "http://localhost:5000";

  static Future<List<dynamic>> fetchLiveInventory({String? clinicId}) async {
    try {
      final uri = clinicId != null
          ? Uri.parse("$baseUrl/api/live_inventory?clinic_id=$clinicId")
          : Uri.parse("$baseUrl/api/live_inventory");
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['inventory'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchDispenseHistory({String? clinicId}) async {
    try {
      final uri = clinicId != null
          ? Uri.parse("$baseUrl/api/dispense_history?clinic_id=$clinicId")
          : Uri.parse("$baseUrl/api/dispense_history");
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['dispense_transactions'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
