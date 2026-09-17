/// Surovi sistemski varnostni podatki, kot jih vrne
/// `NativeScanner.getSystemSecuritySnapshot`.
class SystemSecuritySnapshot {
  final List<String> enabledAccessibilityServices;
  final List<String> enabledNotificationListeners;
  final List<String> activeDeviceAdmins;
  final bool adbEnabled;
  final bool developerOptionsEnabled;
  final bool isDeviceEncrypted;
  final bool hasActiveVpn;
  final String? httpProxyDescription;
  final bool screenLockEnabled;
  final bool usageAccessGranted;
  final bool isLikelyRooted;
  final List<String> rootIndicators;
  final String androidVersion;
  final int sdkInt;
  final String manufacturer;
  final String model;
  final String buildFingerprint;
  final String buildTags;

  const SystemSecuritySnapshot({
    required this.enabledAccessibilityServices,
    required this.enabledNotificationListeners,
    required this.activeDeviceAdmins,
    required this.adbEnabled,
    required this.developerOptionsEnabled,
    required this.isDeviceEncrypted,
    required this.hasActiveVpn,
    required this.httpProxyDescription,
    required this.screenLockEnabled,
    required this.usageAccessGranted,
    required this.isLikelyRooted,
    required this.rootIndicators,
    required this.androidVersion,
    required this.sdkInt,
    required this.manufacturer,
    required this.model,
    required this.buildFingerprint,
    required this.buildTags,
  });

  factory SystemSecuritySnapshot.fromMap(Map<dynamic, dynamic> map) {
    return SystemSecuritySnapshot(
      enabledAccessibilityServices:
          (map['enabledAccessibilityServices'] as List?)?.cast<String>() ?? const [],
      enabledNotificationListeners:
          (map['enabledNotificationListeners'] as List?)?.cast<String>() ?? const [],
      activeDeviceAdmins: (map['activeDeviceAdmins'] as List?)?.cast<String>() ?? const [],
      adbEnabled: (map['adbEnabled'] as bool?) ?? false,
      developerOptionsEnabled: (map['developerOptionsEnabled'] as bool?) ?? false,
      isDeviceEncrypted: (map['isDeviceEncrypted'] as bool?) ?? false,
      hasActiveVpn: (map['hasActiveVpn'] as bool?) ?? false,
      httpProxyDescription: map['httpProxyDescription'] as String?,
      screenLockEnabled: (map['screenLockEnabled'] as bool?) ?? false,
      usageAccessGranted: (map['usageAccessGranted'] as bool?) ?? false,
      isLikelyRooted: (map['isLikelyRooted'] as bool?) ?? false,
      rootIndicators: (map['rootIndicators'] as List?)?.cast<String>() ?? const [],
      androidVersion: (map['androidVersion'] as String?) ?? '?',
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      manufacturer: (map['manufacturer'] as String?) ?? '?',
      model: (map['model'] as String?) ?? '?',
      buildFingerprint: (map['buildFingerprint'] as String?) ?? '',
      buildTags: (map['buildTags'] as String?) ?? '',
    );
  }

  /// Ali je dano ime paketa lastnik ene od komponent v seznamu (format
  /// Android "ComponentName.flattenToString()" je `pkg/pkg.Razred`).
  static bool _ownsComponent(List<String> components, String packageName) {
    return components.any((c) => c.startsWith('$packageName/'));
  }

  bool hasEnabledAccessibilityService(String packageName) =>
      _ownsComponent(enabledAccessibilityServices, packageName);

  bool hasEnabledNotificationListener(String packageName) =>
      _ownsComponent(enabledNotificationListeners, packageName);

  bool hasActiveDeviceAdmin(String packageName) =>
      _ownsComponent(activeDeviceAdmins, packageName);
}
