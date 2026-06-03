import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class SyncResult {
  final bool online;
  final int uploaded;
  final int downloaded;
  final String? error;

  SyncResult({
    this.online = false,
    this.uploaded = 0,
    this.downloaded = 0,
    this.error,
  });
}

class SyncService {
  static const String _baseUrl = "http://localhost:5000";
  static Database? _database;
  static String? _deviceId;

  // ─── Database ───────────────────────────────────────────────

  static Future<Database> get _db async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'local_inventory.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
    return _database!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_inventory (
        item_code TEXT PRIMARY KEY,
        quantity INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        clinic_id TEXT,
        full_brand_name TEXT,
        match_name TEXT,
        strength TEXT,
        dosage_form TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_transactions (
        id TEXT PRIMARY KEY,
        item_code TEXT NOT NULL,
        device_id TEXT NOT NULL,
        quantity_change INTEGER NOT NULL,
        quantity_after INTEGER,
        action TEXT NOT NULL,
        ocr_text TEXT,
        matched_name TEXT,
        matched_strength TEXT,
        confidence REAL,
        local_created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        clinic_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ─── First-time init ───────────────────────────────────────

  static Future<void> initialize(String clinicId) async {
    final db = await _db;
    final initialized = await _getMetadata('initialized');
    if (initialized == 'true') return;

    // Fetch all seed data from APIs
    String? medError, invError, histError;
    List<dynamic> medicines = [];
    List<dynamic> inventory = [];
    List<dynamic> history = [];

    try {
      final medResp = await http
          .get(Uri.parse('$_baseUrl/api/medicine_catalog'))
          .timeout(const Duration(seconds: 10));
      if (medResp.statusCode == 200) {
        medicines = (json.decode(medResp.body) as Map)['medicines'] as List? ?? [];
      }
    } catch (e) {
      medError = e.toString();
    }

    try {
      final invResp = await http
          .get(Uri.parse('$_baseUrl/api/live_inventory?clinic_id=$clinicId'))
          .timeout(const Duration(seconds: 10));
      if (invResp.statusCode == 200) {
        inventory = (json.decode(invResp.body) as Map)['inventory'] as List? ?? [];
      }
    } catch (e) {
      invError = e.toString();
    }

    try {
      final histResp = await http
          .get(Uri.parse('$_baseUrl/api/dispense_history?clinic_id=$clinicId'))
          .timeout(const Duration(seconds: 10));
      if (histResp.statusCode == 200) {
        history = (json.decode(histResp.body) as Map)['dispense_transactions']
            as List? ?? [];
      }
    } catch (e) {
      histError = e.toString();
    }

    // Seed local_inventory from medicines + inventory
    final medMap = <String, Map<String, dynamic>>{};
    for (final m in medicines) {
      if (m is Map) {
        final code = m['item_code']?.toString();
        if (code != null) medMap[code] = Map<String, dynamic>.from(m);
      }
    }
    final invMap = <String, Map<String, dynamic>>{};
    for (final inv in inventory) {
      if (inv is Map) {
        final code = inv['item_code']?.toString();
        if (code != null) invMap[code] = Map<String, dynamic>.from(inv);
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final allCodes = <String>{...medMap.keys, ...invMap.keys};

    await db.transaction((txn) async {
      for (final code in allCodes) {
        final med = medMap[code] ?? {};
        final inv = invMap[code] ?? {};
        await txn.insert('local_inventory', {
          'item_code': code,
          'quantity': (inv['quantity'] ?? 0) as num,
          'updated_at': (inv['updated_at'] ?? now).toString(),
          'clinic_id': clinicId,
          'full_brand_name': (med['full_brand_name'] ?? inv['full_brand_name'] ?? '').toString(),
          'match_name': (med['match_name'] ?? inv['match_name'] ?? '').toString(),
          'strength': (med['strength'] ?? inv['strength'] ?? '').toString(),
          'dosage_form': (med['dosage_form'] ?? inv['dosage_form'] ?? '').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    // Seed local_transactions from history (mark all as synced)
    if (history.isNotEmpty) {
      await db.transaction((txn) async {
        for (final txnItem in history) {
          if (txnItem is! Map) continue;
          await txn.insert('local_transactions', {
            'id': (txnItem['id'] ?? '').toString(),
            'item_code': (txnItem['item_code'] ?? '').toString(),
            'device_id': (txnItem['device_id'] ?? '').toString(),
            'quantity_change': (txnItem['quantity_change'] ?? 0) as num,
            'quantity_after': txnItem['quantity_after'],
            'action': (txnItem['action'] ?? '').toString(),
            'ocr_text': (txnItem['ocr_text'] ?? '').toString(),
            'matched_name': (txnItem['matched_name'] ?? '').toString(),
            'matched_strength': (txnItem['matched_strength'] ?? '').toString(),
            'confidence': (txnItem['confidence'] ?? 0) as num,
            'local_created_at': (txnItem['local_created_at'] ?? now).toString(),
            'synced': 1,
            'clinic_id': clinicId,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    }

    await _setMetadata('initialized', 'true');
    await _setMetadata('last_sync_time', now);

    final errs = <String>[];
    if (medError != null) errs.add('medicines: $medError');
    if (invError != null) errs.add('inventory: $invError');
    if (histError != null) errs.add('history: $histError');
    if (errs.isNotEmpty) {
      debugPrint('SyncService.init partial errors: ${errs.join("; ")}');
    }
  }

  // ─── Full sync cycle ───────────────────────────────────────

  static Future<SyncResult> fullSync(String clinicId) async {
    try {
      await _db; // ensure DB exists
    } catch (e) {
      return SyncResult(error: 'DB init failed: $e');
    }

    final online = await _checkOnline();
    if (!online) return SyncResult(online: false);

    int uploaded = 0;
    int downloaded = 0;

    try {
      uploaded = await _uploadPending(clinicId);
    } catch (e) {
      debugPrint('SyncService upload error: $e');
    }

    try {
      downloaded = await _downloadInventory(clinicId);
    } catch (e) {
      debugPrint('SyncService download error: $e');
    }

    await _setMetadata('last_sync_time', DateTime.now().toUtc().toIso8601String());

    return SyncResult(online: true, uploaded: uploaded, downloaded: downloaded);
  }

  // ─── Record dispense (offline-first) ────────────────────────

  static Future<void> recordDispense({
    required String clinicId,
    required String itemCode,
    required int quantityChange,
    required int quantityAfter,
    required String action,
    String? ocrText,
    String? matchedName,
    String? matchedStrength,
    double? confidence,
  }) async {
    final db = await _db;
    final id = const Uuid().v4();
    final deviceId = await _getDeviceId();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert('local_transactions', {
        'id': id,
        'item_code': itemCode,
        'device_id': deviceId,
        'quantity_change': quantityChange,
        'quantity_after': quantityAfter,
        'action': action,
        'ocr_text': ocrText ?? '',
        'matched_name': matchedName ?? '',
        'matched_strength': matchedStrength ?? '',
        'confidence': confidence ?? 0,
        'local_created_at': now,
        'synced': 0,
        'clinic_id': clinicId,
      });

      await txn.update(
        'local_inventory',
        {'quantity': quantityAfter, 'updated_at': now},
        where: 'item_code = ?',
        whereArgs: [itemCode],
      );
    });
  }

  // ─── Read local inventory (offline fallback) ────────────────

  static Future<List<Map<String, dynamic>>> getLocalInventory({
    String? clinicId,
  }) async {
    final db = await _db;
    if (clinicId != null) {
      return db.query('local_inventory',
          where: 'clinic_id = ?', whereArgs: [clinicId]);
    }
    return db.query('local_inventory');
  }

  // ─── Sync metadata helpers ─────────────────────────────────

  static Future<String?> _getMetadata(String key) async {
    final db = await _db;
    final rows = await db.query('sync_metadata',
        where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  static Future<void> _setMetadata(String key, String value) async {
    final db = await _db;
    await db.insert('sync_metadata', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String> lastSyncTime() async {
    final val = await _getMetadata('last_sync_time');
    return val ?? 'Never';
  }

  static Future<int> pendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM local_transactions WHERE synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ─── Device ID ──────────────────────────────────────────────

  static Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    var stored = await _getMetadata('device_id');
    if (stored == null) {
      stored = const Uuid().v4();
      await _setMetadata('device_id', stored);
    }
    _deviceId = stored;
    return stored;
  }

  // ─── Upload pending ─────────────────────────────────────────

  static Future<int> _uploadPending(String clinicId) async {
    final db = await _db;
    final pending = await db.query('local_transactions',
        where: 'synced = 0', whereArgs: []);

    if (pending.isEmpty) return 0;

    final payload = {
      'clinic_id': clinicId,
      'transactions': pending.map((row) => {
        'id': row['id']?.toString() ?? '',
        'item_code': row['item_code']?.toString() ?? '',
        'device_id': row['device_id']?.toString() ?? '',
        'quantity_change': row['quantity_change'] ?? 0,
        'quantity_after': row['quantity_after'],
        'action': row['action']?.toString() ?? '',
        'ocr_text': row['ocr_text']?.toString() ?? '',
        'matched_name': row['matched_name']?.toString() ?? '',
        'matched_strength': row['matched_strength']?.toString() ?? '',
        'confidence': row['confidence'] ?? 0,
        'local_created_at': row['local_created_at']?.toString() ?? '',
        'clinic_id': clinicId,
      }).toList(),
    };

    final resp = await http
        .post(
          Uri.parse('$_baseUrl/api/sync/dispense'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) return 0;

    final result = json.decode(resp.body) as Map;
    final syncedIds =
        (result['synced_ids'] as List?)?.map((e) => e.toString()).toList() ?? [];

    if (syncedIds.isNotEmpty) {
      final placeholders = syncedIds.map((_) => '?').join(',');
      await db.update(
        'local_transactions',
        {'synced': 1},
        where: 'id IN ($placeholders)',
        whereArgs: syncedIds,
      );
    }

    return syncedIds.length;
  }

  // ─── Download inventory ─────────────────────────────────────

  static Future<int> _downloadInventory(String clinicId) async {
    final resp = await http
        .get(Uri.parse('$_baseUrl/api/live_inventory?clinic_id=$clinicId'))
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) return 0;

    final body = json.decode(resp.body) as Map;
    final items = (body['inventory'] as List?) ?? [];

    if (items.isEmpty) return 0;

    final db = await _db;
    int count = 0;
    await db.transaction((txn) async {
      for (final item in items) {
        if (item is! Map) continue;
        final code = item['item_code']?.toString();
        if (code == null || code.isEmpty) continue;
        await txn.insert('local_inventory', {
          'item_code': code,
          'quantity': (item['quantity'] ?? 0) as num,
          'updated_at': (item['updated_at'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
          'clinic_id': clinicId,
          'full_brand_name': (item['full_brand_name'] ?? '').toString(),
          'match_name': (item['match_name'] ?? '').toString(),
          'strength': (item['strength'] ?? '').toString(),
          'dosage_form': (item['dosage_form'] ?? '').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
    });
    return count;
  }

  // ─── Connectivity ──────────────────────────────────────────

  static Future<bool> _checkOnline() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/sync/status'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return false;
      final body = json.decode(resp.body) as Map;
      return body['online'] == true;
    } catch (_) {
      return false;
    }
  }

  // ─── Cleanup ────────────────────────────────────────────────

  static Future<void> clear() async {
    final db = await _db;
    await db.delete('local_inventory');
    await db.delete('local_transactions');
    await db.delete('sync_metadata');
    _deviceId = null;
  }
}
