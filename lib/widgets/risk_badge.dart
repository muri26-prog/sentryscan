import 'package:flutter/material.dart';

import '../models/risk_finding.dart';
import '../theme.dart';

class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.severity});

  final RiskSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = colorForSeverity(context, severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        severity.label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
