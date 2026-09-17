import 'package:permission_handler/permission_handler.dart';

import 'native_bridge.dart';

/// Zbirka pomožnih metod za dovoljenja, ki jih Android NE dovoljuje
/// zahtevati z navadnim runtime dialogom (Usage access, Accessibility,
/// Notification listener, izjema od varčevanja baterije) - za te samo
/// odpremo pravi zaslon v Nastavitvah in uporabnik odloči sam. Edino
/// pravo "runtime permission" v tej aplikaciji je POST_NOTIFICATIONS.
class PermissionGateService {
  const PermissionGateService();

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> isNotificationGranted() async {
    return (await Permission.notification.status).isGranted;
  }

  /// Za IZJEMO OD VARČEVANJA BATERIJE ZA LASTNO APLIKACIJO uporabimo
  /// permission_handler (zna prikazati pravi sistemski dialog za točno to
  /// aplikacijo) namesto ročnega Intent-a - manj kode, enak rezultat.
  Future<bool> isIgnoringBatteryOptimizationsForSelf() async {
    return (await Permission.ignoreBatteryOptimizations.status).isGranted;
  }

  Future<bool> requestIgnoreBatteryOptimizationsForSelf() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<void> openUsageAccessSettings() =>
      NativeBridge.instance.openSpecialSetting('usage_access');

  Future<void> openAccessibilitySettings() =>
      NativeBridge.instance.openSpecialSetting('accessibility_settings');

  Future<void> openNotificationListenerSettings() =>
      NativeBridge.instance.openSpecialSetting('notification_listener_settings');

  Future<void> openSecuritySettings() =>
      NativeBridge.instance.openSpecialSetting('security_settings');

  Future<void> openBatteryOptimizationSettings() =>
      NativeBridge.instance.openSpecialSetting('battery_optimization_all');
}
