import '../models/app_info.dart';
import '../models/scan_report.dart';
import '../models/vt_verdict.dart';
import 'heuristics_engine.dart';
import 'native_bridge.dart';
import 'storage_service.dart';
import 'virustotal_service.dart';

typedef ScanProgressCallback = void Function(String stage);

/// Orkestrira celoten pregled: pobere surove podatke prek `NativeBridge`,
/// jih oceni z `HeuristicsEngine` in po potrebi obogati z VirusTotal
/// rezultati. To je edini razred, ki ga zasloni potrebujejo za sprožitev
/// pregleda - ne kličejo native mostu ali heuristike neposredno.
class ScanService {
  ScanService({
    NativeBridge? bridge,
    HeuristicsEngine? engine,
    VirusTotalService? vt,
    StorageService? storage,
  })  : _bridge = bridge ?? NativeBridge.instance,
        _engine = engine ?? const HeuristicsEngine(),
        _vt = vt ?? VirusTotalService(),
        _storage = storage ?? StorageService.instance;

  final NativeBridge _bridge;
  final HeuristicsEngine _engine;
  final VirusTotalService _vt;
  final StorageService _storage;

  Map<String, int> _lastUsageStats = {};
  final Map<String, VtVerdict> _vtVerdictsByPackage = {};
  ScanReport? _lastReport;

  Map<String, int> get lastUsageStats => _lastUsageStats;

  /// Poln rezultat zadnjega pregleda v TEJ seji aplikacije (v pomnilniku, ne
  /// na disku) - uporabljen za "podrobnosti zadnjega pregleda" na domačem
  /// zaslonu, brez ponovnega poganjanja pregleda. `null`, dokler v tej seji
  /// še ni bil izveden noben pregled (npr. po ponovnem zagonu aplikacije).
  ScanReport? get lastReport => _lastReport;

  /// Izvede hiter, popolnoma lokalen pregled (brez omrežja). Traja od nekaj
  /// sekund do ~1 minute, odvisno od števila nameščenih aplikacij.
  Future<ScanReport> runScan({ScanProgressCallback? onProgress}) async {
    onProgress?.call('Berem seznam nameščenih aplikacij ...');
    final rawApps = await _bridge.getInstalledApps();
    // Deduplicira po packageName (glej isto opombo v HeuristicsEngine) - tu
    // je edino mesto, kjer se seznam aplikacij za pregled dejansko sestavi.
    final apps = {for (final a in rawApps) a.packageName: a}.values.toList(growable: false);

    onProgress?.call('Berem sistemske varnostne nastavitve ...');
    final system = await _bridge.getSystemSecuritySnapshot();

    var usage = <String, int>{};
    if (system.usageAccessGranted) {
      onProgress?.call('Berem statistiko uporabe aplikacij ...');
      usage = await _bridge.getUsageStats(days: 7);
    }
    _lastUsageStats = usage;

    onProgress?.call('Ocenjujem tveganja ...');
    final findings = _engine.evaluate(
      apps: apps,
      system: system,
      usageForegroundMsByPackage: usage,
      vtVerdictsByPackage: Map.of(_vtVerdictsByPackage),
    );

    final report = ScanReport(
      generatedAt: DateTime.now(),
      apps: apps,
      systemSnapshot: system,
      findings: findings,
    );

    await _storage.recordScanSummary(
      generatedAt: report.generatedAt,
      riskScore: report.riskScore,
      findingsCount: findings.length,
      criticalCount: report.criticalFindings.length,
      highCount: report.highFindings.length,
    );

    _lastReport = report;
    return report;
  }

  /// Seznam paketov, ki jih je vredno preveriti na VirusTotal: tiste, ki so
  /// že dobile vsaj eno najdbo srednje resnosti ali več pri lokalni
  /// heuristiki. Ker ima javni VT API zelo strogo omejitev hitrosti, NI
  /// smiselno (in bi bilo prepočasi) preverjati vseh nameščenih aplikacij.
  List<AppInfo> suggestedAppsForVirusTotal(ScanReport report) {
    final flaggedPackages = report.findings
        .where((f) => f.relatedPackageName != null)
        .map((f) => f.relatedPackageName!)
        .toSet();
    return report.apps.where((a) => flaggedPackages.contains(a.packageName)).toList();
  }

  /// Izračuna APK hash in poizve VirusTotal za podan podmnožico aplikacij,
  /// nato vrne NOVO `ScanReport` s ponovno izračunanimi najdbami (VT
  /// rezultati lahko obstoječo najdbo nadgradijo, npr. iz "medium" v
  /// "critical"). Zaporedno, s prisilnim zamikom med zahtevki (glej
  /// `VirusTotalService`) - za ~10 aplikacij lahko traja nekaj minut.
  Future<ScanReport> checkAppsWithVirusTotal(
    ScanReport previous,
    List<AppInfo> appsToCheck,
    String apiKey, {
    VtProgressCallback? onProgress,
  }) async {
    final hashByPackage = <String, String>{};
    for (final app in appsToCheck) {
      final hash = await _bridge.computeApkSha256(app.packageName);
      if (hash != null) hashByPackage[app.packageName] = hash;
    }

    final results = await _vt.checkMany(hashByPackage, apiKey, onProgress: onProgress);
    _vtVerdictsByPackage.addAll(results);

    final findings = _engine.evaluate(
      apps: previous.apps,
      system: previous.systemSnapshot,
      usageForegroundMsByPackage: _lastUsageStats,
      vtVerdictsByPackage: Map.of(_vtVerdictsByPackage),
    );

    final updated = ScanReport(
      generatedAt: previous.generatedAt,
      apps: previous.apps,
      systemSnapshot: previous.systemSnapshot,
      findings: findings,
    );
    _lastReport = updated;
    return updated;
  }

  void dispose() => _vt.dispose();
}
