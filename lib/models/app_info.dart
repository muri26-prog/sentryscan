/// Android `UsageStatsManager.STANDBY_BUCKET_*` vrednosti - kopija konstant,
/// da jih lahko beremo brez dodatne odvisnosti od native strani.
class StandbyBucket {
  static const int active = 10;
  static const int workingSet = 20;
  static const int frequent = 30;
  static const int rare = 40;
  static const int restricted = 45;
  static const int never = 50;

  static String label(int? bucket) {
    switch (bucket) {
      case active:
        return 'Aktivna';
      case workingSet:
        return 'Delovni nabor';
      case frequent:
        return 'Pogosto uporabljena';
      case rare:
        return 'Redko uporabljena';
      case restricted:
        return 'Omejena';
      case never:
        return 'Nikoli uporabljena';
      default:
        return 'Neznano';
    }
  }
}

/// Znani "installer" paketi za Play Store / sistemski nameščevalnik - vse
/// drugo (ali `null`) štejemo kot sideload za namene analize tveganja.
const kPlayStoreInstaller = 'com.android.vending';
const kKnownSystemInstallers = {
  kPlayStoreInstaller,
  'com.google.android.packageinstaller',
  'com.android.packageinstaller',
  'com.google.android.gms', // npr. Play System updates / instant apps
};

/// Surovi podatki o eni nameščeni aplikaciji, kot jih vrne
/// `NativeScanner.getInstalledApps` na Android strani. Ta razred namenoma NE
/// vsebuje ocene tveganja - to izračuna `HeuristicsEngine`.
class AppInfo {
  final String packageName;
  final String appLabel;
  final String? versionName;
  final int versionCode;
  final DateTime firstInstallTime;
  final DateTime lastUpdateTime;
  final String? installerPackageName;
  final bool isSystemApp;
  final bool isUpdatedSystemApp;
  final bool hasLauncherIcon;
  final List<String> requestedPermissions;
  final List<String> grantedPermissions;
  final String? signingCertSha256;
  final String? apkPath;
  final int apkSizeBytes;
  final bool isIgnoringBatteryOptimizations;
  final int? standbyBucket;

  const AppInfo({
    required this.packageName,
    required this.appLabel,
    required this.versionName,
    required this.versionCode,
    required this.firstInstallTime,
    required this.lastUpdateTime,
    required this.installerPackageName,
    required this.isSystemApp,
    required this.isUpdatedSystemApp,
    required this.hasLauncherIcon,
    required this.requestedPermissions,
    required this.grantedPermissions,
    required this.signingCertSha256,
    required this.apkPath,
    required this.apkSizeBytes,
    required this.isIgnoringBatteryOptimizations,
    required this.standbyBucket,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String,
      appLabel: (map['appLabel'] as String?) ?? map['packageName'] as String,
      versionName: map['versionName'] as String?,
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      firstInstallTime: DateTime.fromMillisecondsSinceEpoch(
        (map['firstInstallTime'] as num?)?.toInt() ?? 0,
      ),
      lastUpdateTime: DateTime.fromMillisecondsSinceEpoch(
        (map['lastUpdateTime'] as num?)?.toInt() ?? 0,
      ),
      installerPackageName: map['installerPackageName'] as String?,
      isSystemApp: (map['isSystemApp'] as bool?) ?? false,
      isUpdatedSystemApp: (map['isUpdatedSystemApp'] as bool?) ?? false,
      hasLauncherIcon: (map['hasLauncherIcon'] as bool?) ?? true,
      requestedPermissions: (map['requestedPermissions'] as List?)?.cast<String>() ?? const [],
      grantedPermissions: (map['grantedPermissions'] as List?)?.cast<String>() ?? const [],
      signingCertSha256: map['signingCertSha256'] as String?,
      apkPath: map['apkPath'] as String?,
      apkSizeBytes: (map['apkSizeBytes'] as num?)?.toInt() ?? 0,
      isIgnoringBatteryOptimizations: (map['isIgnoringBatteryOptimizations'] as bool?) ?? false,
      standbyBucket: (map['standbyBucket'] as num?)?.toInt(),
    );
  }

  bool get isSideloaded =>
      installerPackageName == null || !kKnownSystemInstallers.contains(installerPackageName);

  bool hasPermission(String permission) => grantedPermissions.contains(permission);

  bool hasAnyPermission(Iterable<String> permissions) =>
      permissions.any((p) => grantedPermissions.contains(p));

  String get standbyBucketLabel => StandbyBucket.label(standbyBucket);
}
