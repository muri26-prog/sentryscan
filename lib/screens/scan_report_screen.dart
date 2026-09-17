import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../models/risk_finding.dart';
import '../models/scan_report.dart';
import '../services/scan_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/risk_badge.dart';
import '../widgets/section_card.dart';
import 'app_detail_screen.dart';

class ScanReportScreen extends StatefulWidget {
  const ScanReportScreen({super.key, required this.scanService, required this.report});

  final ScanService scanService;
  final ScanReport report;

  @override
  State<ScanReportScreen> createState() => _ScanReportScreenState();
}

class _ScanReportScreenState extends State<ScanReportScreen> {
  late ScanReport _report = widget.report;
  bool _checkingVt = false;
  String _vtStage = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severity = _severityForScore(_report.riskScore);
    final color = colorForSeverity(context, severity);

    final grouped = <RiskSeverity, List<RiskFinding>>{};
    for (final f in _report.findings) {
      grouped.putIfAbsent(f.severity, () => []).add(f);
    }
    const order = [
      RiskSeverity.critical,
      RiskSeverity.high,
      RiskSeverity.medium,
      RiskSeverity.low,
      RiskSeverity.info,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Rezultat pregleda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: _report.riskLevelLabel,
            subtitle: '${_report.apps.length} nameščenih aplikacij pregledanih',
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    '${_report.riskScore}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _report.findings.isEmpty
                        ? 'Ni bilo zaznanih indikatorjev tveganja pri tem pregledu.'
                        : '${_report.findings.length} najdb skupaj.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildVirusTotalCard(context),
          const SizedBox(height: 8),
          if (_report.findings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Vse čisto. 🎉')),
            )
          else
            for (final sev in order)
              if (grouped[sev]?.isNotEmpty ?? false) _buildSeverityGroup(context, sev, grouped[sev]!),
        ],
      ),
    );
  }

  Widget _buildVirusTotalCard(BuildContext context) {
    final suggested = widget.scanService.suggestedAppsForVirusTotal(_report);
    return SectionCard(
      title: 'VirusTotal preverjanje',
      subtitle: suggested.isEmpty
          ? 'Ni aplikacij, ki bi jih lokalna analiza označila kot vredne dodatnega preverjanja'
          : '${suggested.length} označenih aplikacij je mogoče preveriti proti bazi znanih groženj',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_checkingVt) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_vtStage, style: Theme.of(context).textTheme.bodySmall),
          ] else if (suggested.isNotEmpty)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.cloud_sync_outlined),
              label: Text('Preveri ${suggested.length} aplikacij na VirusTotal'),
              onPressed: () => _runVtCheck(suggested),
            ),
        ],
      ),
    );
  }

  Future<void> _runVtCheck(List<AppInfo> suggested) async {
    final enabled = await StorageService.instance.vtLookupsEnabled();
    final apiKey = await StorageService.instance.getVtApiKey();
    if (!enabled || apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Najprej v Nastavitvah vklopi VirusTotal preverjanje in vnesi svoj API ključ.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _checkingVt = true;
      _vtStage = 'Pripravljam ...';
    });

    try {
      final updated = await widget.scanService.checkAppsWithVirusTotal(
        _report,
        suggested,
        apiKey,
        onProgress: (done, total, label) {
          if (mounted) {
            setState(() => _vtStage = 'Preverjam $label ($done/$total) - javni VT '
                'API dovoljuje le nekaj zahtevkov na minuto, zato je to lahko počasno.');
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _report = updated;
        _checkingVt = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingVt = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Napaka pri VirusTotal preverjanju: $e')),
      );
    }
  }

  Widget _buildSeverityGroup(BuildContext context, RiskSeverity sev, List<RiskFinding> findings) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: RiskBadge(severity: sev),
            ),
            for (final f in findings) _buildFindingTile(context, f),
          ],
        ),
      ),
    );
  }

  Widget _buildFindingTile(BuildContext context, RiskFinding f) {
    return ListTile(
      title: Text(f.title),
      subtitle: Text(f.description),
      isThreeLine: f.description.length > 60,
      trailing: f.relatedPackageName != null ? const Icon(Icons.chevron_right) : null,
      onTap: f.relatedPackageName == null
          ? null
          : () {
              final app = _report.apps.where((a) => a.packageName == f.relatedPackageName);
              if (app.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AppDetailScreen(
                    app: app.first,
                    system: _report.systemSnapshot,
                    findings: _report.findings
                        .where((x) => x.relatedPackageName == f.relatedPackageName)
                        .toList(),
                  ),
                ),
              );
            },
    );
  }

  RiskSeverity _severityForScore(int score) {
    if (score >= 60) return RiskSeverity.critical;
    if (score >= 30) return RiskSeverity.high;
    if (score >= 10) return RiskSeverity.medium;
    if (score > 0) return RiskSeverity.low;
    return RiskSeverity.info;
  }
}
