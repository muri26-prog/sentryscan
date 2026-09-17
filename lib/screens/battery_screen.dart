import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/battery_insight.dart';
import '../models/battery_sample.dart';
import '../services/battery_analysis_service.dart';
import '../services/native_bridge.dart';
import '../services/permission_gate_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/section_card.dart';

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  static const _analysisWindow = Duration(days: 14);

  bool _loading = true;
  bool _samplingEnabled = false;
  List<BatterySample> _history = const [];
  BatteryAnalysisResult? _result;
  final _permissionGate = const PermissionGateService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final samplingEnabled = await StorageService.instance.isBatterySamplingEnabled();
    final since = DateTime.now().subtract(_analysisWindow);
    final history = await NativeBridge.instance.readBatteryHistory(since: since);
    final apps = await NativeBridge.instance.getInstalledApps();
    final usage = await NativeBridge.instance.getUsageStats(days: 7);

    // Ujemi tudi trenutni trenutek, da graf in izračun nista videti "zastarela".
    final current = await NativeBridge.instance.captureBatterySampleNow();
    final combined = [...history, current];

    final result = const BatteryAnalysisService().analyze(
      history: combined,
      usageForegroundMsByPackage: usage,
      apps: apps,
    );

    if (!mounted) return;
    setState(() {
      _samplingEnabled = samplingEnabled;
      _history = combined;
      _result = result;
      _loading = false;
    });
  }

  Future<void> _toggleSampling(bool enabled) async {
    setState(() => _samplingEnabled = enabled);
    await StorageService.instance.setBatterySamplingEnabled(enabled);
    if (enabled) {
      await NativeBridge.instance.scheduleBatterySampling();
      await _permissionGate.requestIgnoreBatteryOptimizationsForSelf();
    } else {
      await NativeBridge.instance.cancelBatterySampling();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analiza baterije'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'Spremljanje v ozadju',
                    subtitle: 'Zbira en vzorec vsakih ~15 minut, lokalno na napravi',
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _samplingEnabled,
                      title: const Text('Vklopljeno'),
                      subtitle: const Text(
                        'Priporočeno: pusti vklopljeno vsaj 24-48h za zanesljivo analizo.',
                      ),
                      onChanged: _toggleSampling,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryCard(context),
                  const SizedBox(height: 8),
                  if (_history.length >= 2) _buildChartCard(context),
                  const SizedBox(height: 8),
                  if (_result != null && _result!.insights.isNotEmpty)
                    SectionCard(
                      title: 'Ugotovitve',
                      child: Column(
                        children: [
                          for (final insight in _result!.insights) _buildInsightTile(context, insight),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final drain = _result?.averageDrainPercentPerHour;
    return SectionCard(
      title: drain == null ? 'Hitrost praznjenja: ni dovolj podatkov' : 'Povprečna hitrost praznjenja',
      subtitle: '${_result?.sampleCount ?? 0} vzorcev zbranih',
      child: drain == null
          ? const Text('Vklopi spremljanje in počakaj nekaj ur.')
          : Text(
              '${drain.toStringAsFixed(1)} %/uro',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
    );
  }

  Widget _buildChartCard(BuildContext context) {
    final sorted = [..._history]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final firstMs = sorted.first.timestamp.millisecondsSinceEpoch.toDouble();
    final spots = sorted
        .map((s) => FlSpot(
              (s.timestamp.millisecondsSinceEpoch - firstMs) / (1000 * 60 * 60),
              s.levelPercent.toDouble(),
            ))
        .toList();

    return SectionCard(
      title: 'Nivo baterije skozi čas',
      subtitle: 'Vodoravna os: ure od začetka zbranih podatkov',
      child: SizedBox(
        height: 220,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 100,
            gridData: const FlGridData(show: true),
            titlesData: const FlTitlesData(
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: Theme.of(context).colorScheme.primary,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightTile(BuildContext context, BatteryInsight insight) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.circle, size: 12, color: colorForSeverity(context, insight.severity)),
      title: Text(insight.title),
      subtitle: Text(insight.description),
      isThreeLine: true,
    );
  }
}
