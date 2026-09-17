class BatterySample {
  final DateTime timestamp;
  final int levelPercent;
  final bool isCharging;
  final String pluggedType;
  final String health;
  final double? temperatureC;
  final int? voltageMv;
  final String? technology;
  final int? currentNowMicroAmps;
  final int? chargeCounterMicroAh;

  const BatterySample({
    required this.timestamp,
    required this.levelPercent,
    required this.isCharging,
    required this.pluggedType,
    required this.health,
    this.temperatureC,
    this.voltageMv,
    this.technology,
    this.currentNowMicroAmps,
    this.chargeCounterMicroAh,
  });

  factory BatterySample.fromMap(Map<dynamic, dynamic> map) {
    return BatterySample(
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestampMs'] as num?)?.toInt() ?? 0),
      levelPercent: (map['levelPercent'] as num?)?.toInt() ?? -1,
      isCharging: (map['isCharging'] as bool?) ?? false,
      pluggedType: (map['pluggedType'] as String?) ?? 'NONE',
      health: (map['health'] as String?) ?? 'UNKNOWN',
      temperatureC: (map['temperatureC'] as num?)?.toDouble(),
      voltageMv: (map['voltageMv'] as num?)?.toInt(),
      technology: map['technology'] as String?,
      currentNowMicroAmps: (map['currentNowMicroAmps'] as num?)?.toInt(),
      chargeCounterMicroAh: (map['chargeCounterMicroAh'] as num?)?.toInt(),
    );
  }
}
