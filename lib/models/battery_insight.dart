import 'risk_finding.dart';

/// Ena ugotovitev iz analize praznjenja baterije. Uporablja isto lestvico
/// resnosti kot varnostne najdbe (za dosleden videz v UI), a tu "resnost"
/// pomeni "kako verjeten/pomemben vzrok za praznjenje", ne varnostno grožnjo.
class BatteryInsight {
  final String id;
  final RiskSeverity severity;
  final String title;
  final String description;
  final String? relatedPackageName;
  final String? relatedAppLabel;

  const BatteryInsight({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    this.relatedPackageName,
    this.relatedAppLabel,
  });
}

class BatteryAnalysisResult {
  /// Povprečna hitrost praznjenja v %/uro, izračunana iz obdobij, ko
  /// naprava NI bila priklopljena na polnilec. `null`, če premalo podatkov
  /// (npr. prvi zagon, ali naprava večino časa na polnilcu).
  final double? averageDrainPercentPerHour;

  final int sampleCount;
  final DateTime? oldestSampleAt;
  final List<BatteryInsight> insights;

  /// Aplikacije z največ časom v ospredju v analiziranem obdobju (posreden
  /// kazalnik prispevka k porabi - Android tretjim osebam ne razkriva
  /// dejanske porabe baterije po aplikaciji, glej opombo v NativeScanner).
  final List<MapEntry<String, Duration>> topForegroundApps;

  const BatteryAnalysisResult({
    required this.averageDrainPercentPerHour,
    required this.sampleCount,
    required this.oldestSampleAt,
    required this.insights,
    required this.topForegroundApps,
  });
}
