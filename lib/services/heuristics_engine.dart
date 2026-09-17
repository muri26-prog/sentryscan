import '../models/app_info.dart';
import '../models/risk_finding.dart';
import '../models/system_security_snapshot.dart';
import '../models/vt_verdict.dart';

/// Dovoljenja, ki omogočajo dostop do občutljivih zasebnih podatkov
/// (mikrofon, kamera, lokacija, SMS, klici, stiki). Njihova prisotnost sama
/// po sebi ni sumljiva (marsikatera legitimna aplikacija jih potrebuje) -
/// postane pomembna šele v kombinaciji z drugimi signali (sideload, skrita
/// ikona, dostopnostna storitev ...).
const kSensitivePermissions = {
  'android.permission.CAMERA',
  'android.permission.RECORD_AUDIO',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_BACKGROUND_LOCATION',
  'android.permission.READ_SMS',
  'android.permission.RECEIVE_SMS',
  'android.permission.READ_CALL_LOG',
  'android.permission.READ_CONTACTS',
  'android.permission.READ_PHONE_STATE',
  'android.permission.PROCESS_OUTGOING_CALLS',
};

const kKnownBrandKeywords = [
  'whatsapp', 'facebook', 'instagram', 'telegram', 'messenger', 'snapchat',
  'tiktok', 'wechat', 'viber', 'signal', 'gmail', 'outlook', 'paypal',
  'revolut', 'binance', 'coinbase',
];

/// Izračuna seznam `RiskFinding` iz surovih podatkov (seznam aplikacij +
/// sistemski posnetek + neobvezni VirusTotal rezultati/statistika uporabe).
/// Vsa "je to sumljivo" logika je zbrana TUKAJ - namerno ločeno od native
/// zbiranja podatkov, da lahko pravila preveriš/prilagodiš brez poseganja v
/// Android kodo.
class HeuristicsEngine {
  const HeuristicsEngine();

  List<RiskFinding> evaluate({
    required List<AppInfo> apps,
    required SystemSecuritySnapshot system,
    Map<String, int> usageForegroundMsByPackage = const {},
    Map<String, VtVerdict> vtVerdictsByPackage = const {},
  }) {
    final findings = <RiskFinding>[];

    findings.addAll(_deviceLevelFindings(system));

    // Deduplicira po packageName - PackageManager na nekaterih napravah
    // (npr. z delovnim profilom ali OEM posebnostmi) lahko isti paket vrne
    // večkrat; brez tega bi se vsaka najdba zanj podvojila.
    final uniqueApps = <String, AppInfo>{};
    for (final app in apps) {
      uniqueApps.putIfAbsent(app.packageName, () => app);
    }

    for (final app in uniqueApps.values) {
      findings.addAll(_appLevelFindings(
        app,
        system,
        usageForegroundMsByPackage[app.packageName],
        vtVerdictsByPackage[app.packageName],
      ));
    }

    return findings;
  }

  // -----------------------------------------------------------------
  // Pravila na nivoju naprave
  // -----------------------------------------------------------------

  List<RiskFinding> _deviceLevelFindings(SystemSecuritySnapshot s) {
    final findings = <RiskFinding>[];

    if (s.isLikelyRooted) {
      findings.add(RiskFinding(
        id: 'device.rooted',
        severity: RiskSeverity.high,
        title: 'Naprava je verjetno rootana',
        description: 'Zaznani znaki: ${s.rootIndicators.join(', ')}. Root dostop '
            'omogoča aplikacijam obhod normalnih varnostnih omejitev Androida in '
            'lahko skrije prisotnost nadzorne programske opreme pred tem in '
            'drugimi pregledi.',
        recommendation: 'Če si napravo rootal(a) namerno in vedoč, lahko to '
            'ugotovitev prezreš. Če ne, je to resen varnostni incident - '
            'razmisli o popolnem tovarniškem ponastavitvi.',
      ));
    }

    if (s.adbEnabled && s.developerOptionsEnabled) {
      findings.add(const RiskFinding(
        id: 'device.adb_enabled',
        severity: RiskSeverity.medium,
        title: 'USB razhroščevanje (ADB) je omogočeno',
        description: 'Možnosti za razvijalce in ADB razhroščevanje sta vklopljena. '
            'To je pogost korak, ki ga naredi nekdo s fizičnim dostopom do '
            'naprave, preden namesti nadzorno programsko opremo prek USB.',
        recommendation: 'Če tega nisi vklopil(a) namerno za razvoj, izklopi v '
            'Nastavitve > Možnosti za razvijalce.',
      ));
    }

    if (!s.screenLockEnabled) {
      findings.add(const RiskFinding(
        id: 'device.no_screen_lock',
        severity: RiskSeverity.medium,
        title: 'Naprava nima nastavljenega zaklepa zaslona',
        description: 'Brez PIN/gesla/prstnega odtisa lahko kdorkoli s kratkim '
            'fizičnim dostopom namesti aplikacije ali spremeni nastavitve.',
        recommendation: 'Nastavi zaklep zaslona v Nastavitve > Varnost.',
      ));
    }

    if (!s.isDeviceEncrypted) {
      findings.add(const RiskFinding(
        id: 'device.not_encrypted',
        severity: RiskSeverity.medium,
        title: 'Shramba naprave ni (zaznano) šifrirana',
        description: 'Brez šifriranja shrambe je vsebina naprave berljiva ob '
            'neposrednem fizičnem dostopu do strojne opreme.',
      ));
    }

    if (s.httpProxyDescription != null) {
      findings.add(RiskFinding(
        id: 'device.manual_proxy',
        severity: RiskSeverity.medium,
        title: 'Ročno konfiguriran HTTP proxy (${s.httpProxyDescription})',
        description: 'Ves ali del prometa se lahko preusmerja prek tega '
            'strežnika, kar omogoča prestrezanje ali spreminjanje prometa '
            '("man-in-the-middle").',
        recommendation: 'Če tega nisi nastavil(a) sam(a) (npr. za delo), '
            'preveri nastavitve Wi-Fi omrežja in jih po potrebi počisti.',
      ));
    }

    if (s.hasActiveVpn) {
      findings.add(const RiskFinding(
        id: 'device.active_vpn',
        severity: RiskSeverity.info,
        title: 'Aktivna je VPN povezava',
        description: 'Nekatera nadzorna orodja preusmerjajo promet prek VPN, da '
            'ga lahko pregledujejo. Če si VPN vklopil(a) sam(a), je to '
            'pričakovano in neškodljivo.',
      ));
    }

    if (s.activeDeviceAdmins.length > 1) {
      findings.add(RiskFinding(
        id: 'device.multiple_admins',
        severity: RiskSeverity.low,
        title: '${s.activeDeviceAdmins.length} aplikacij ima pravice skrbnika naprave',
        description: 'Skrbniki naprave: ${s.activeDeviceAdmins.join(', ')}. '
            'Preveri, da prepoznaš in zaupaš vsem naštetim.',
      ));
    }

    return findings;
  }

  // -----------------------------------------------------------------
  // Pravila na nivoju posamezne aplikacije
  // -----------------------------------------------------------------

  List<RiskFinding> _appLevelFindings(
    AppInfo app,
    SystemSecuritySnapshot system,
    int? usageForegroundMs,
    VtVerdict? vt,
  ) {
    final findings = <RiskFinding>[];
    void add(RiskFinding f) => findings.add(f);

    final hasAccessibility = system.hasEnabledAccessibilityService(app.packageName);
    final hasNotificationAccess = system.hasEnabledNotificationListener(app.packageName);
    final isActiveDeviceAdmin = system.hasActiveDeviceAdmin(app.packageName);
    final sensitiveGranted =
        kSensitivePermissions.where(app.grantedPermissions.contains).toList();
    final neverUsedByUser = (usageForegroundMs ?? 0) == 0;

    RiskFinding build(String suffix, RiskSeverity sev, String title, String desc, [String? rec]) =>
        RiskFinding(
          id: '${app.packageName}.$suffix',
          severity: sev,
          title: title,
          description: desc,
          relatedPackageName: app.packageName,
          relatedAppLabel: app.appLabel,
          recommendation: rec,
        );

    // --- VirusTotal ---
    if (vt != null) {
      if (vt.status == VtStatus.malicious) {
        add(build(
          'vt_malicious',
          RiskSeverity.critical,
          'VirusTotal: zaznano kot zlonamerno',
          '${vt.maliciousCount} od ${vt.maliciousCount + vt.suspiciousCount + vt.harmlessCount + vt.undetectedCount} '
              'protivirusnih pregledovalnikov na VirusTotal to aplikacijo označuje kot zlonamerno.',
          'Aplikacijo takoj odstrani in preveri druge naprave/račune, ki bi lahko bili prizadeti.',
        ));
      } else if (vt.status == VtStatus.suspicious && vt.maliciousCount == 0) {
        add(build(
          'vt_suspicious',
          RiskSeverity.medium,
          'VirusTotal: nekateri pregledovalniki jo označujejo kot sumljivo',
          '${vt.suspiciousCount} pregledovalnikov jo je označilo kot sumljivo.',
        ));
      }
    }

    // --- Dostopnostna storitev ---
    if (hasAccessibility) {
      if (app.isSideloaded && !app.hasLauncherIcon) {
        add(build(
          'hidden_accessibility',
          RiskSeverity.critical,
          'Skrita aplikacija z omogočeno dostopnostno storitvijo',
          'Aplikacija je nameščena mimo Google Play, nima ikone v meniju aplikacij '
              'in ima omogočeno dostopnostno storitev - ta kombinacija je značilna '
              'za vohunsko/nadzorno programsko opremo (lahko bere vsebino zaslona, '
              'gesla in sporočila v drugih aplikacijah).',
          'Preveri v Nastavitve > Dostopnost, kaj počne, in če je ne prepoznaš, jo odstrani.',
        ));
      } else if (app.isSideloaded) {
        add(build(
          'sideloaded_accessibility',
          RiskSeverity.high,
          'Sideloadana aplikacija z omogočeno dostopnostno storitvijo',
          'Dostopnostne storitve lahko berejo in simulirajo dotike po celotnem '
              'zaslonu. Legitimne so npr. bralniki zaslona, a v kombinaciji s '
              'sideload izvorom velja preveriti, čemu je storitev res namenjena.',
        ));
      }
    }

    // --- Obveščanje (notification listener) ---
    if (hasNotificationAccess && app.isSideloaded) {
      add(build(
        'notification_listener',
        RiskSeverity.high,
        'Bere vsa sistemska obvestila',
        'Aplikacija ima dostop do vseh prejetih obvestil na napravi (SMS/2FA '
            'kode, sporočila iz klepetov ipd.), nameščena pa je bila mimo Google Play.',
      ));
    }

    // --- Device admin ---
    if (isActiveDeviceAdmin && !app.hasLauncherIcon && !app.isPreinstalled) {
      add(build(
        'hidden_device_admin',
        RiskSeverity.critical,
        'Skrita aplikacija s pravicami skrbnika naprave',
        'Aplikacija nima ikone v meniju in ima pravice skrbnika naprave (lahko '
            'zaklene zaslon, izbriše podatke, onemogoči kamero ...). To je '
            'pogost vzorec pri stalkerware aplikacijah.',
        'Preveri v Nastavitve > Varnost > Skrbniki naprave in odstrani, če je ne prepoznaš.',
      ));
    } else if (isActiveDeviceAdmin && app.isSideloaded) {
      add(build(
        'device_admin',
        RiskSeverity.medium,
        'Ima pravice skrbnika naprave',
        'Sideloadana aplikacija s pravicami skrbnika naprave - preveri, da je prepoznaš.',
      ));
    }

    // --- Skrita ikona (splošno) ---
    if (!app.hasLauncherIcon && !app.isPreinstalled && !isActiveDeviceAdmin && !hasAccessibility) {
      add(build(
        'hidden_icon',
        RiskSeverity.medium,
        'Aplikacija brez ikone v meniju aplikacij',
        'Aplikacija se namerno skriva pred normalno navigacijo po napravi. '
            'Nekatere legitimne pomožne komponente to počnejo, a je vredno preveriti.',
      ));
    }

    // --- Sideload + veliko občutljivih dovoljenj ---
    if (app.isSideloaded && sensitiveGranted.length >= 3) {
      add(build(
        'sideload_sensitive_bundle',
        RiskSeverity.high,
        'Sideload aplikacija s širokim dostopom do zasebnih podatkov',
        'Nameščena mimo Google Play in ima odobrena dovoljenja: '
            '${sensitiveGranted.join(', ')}.',
      ));
    }

    // --- Skrita + nikoli odprta s strani uporabnika + občutljiva dovoljenja ---
    if (!app.hasLauncherIcon &&
        !app.isPreinstalled &&
        neverUsedByUser &&
        sensitiveGranted.isNotEmpty) {
      add(build(
        'hidden_no_interaction',
        RiskSeverity.high,
        'Skrita aplikacija brez kakršnekoli uporabniške interakcije',
        'Uporabnik je nikoli ni odprl neposredno, nima ikone, ima pa dostop do: '
            '${sensitiveGranted.join(', ')}. Deluje torej izključno v ozadju.',
      ));
    }

    // --- Sledilni profil: samodejni zagon + izjema od varčevanja + lokacija ---
    final requestsBoot = app.requestedPermissions.contains('android.permission.RECEIVE_BOOT_COMPLETED');
    final hasLocation = app.hasAnyPermission(const [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_BACKGROUND_LOCATION',
    ]);
    if (app.isSideloaded && app.isIgnoringBatteryOptimizations && requestsBoot && hasLocation) {
      add(build(
        'tracker_profile',
        RiskSeverity.high,
        'Profil, značilen za sledilne aplikacije',
        'Aplikacija se zažene ob vklopu naprave, je izvzeta iz varčevanja '
            'baterije (deluje neprekinjeno v ozadju) in ima dostop do lokacije.',
      ));
    }

    // --- Overlay / SMS prestrezanje ---
    if (app.isSideloaded &&
        app.hasAnyPermission(const ['android.permission.SYSTEM_ALERT_WINDOW'])) {
      add(build(
        'overlay_permission',
        RiskSeverity.medium,
        'Lahko riše čez druge aplikacije ("overlay")',
        'To dovoljenje omogoča prikaz vsebine nad drugimi aplikacijami - '
            'uporablja se tudi za phishing prekrivke ali skrivanje dejavnosti.',
      ));
    }
    if (app.isSideloaded &&
        !app.hasLauncherIcon &&
        app.hasAnyPermission(const [
          'android.permission.READ_SMS',
          'android.permission.RECEIVE_SMS',
        ])) {
      add(build(
        'sms_interception',
        RiskSeverity.high,
        'Skrita aplikacija z dostopom do SMS sporočil',
        'Lahko bere prejeta SMS sporočila, vključno z enkratnimi (2FA) kodami.',
      ));
    }

    // --- Morebitna ponaredba znane blagovne znamke ---
    final lowerLabel = app.appLabel.toLowerCase();
    final lowerPkg = app.packageName.toLowerCase();
    final mimicsKnownBrand = kKnownBrandKeywords.any(
      (kw) => (lowerLabel.contains(kw) || lowerPkg.contains(kw)),
    );
    if (mimicsKnownBrand && app.isSideloaded) {
      add(build(
        'brand_mimic',
        RiskSeverity.medium,
        'Ime spominja na znano aplikacijo, a ni iz Google Play',
        'Ime ali paket ("${app.packageName}") spominja na uveljavljeno '
            'aplikacijo, nameščena pa je bila mimo Google Play. Preveri '
            'pristnost, preden ji zaupaš prijavne podatke.',
      ));
    }

    // --- Nenehno aktivna + izvzeta iz varčevanja + skrita ---
    // isAppInactive != true zajame tako "sistem jo ocenjuje kot aktivno" kot
    // "ni podatka" (brez Usage access privzeto raje preveč kot premalo opozori).
    if (!app.hasLauncherIcon &&
        !app.isPreinstalled &&
        app.isIgnoringBatteryOptimizations &&
        app.isAppInactive != true) {
      add(build(
        'hidden_always_active',
        RiskSeverity.critical,
        'Skrita aplikacija se nenehno izvaja v ozadju',
        'Android je ne ocenjuje kot neaktivno in '
            'je izvzeta iz varčevanja z baterijo, hkrati pa nima ikone v meniju - '
            'to je pogosto vzrok tako za skrito delovanje kot za pospešeno '
            'praznjenje baterije.',
      ));
    }

    return findings;
  }
}
