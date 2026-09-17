import 'package:flutter/material.dart';

import '../models/system_security_snapshot.dart';
import '../services/native_bridge.dart';
import '../services/permission_gate_service.dart';
import '../widgets/permission_tile.dart';
import '../widgets/section_card.dart';

class PermissionsSetupScreen extends StatefulWidget {
  const PermissionsSetupScreen({super.key});

  @override
  State<PermissionsSetupScreen> createState() => _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState extends State<PermissionsSetupScreen> with WidgetsBindingObserver {
  final _gate = const PermissionGateService();

  bool _loading = true;
  SystemSecuritySnapshot? _snapshot;
  bool _notificationGranted = false;
  bool _batteryExemptGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uporabnik se pogosto vrne sem po tem, ko je v Nastavitvah nekaj
    // spremenil - ob vrnitvi v aplikacijo osvežimo stanje.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final snapshot = await NativeBridge.instance.getSystemSecuritySnapshot();
    final notification = await _gate.isNotificationGranted();
    final batteryExempt = await _gate.isIgnoringBatteryOptimizationsForSelf();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _notificationGranted = notification;
      _batteryExemptGranted = batteryExempt;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dovoljenja za polno delovanje')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionCard(
                  title: 'Zakaj to potrebujemo',
                  child: Text(
                    'SentryScan je "sideload" aplikacija (ni iz Google Play), zato lahko '
                    'zahteva dostope, ki bi jih Play sicer omejeval. Nekaterih od njih '
                    'Android ne dovoli vklopiti z navadnim pojavnim oknom - moraš jih '
                    'ročno potrditi spodaj.',
                  ),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  title: 'Dovoljenja',
                  child: Column(
                    children: [
                      PermissionTile(
                        title: 'Dostop do statistike uporabe (Usage access)',
                        description: 'Potreben za analizo baterije in zaznavo skritih, '
                            'nenehno aktivnih aplikacij.',
                        granted: _snapshot?.usageAccessGranted ?? false,
                        onOpenSettings: () async {
                          await _gate.openUsageAccessSettings();
                        },
                      ),
                      const Divider(),
                      PermissionTile(
                        title: 'Obvestila',
                        description: 'Za opozorilo, ko se pregled zaključi ali zazna kritično najdbo.',
                        granted: _notificationGranted,
                        actionLabel: 'Dovoli',
                        onOpenSettings: () async {
                          await _gate.requestNotificationPermission();
                          _refresh();
                        },
                      ),
                      const Divider(),
                      PermissionTile(
                        title: 'Izjema od varčevanja baterije (za SentryScan)',
                        description: 'Da lahko periodično spremljanje baterije zanesljivo '
                            'teče tudi, ko je zaslon ugasnjen.',
                        granted: _batteryExemptGranted,
                        actionLabel: 'Dovoli',
                        onOpenSettings: () async {
                          await _gate.requestIgnoreBatteryOptimizationsForSelf();
                          _refresh();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  title: 'Preglednice, ki jih lahko odpreš ročno',
                  subtitle: 'Za pregled/upravljanje drugih aplikacij (ne SentryScan)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.accessibility_new),
                        label: const Text('Seznam dostopnostnih storitev'),
                        onPressed: () => _gate.openAccessibilitySettings(),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.notifications_none),
                        label: const Text('Seznam aplikacij z dostopom do obvestil'),
                        onPressed: () => _gate.openNotificationListenerSettings(),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.security),
                        label: const Text('Varnostne nastavitve (skrbniki naprave, zaklep)'),
                        onPressed: () => _gate.openSecuritySettings(),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.battery_saver_outlined),
                        label: const Text('Vse izjeme od varčevanja baterije'),
                        onPressed: () => _gate.openBatteryOptimizationSettings(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
