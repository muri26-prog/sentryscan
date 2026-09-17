import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/vt_verdict.dart';
import 'storage_service.dart';

typedef VtProgressCallback = void Function(int done, int total, String currentLabel);

/// Odjemalec za VirusTotal API v3 (poizvedba po datotečnem hashu, brez
/// nalaganja same datoteke). Pošlje SAMO SHA-256 - nikoli vsebine APK-ja.
///
/// Javni (brezplačni) VirusTotal API ključ ima trdo omejitev ~4 zahtevkov na
/// minuto in ~500 na dan - zato ta razred zahtevke izvaja ZAPOREDNO z
/// vsiljenim premorom med njimi, ne glede na to, koliko aplikacij je za
/// preverjanje. Rezultati se predpomnijo (`StorageService`), da se isti
/// hash ne poizveduje znova prej kot čez `cacheMaxAge`.
class VirusTotalService {
  VirusTotalService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _minDelayBetweenRequests = Duration(seconds: 16);
  DateTime? _lastRequestAt;

  Future<VtVerdict> lookupHash(String sha256, String apiKey) async {
    await _respectRateLimit();

    final uri = Uri.parse('https://www.virustotal.com/api/v3/files/$sha256');
    late final http.Response response;
    try {
      response = await _client.get(uri, headers: {'x-apikey': apiKey}).timeout(
            const Duration(seconds: 20),
          );
    } catch (e) {
      return VtVerdict.error(sha256, 'Omrežna napaka: $e');
    } finally {
      _lastRequestAt = DateTime.now();
    }

    if (response.statusCode == 404) {
      return VtVerdict.unknown(sha256);
    }
    if (response.statusCode == 429) {
      return VtVerdict(
        sha256: sha256,
        status: VtStatus.rateLimited,
        maliciousCount: 0,
        suspiciousCount: 0,
        harmlessCount: 0,
        undetectedCount: 0,
        checkedAt: DateTime.now(),
        errorMessage: 'VirusTotal je omejil hitrost poizvedb - poskusi znova kasneje.',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return VtVerdict.error(sha256, 'API ključ ni veljaven ali nima dostopa.');
    }
    if (response.statusCode != 200) {
      return VtVerdict.error(sha256, 'Nepričakovan odgovor VirusTotal (${response.statusCode}).');
    }

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final attributes = (body['data'] as Map<String, dynamic>)['attributes'] as Map<String, dynamic>;
      final stats = attributes['last_analysis_stats'] as Map<String, dynamic>;
      final malicious = (stats['malicious'] as num?)?.toInt() ?? 0;
      final suspicious = (stats['suspicious'] as num?)?.toInt() ?? 0;
      final harmless = (stats['harmless'] as num?)?.toInt() ?? 0;
      final undetected = (stats['undetected'] as num?)?.toInt() ?? 0;

      final status = malicious > 0
          ? VtStatus.malicious
          : (suspicious > 0 ? VtStatus.suspicious : VtStatus.clean);

      return VtVerdict(
        sha256: sha256,
        status: status,
        maliciousCount: malicious,
        suspiciousCount: suspicious,
        harmlessCount: harmless,
        undetectedCount: undetected,
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      return VtVerdict.error(sha256, 'Napaka pri branju odgovora: $e');
    }
  }

  /// Preveri seznam (packageName, sha256) parov, uporabi predpomnilnik kjer
  /// je mogoče, sicer poizveduje zaporedno z zamikom. Kliče [onProgress] po
  /// vsakem koraku, da lahko UI prikaže napredek dolgega pregleda.
  Future<Map<String, VtVerdict>> checkMany(
    Map<String, String> sha256ByPackageName,
    String apiKey, {
    VtProgressCallback? onProgress,
  }) async {
    final results = <String, VtVerdict>{};
    final entries = sha256ByPackageName.entries.toList();

    for (var i = 0; i < entries.length; i++) {
      final packageName = entries[i].key;
      final sha256 = entries[i].value;
      onProgress?.call(i, entries.length, packageName);

      final cached = await StorageService.instance.getCachedVtVerdict(sha256);
      if (cached != null) {
        results[packageName] = cached;
        continue;
      }

      final verdict = await lookupHash(sha256, apiKey);
      await StorageService.instance.cacheVtVerdict(verdict);
      results[packageName] = verdict;
    }

    onProgress?.call(entries.length, entries.length, '');
    return results;
  }

  Future<void> _respectRateLimit() async {
    final last = _lastRequestAt;
    if (last == null) return;
    final elapsed = DateTime.now().difference(last);
    if (elapsed < _minDelayBetweenRequests) {
      await Future.delayed(_minDelayBetweenRequests - elapsed);
    }
  }

  void dispose() => _client.close();
}
