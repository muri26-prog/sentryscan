import 'package:flutter/material.dart';

import 'models/risk_finding.dart';

const _seedColor = Color(0xFF1B5E20);

ThemeData buildSentryScanTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

Color colorForSeverity(BuildContext context, RiskSeverity severity) {
  switch (severity) {
    case RiskSeverity.critical:
      return const Color(0xFFB3261E);
    case RiskSeverity.high:
      return const Color(0xFFE65100);
    case RiskSeverity.medium:
      return const Color(0xFFF9A825);
    case RiskSeverity.low:
      return const Color(0xFF2E7D32);
    case RiskSeverity.info:
      return Theme.of(context).colorScheme.primary;
  }
}
