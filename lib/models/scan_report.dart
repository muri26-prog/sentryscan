import 'app_info.dart';
import 'risk_finding.dart';
import 'system_security_snapshot.dart';

/// Celoten rezultat enega pregleda: seznam aplikacij, sistemski posnetek in
/// vse ugotovitve, ki jih je izračunal `HeuristicsEngine`.
class ScanReport {
  final DateTime generatedAt;
  final List<AppInfo> apps;
  final SystemSecuritySnapshot systemSnapshot;
  final List<RiskFinding> findings;

  const ScanReport({
    required this.generatedAt,
    required this.apps,
    required this.systemSnapshot,
    required this.findings,
  });

  List<RiskFinding> get criticalFindings =>
      findings.where((f) => f.severity == RiskSeverity.critical).toList();

  List<RiskFinding> get highFindings =>
      findings.where((f) => f.severity == RiskSeverity.high).toList();

  /// Skupna ocena tveganja naprave, 0 (brez zaznanih tveganj) do 100
  /// (kritično). Ni "verjetnost okužbe" v statističnem smislu, temveč
  /// utežena vsota resnosti najdb - namenjena razvrščanju/prednostenju, ne
  /// natančni napovedi.
  int get riskScore {
    final total = findings.fold<int>(0, (sum, f) => sum + f.severity.weight);
    return total.clamp(0, 100);
  }

  String get riskLevelLabel {
    final score = riskScore;
    if (score >= 60) return 'Kritično tveganje';
    if (score >= 30) return 'Visoko tveganje';
    if (score >= 10) return 'Zmerno tveganje';
    if (score > 0) return 'Nizko tveganje';
    return 'Ni zaznanih tveganj';
  }
}
