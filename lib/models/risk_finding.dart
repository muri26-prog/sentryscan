enum RiskSeverity { info, low, medium, high, critical }

extension RiskSeverityX on RiskSeverity {
  int get weight {
    switch (this) {
      case RiskSeverity.info:
        return 0;
      case RiskSeverity.low:
        return 5;
      case RiskSeverity.medium:
        return 15;
      case RiskSeverity.high:
        return 30;
      case RiskSeverity.critical:
        return 50;
    }
  }

  String get label {
    switch (this) {
      case RiskSeverity.info:
        return 'Informativno';
      case RiskSeverity.low:
        return 'Nizko tveganje';
      case RiskSeverity.medium:
        return 'Srednje tveganje';
      case RiskSeverity.high:
        return 'Visoko tveganje';
      case RiskSeverity.critical:
        return 'Kritično';
    }
  }
}

/// En posamezen ugotovljen indikator tveganja - lahko je vezan na
/// konkretno aplikacijo (`relatedPackageName`) ali na splošno stanje
/// naprave (npr. root, ADB).
class RiskFinding {
  final String id;
  final RiskSeverity severity;
  final String title;
  final String description;
  final String? relatedPackageName;
  final String? relatedAppLabel;
  final String? recommendation;

  const RiskFinding({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    this.relatedPackageName,
    this.relatedAppLabel,
    this.recommendation,
  });
}
