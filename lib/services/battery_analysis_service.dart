import '../models/app_info.dart';
import '../models/battery_insight.dart';
import '../models/battery_sample.dart';
import '../models/risk_finding.dart';

/// Analizira lokalno zbrano zgodovino baterije (glej `BatterySamplerWorker`
/// na Android strani) in jo poveže s podatki o aplikacijah, da poda
/// razumljive vzroke za (hitro) praznjenje.
///
/// POMEMBNA OMEJITEV (glej tudi komentar v NativeScanner.kt): Android
/// tretjim osebam ne razkriva dejanske porabe baterije PO APLIKACIJI (ta
/// podatek je za sistemske/privilegirane aplikacije, dostopen le prek
/// `adb shell dumpsys batterystats` ali na rootani napravi). Zato ta
/// analiza uporablja NAJBOLJŠE RAZPOLOŽLJIVE POSREDNE kazalnike:
///  - dejanski upad odstotka baterije skozi čas (natančen, meritev OS-a),
///  - skupni čas posamezne aplikacije v ospredju (UsageStats),
///  - ali je aplikacija izvzeta iz varčevanja z baterijo + kako "aktivna"
///    jo ocenjuje sam Android (standby bucket).
/// Rezultat je zato "najverjetnejši osumljenci", ne matematično dokazana
/// odgovornost posamezne aplikacije.
class BatteryAnalysisService {
  const BatteryAnalysisService();

  BatteryAnalysisResult analyze({
    required List<BatterySample> history,
    required Map<String, int> usageForegroundMsByPackage,
    required List<AppInfo> apps,
  }) {
    if (history.isEmpty) {
      return const BatteryAnalysisResult(
        averageDrainPercentPerHour: null,
        sampleCount: 0,
        oldestSampleAt: null,
        insights: [
          BatteryInsight(
            id: 'battery.no_data',
            severity: RiskSeverity.info,
            title: 'Še ni dovolj podatkov o bateriji',
            description: 'Vklopi spremljanje baterije v Nastavitvah in počakaj vsaj '
                'nekaj ur (idealno 24+), da SentryScan zbere dovolj vzorcev za '
                'zanesljivo analizo praznjenja.',
          ),
        ],
        topForegroundApps: [],
      );
    }

    final sorted = [...history]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final drainRate = _computeAverageDrainRate(sorted);

    final insights = <BatteryInsight>[];

    if (sorted.length < 5 ||
        sorted.last.timestamp.difference(sorted.first.timestamp) < const Duration(hours: 3)) {
      insights.add(const BatteryInsight(
        id: 'battery.short_history',
        severity: RiskSeverity.info,
        title: 'Zgodovina je še kratka',
        description: 'Za bolj zanesljivo oceno hitrosti praznjenja pusti spremljanje '
            'vklopljeno vsaj 24 ur.',
      ));
    }

    if (drainRate != null) {
      if (drainRate >= 15) {
        insights.add(BatteryInsight(
          id: 'battery.very_fast_drain',
          severity: RiskSeverity.high,
          title: 'Zelo hitro praznjenje: ${drainRate.toStringAsFixed(1)} %/uro',
          description: 'Pri tej hitrosti bi se polna baterija izpraznila v približno '
              '${(100 / drainRate).toStringAsFixed(1)} urah neprekinjene uporabe/mirovanja.',
        ));
      } else if (drainRate >= 8) {
        insights.add(BatteryInsight(
          id: 'battery.fast_drain',
          severity: RiskSeverity.medium,
          title: 'Pospešeno praznjenje: ${drainRate.toStringAsFixed(1)} %/uro',
          description: 'To je nad tipičnim mirovanjem (običajno 1-3 %/uro pri '
              'zaklenjenem zaslonu), kar nakazuje na aktivno porabo v ozadju.',
        ));
      }
    }

    final latest = sorted.last;
    if (latest.temperatureC != null && latest.temperatureC! >= 40) {
      insights.add(BatteryInsight(
        id: 'battery.high_temperature',
        severity: RiskSeverity.medium,
        title: 'Povišana temperatura baterije (${latest.temperatureC!.toStringAsFixed(1)} °C)',
        description: 'Visoka temperatura pospešuje staranje baterije in je pogosto '
            'znak intenzivnega procesorja/GPU dela v ozadju (npr. rudarjenje '
            'kriptovalut, video v ozadju, prekomerno sledenje lokaciji).',
      ));
    }

    if (latest.health != 'GOOD' && latest.health != 'UNKNOWN') {
      insights.add(BatteryInsight(
        id: 'battery.health',
        severity: RiskSeverity.low,
        title: 'Stanje baterije: ${_healthLabel(latest.health)}',
        description: 'Sistem poroča o odstopanju od normalnega stanja baterije. To '
            'lahko samo po sebi pojasni hitrejše praznjenje in ni nujno povezano '
            'z nobeno aplikacijo.',
      ));
    }

    // Top aplikacije po času v ospredju - poveži z oznakami iz seznama aplikacij.
    final labelByPackage = {for (final a in apps) a.packageName: a.appLabel};
    final sortedUsage = usageForegroundMsByPackage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topForegroundApps = sortedUsage
        .take(8)
        .map((e) => MapEntry(e.key, Duration(milliseconds: e.value)))
        .toList();

    if (topForegroundApps.isNotEmpty) {
      final top = topForegroundApps.first;
      final label = labelByPackage[top.key] ?? top.key;
      insights.add(BatteryInsight(
        id: 'battery.top_foreground_app',
        severity: RiskSeverity.info,
        title: 'Največ časa v ospredju: $label',
        description: '${_formatDuration(top.value)} v izbranem obdobju. To je '
            'najmočnejši posredni kazalnik porabe, ki je na voljo brez root dostopa.',
        relatedPackageName: top.key,
        relatedAppLabel: label,
      ));
    }

    // Aplikacije, ki tečejo brez omejitev IN jih Android ocenjuje kot stalno aktivne.
    for (final app in apps) {
      final isAlwaysActive = app.standbyBucket != null && app.standbyBucket! <= 20;
      if (app.isIgnoringBatteryOptimizations && isAlwaysActive && !app.isSystemApp) {
        insights.add(BatteryInsight(
          id: 'battery.unrestricted.${app.packageName}',
          severity: RiskSeverity.medium,
          title: '${app.appLabel} deluje brez omejitev v ozadju',
          description: 'Izvzeta je iz varčevanja z baterijo in jo Android ocenjuje kot '
              'stalno aktivno (${app.standbyBucketLabel}). Če je ne uporabljaš pogosto, '
              'razmisli o odstranitvi izjeme v Nastavitve > Baterija.',
          relatedPackageName: app.packageName,
          relatedAppLabel: app.appLabel,
        ));
      }
    }

    return BatteryAnalysisResult(
      averageDrainPercentPerHour: drainRate,
      sampleCount: sorted.length,
      oldestSampleAt: sorted.first.timestamp,
      insights: insights,
      topForegroundApps: topForegroundApps,
    );
  }

  /// Izračuna povprečno hitrost praznjenja (%/uro) tako, da sešteje upad
  /// odstotka in trajanje po vseh strnjenih obdobjih, ko naprava NI bila
  /// na polnilcu (izognemo se popačenju zaradi polnjenja).
  double? _computeAverageDrainRate(List<BatterySample> sorted) {
    double totalPercentDrained = 0;
    double totalHours = 0;

    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      if (prev.isCharging || curr.isCharging) continue;
      if (curr.levelPercent < 0 || prev.levelPercent < 0) continue;

      final hours = curr.timestamp.difference(prev.timestamp).inSeconds / 3600.0;
      if (hours <= 0 || hours > 6) continue; // preskoči prevelike vrzeli (npr. telefon ugasnjen)

      final drop = prev.levelPercent - curr.levelPercent;
      if (drop <= 0) continue; // ignoriraj šum/rahla nihanja navzgor

      totalPercentDrained += drop;
      totalHours += hours;
    }

    if (totalHours < 0.5) return null; // premalo veljavnih podatkov
    return totalPercentDrained / totalHours;
  }

  String _healthLabel(String raw) {
    switch (raw) {
      case 'OVERHEAT':
        return 'pregrevanje';
      case 'DEAD':
        return 'izrabljena';
      case 'OVER_VOLTAGE':
        return 'previsoka napetost';
      case 'UNSPECIFIED_FAILURE':
        return 'nedoločena okvara';
      case 'COLD':
        return 'prehladna';
      default:
        return raw;
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '$hours h $minutes min';
    return '$minutes min';
  }
}
