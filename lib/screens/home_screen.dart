import 'package:flutter/material.dart';

import '../models/risk_finding.dart';
import '../services/scan_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/section_card.dart';
import 'battery_screen.dart';
import 'permissions_setup_screen.dart';
import 'scan_report_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.scanService});

  final ScanService scanService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, Object?>> _history = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final rows = await StorageService.instance.getScanHistory(limit: 5);
    if (!mounted) return;
    setState(() {
      _history = rows;
      _loadingHistory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastScan = _history.isNotEmpty ? _history.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SentryScan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Nastavitve',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Stanje naprave',
            subtitle: lastScan == null
                ? 'Še ni bil izveden noben pregled'
                : 'Zadnji pregled: ${_formatTimestamp(lastScan['generatedAt'] as int)} - dotakni se za podrobnosti',
            onTap: lastScan == null ? null : () => _openLastReportDetails(context),
            child: _loadingHistory
                ? const LinearProgressIndicator()
                : _buildLastScoreSummary(context, lastScan),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Varnostni pregled',
            subtitle: 'Aplikacije, dovoljenja, root/ADB/šifriranje, VirusTotal',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Preveri nameščene aplikacije, sistemske nastavitve in sledi '
                  'morebitne vohunske/nadzorne programske opreme.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.security),
                  label: const Text('Zaženi pregled'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScanScreen(scanService: widget.scanService),
                    ),
                  ).then((_) => _loadHistory()),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Poraba baterije',
            subtitle: 'Hitrost praznjenja in verjetni vzroki',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Analiziraj zgodovino baterije in poveži padce z aplikacijami, '
                  'ki se največ izvajajo v ozadju.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.battery_alert_outlined),
                  label: const Text('Analiza baterije'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BatteryScreen()),
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Dovoljenja za polno delovanje',
            subtitle: 'Usage access, obvestila, izjema od varčevanja baterije',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.checklist_outlined),
                label: const Text('Preveri dovoljenja'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PermissionsSetupScreen()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLastReportDetails(BuildContext context) {
    final report = widget.scanService.lastReport;
    if (report == null) {
      // Trajno se shranjuje le povzetek (števci), poln seznam najdb pa živi
      // samo v pomnilniku med tekočo sejo aplikacije - po ponovnem zagonu
      // aplikacije ga ni več na voljo brez novega pregleda.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Podrobnosti zadnjega pregleda niso več na voljo (aplikacija je bila '
            'medtem znova zagnana) - zaženi nov pregled.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanReportScreen(scanService: widget.scanService, report: report),
      ),
    );
  }

  Widget _buildLastScoreSummary(BuildContext context, Map<String, Object?>? lastScan) {
    if (lastScan == null) {
      return const Text('Zaženi prvi pregled, da vidiš oceno tveganja naprave.');
    }
    final score = lastScan['riskScore'] as int;
    final critical = lastScan['criticalCount'] as int;
    final high = lastScan['highCount'] as int;
    final severity = score >= 60
        ? RiskSeverity.critical
        : score >= 30
            ? RiskSeverity.high
            : score >= 10
                ? RiskSeverity.medium
                : score > 0
                    ? RiskSeverity.low
                    : RiskSeverity.info;
    final color = colorForSeverity(context, severity);

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ocena tveganja: $score/100', style: Theme.of(context).textTheme.titleMedium),
              Text('$critical kritičnih, $high visokih najdb'),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
