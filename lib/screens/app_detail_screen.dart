import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_info.dart';
import '../models/risk_finding.dart';
import '../models/system_security_snapshot.dart';
import '../services/native_bridge.dart';
import '../services/permission_gate_service.dart';
import '../widgets/risk_badge.dart';
import '../widgets/section_card.dart';

class AppDetailScreen extends StatelessWidget {
  const AppDetailScreen({
    super.key,
    required this.app,
    required this.system,
    required this.findings,
  });

  final AppInfo app;
  final SystemSecuritySnapshot system;
  final List<RiskFinding> findings;
  final _permissionGate = const PermissionGateService();

  static final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final hasAccessibility = system.hasEnabledAccessibilityService(app.packageName);
    final hasNotificationAccess = system.hasEnabledNotificationListener(app.packageName);
    final isDeviceAdmin = system.hasActiveDeviceAdmin(app.packageName);

    return Scaffold(
      appBar: AppBar(title: Text(app.appLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: app.appLabel,
            subtitle: app.packageName,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Različica', '${app.versionName ?? '?'} (${app.versionCode})'),
                _row('Nameščena', _dateFormat.format(app.firstInstallTime)),
                _row('Zadnjič posodobljena', _dateFormat.format(app.lastUpdateTime)),
                _row('Vir namestitve', app.installerPackageName ?? 'Neznan / sideload'),
                _row('Sistemska aplikacija', app.isSystemApp ? 'Da' : 'Ne'),
                _row('Ikona v meniju', app.hasLauncherIcon ? 'Da' : 'Ne (skrita)'),
                _row('Velikost APK', _formatBytes(app.apkSizeBytes)),
                _row('SHA-256 podpisnega certifikata', app.signingCertSha256 ?? 'Ni na voljo'),
                _row('Standby stanje (Android)', app.standbyBucketLabel),
                _row(
                  'Izjema od varčevanja baterije',
                  app.isIgnoringBatteryOptimizations ? 'Da' : 'Ne',
                ),
              ],
            ),
          ),
          if (findings.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionCard(
              title: 'Ugotovitve za to aplikacijo',
              child: Column(
                children: [
                  for (final f in findings)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: RiskBadge(severity: f.severity),
                      title: Text(f.title),
                      subtitle: Text(f.description),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          SectionCard(
            title: 'Posebni dostopi',
            child: Column(
              children: [
                if (hasAccessibility)
                  _accessRow(
                    context,
                    'Dostopnostna storitev je omogočena',
                    () => _permissionGate.openAccessibilitySettings(),
                  ),
                if (hasNotificationAccess)
                  _accessRow(
                    context,
                    'Dostop do obvestil je omogočen',
                    () => _permissionGate.openNotificationListenerSettings(),
                  ),
                if (isDeviceAdmin)
                  _accessRow(
                    context,
                    'Ima pravice skrbnika naprave',
                    () => _permissionGate.openSecuritySettings(),
                  ),
                if (!hasAccessibility && !hasNotificationAccess && !isDeviceAdmin)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Brez posebnih sistemskih dostopov'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Odobrena dovoljenja (${app.grantedPermissions.length})',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in app.grantedPermissions)
                  Chip(label: Text(_shortPermission(p)), visualDensity: VisualDensity.compact),
                if (app.grantedPermissions.isEmpty) const Text('Brez odobrenih dovoljenj'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Odpri nastavitve aplikacije'),
            onPressed: () => NativeBridge.instance.openAppDetailsSettings(app.packageName),
          ),
        ],
      ),
    );
  }

  Widget _accessRow(BuildContext context, String label, VoidCallback onManage) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
      title: Text(label),
      trailing: TextButton(onPressed: onManage, child: const Text('Upravljaj')),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 190, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _shortPermission(String full) => full.replaceFirst('android.permission.', '');

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
