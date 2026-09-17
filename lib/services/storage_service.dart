import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/vt_verdict.dart';

const _kVtApiKeyStorageKey = 'virustotal_api_key';

/// Lokalna vztrajnost: VirusTotal API ključ (varno, ločeno od baze),
/// predpomnilnik VT rezultatov (da ne poizvedujemo znova za isti hash) in
/// kratka zgodovina pregledov (za trend ocene tveganja skozi čas).
///
/// Vse ostane na napravi - noben del teh podatkov se ne pošilja nikamor
/// razen samega VirusTotal API klica (glej `VirusTotalService`), ki
/// namenoma pošlje SAMO SHA-256 hash datoteke, nikoli vsebine APK-ja same.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _secureStorage = FlutterSecureStorage();
  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'sentryscan.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vt_cache (
            sha256 TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            maliciousCount INTEGER NOT NULL,
            suspiciousCount INTEGER NOT NULL,
            harmlessCount INTEGER NOT NULL,
            undetectedCount INTEGER NOT NULL,
            checkedAt INTEGER NOT NULL,
            errorMessage TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE scan_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            generatedAt INTEGER NOT NULL,
            riskScore INTEGER NOT NULL,
            findingsCount INTEGER NOT NULL,
            criticalCount INTEGER NOT NULL,
            highCount INTEGER NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  // --- VirusTotal API ključ (varna shramba, ločena od SQLite baze) ---

  Future<String?> getVtApiKey() => _secureStorage.read(key: _kVtApiKeyStorageKey);

  Future<void> setVtApiKey(String apiKey) =>
      _secureStorage.write(key: _kVtApiKeyStorageKey, value: apiKey);

  Future<void> clearVtApiKey() => _secureStorage.delete(key: _kVtApiKeyStorageKey);

  // --- VirusTotal predpomnilnik ---

  Future<VtVerdict?> getCachedVtVerdict(String sha256, {Duration maxAge = const Duration(days: 7)}) async {
    final db = await _database;
    final rows = await db.query('vt_cache', where: 'sha256 = ?', whereArgs: [sha256]);
    if (rows.isEmpty) return null;
    final verdict = VtVerdict.fromDbMap(rows.first);
    if (DateTime.now().difference(verdict.checkedAt) > maxAge) return null;
    return verdict;
  }

  Future<void> cacheVtVerdict(VtVerdict verdict) async {
    final db = await _database;
    await db.insert(
      'vt_cache',
      verdict.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Zgodovina pregledov (za trend prikaz) ---

  Future<void> recordScanSummary({
    required DateTime generatedAt,
    required int riskScore,
    required int findingsCount,
    required int criticalCount,
    required int highCount,
  }) async {
    final db = await _database;
    await db.insert('scan_history', {
      'generatedAt': generatedAt.millisecondsSinceEpoch,
      'riskScore': riskScore,
      'findingsCount': findingsCount,
      'criticalCount': criticalCount,
      'highCount': highCount,
    });
  }

  Future<List<Map<String, Object?>>> getScanHistory({int limit = 30}) async {
    final db = await _database;
    return db.query('scan_history', orderBy: 'generatedAt DESC', limit: limit);
  }

  // --- Preproste nastavitve ---

  Future<bool> isBatterySamplingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('battery_sampling_enabled') ?? false;
  }

  Future<void> setBatterySamplingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_sampling_enabled', enabled);
  }

  Future<bool> vtLookupsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('vt_lookups_enabled') ?? false;
  }

  Future<void> setVtLookupsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vt_lookups_enabled', enabled);
  }
}
