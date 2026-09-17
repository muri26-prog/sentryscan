const kPlayStoreInstaller = 'com.android.vending';

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

  /// Android-ova lastna ocena, ali je aplikacija trenutno "neaktivna"
  /// (`UsageStatsManager.isAppInactive`). `null`, če dostop do statistike
  /// uporabe (Usage access) ni odobren.
  final bool? isAppInactive;

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
    required this.isAppInactive,
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
      isAppInactive: map['isAppInactive'] as bool?,
    );
  }

  /// Poti pod temi mapami so del bralno-zaščitenih sistemskih particij -
  /// aplikacija tja lahko pride SAMO ob izdelavi/OTA posodobitvi naprave, ne
  /// z naknadno (ročno ali zlonamerno) namestitvijo brez root dostopa. To je
  /// zanesljivejši signal "prišla je s telefonom" kot `installerPackageName`,
  /// ki je na marsikateri OEM prednameščeni aplikaciji (Samsung/Xiaomi/...)
  /// pogosto `null`, kar bi jo brez tega preverjanja napačno označilo za
  /// sideload.
  static const _kSystemPartitionPrefixes = [
    '/system/',
    '/system_ext/',
    '/vendor/',
    '/product/',
    '/odm/',
    '/apex/',
  ];

  bool get isOnSystemPartition =>
      apkPath != null && _kSystemPartitionPrefixes.any((p) => apkPath!.startsWith(p));

  /// Prišla je s telefonom (tovarniško ali prek OTA), ne glede na to, ali je
  /// OS to konkretno aplikacijo označil z zastavico FLAG_SYSTEM.
  bool get isPreinstalled => isSystemApp || isUpdatedSystemApp || isOnSystemPartition;

  bool get isFromPlayStore => installerPackageName == kPlayStoreInstaller;

  /// Aplikacija, ki je NI prišla s telefonom IN ni bila nameščena prek
  /// Google Play - torej jo je nekdo namestil naknadno mimo uradne trgovine
  /// (APK datoteka, drug app store, ADB, MDM ...). To je precej ožji in
  /// zanesljivejši pogoj kot zgolj "installerPackageName ni Play Store", ki
  /// bi sam zase napačno zajel na stotine legitimnih OEM komponent.
  bool get isSideloaded => !isPreinstalled && !isFromPlayStore;

  bool hasPermission(String permission) => grantedPermissions.contains(permission);

  bool hasAnyPermission(Iterable<String> permissions) =>
      permissions.any((p) => grantedPermissions.contains(p));

  /// Sistemska ocena "je trenutno aktivna" - obratno od [isAppInactive].
  /// `null`, če ni na voljo (ni odobrenega dostopa do Usage access).
  bool? get isActiveAccordingToSystem => isAppInactive == null ? null : !isAppInactive!;
}
