import 'package:flutter/services.dart';

import '../models/app_info.dart';
import '../models/battery_sample.dart';
import '../models/system_security_snapshot.dart';

/// Tanek ovoj okoli `MethodChannel` proti Kotlin `NativeScanner`/
/// `MainActivity`. Vsa dejanska sistemska logika živi na Android strani -
/// ta razred samo (de)serializira klice.
class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _channel = MethodChannel('com.sentryscan.app/native');

  Future<List<AppInfo>> getInstalledApps() async {
    final result = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
    return (result ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map(AppInfo.fromMap)
        .toList(growable: false);
  }

  Future<String?> computeApkSha256(String packageName) {
    return _channel.invokeMethod<String>('computeApkSha256', {'packageName': packageName});
  }

  Future<SystemSecuritySnapshot> getSystemSecuritySnapshot() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getSystemSecuritySnapshot');
    return SystemSecuritySnapshot.fromMap(result ?? const {});
  }

  /// Vrne mapo packageName -> skupni čas v ospredju (ms) v zadnjih [days]
  /// dneh. Prazna mapa, če uporabnik ni odobril dostopa do "Usage access".
  Future<Map<String, int>> getUsageStats({int days = 7}) async {
    final result = await _channel.invokeMethod<List<dynamic>>('getUsageStats', {'days': days});
    final map = <String, int>{};
    for (final entry in (result ?? const [])) {
      final e = entry as Map<dynamic, dynamic>;
      final pkg = e['packageName'] as String?;
      final time = (e['totalForegroundTimeMs'] as num?)?.toInt();
      if (pkg != null && time != null) {
        map[pkg] = time;
      }
    }
    return map;
  }

  Future<BatterySample> getBatterySnapshot() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getBatterySnapshot');
    return BatterySample.fromMap(result ?? const {});
  }

  Future<BatterySample> captureBatterySampleNow() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('captureBatterySampleNow');
    return BatterySample.fromMap(result ?? const {});
  }

  Future<List<BatterySample>> readBatteryHistory({required DateTime since}) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'readBatteryHistory',
      {'sinceEpochMs': since.millisecondsSinceEpoch},
    );
    return (result ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map(BatterySample.fromMap)
        .toList(growable: false);
  }

  Future<void> scheduleBatterySampling() {
    return _channel.invokeMethod('scheduleBatterySampling');
  }

  Future<void> cancelBatterySampling() {
    return _channel.invokeMethod('cancelBatterySampling');
  }

  /// `target` eno od: usage_access, accessibility_settings,
  /// notification_listener_settings, security_settings,
  /// battery_optimization_all, request_ignore_battery_optimizations_self.
  Future<void> openSpecialSetting(String target) {
    return _channel.invokeMethod('openSpecialSetting', {'target': target});
  }

  Future<void> openAppDetailsSettings(String packageName) {
    return _channel.invokeMethod('openAppDetailsSettings', {'packageName': packageName});
  }
}
