import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import '../widgets/section_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  bool _vtEnabled = false;
  bool _batterySamplingEnabled = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await StorageService.instance.getVtApiKey();
    final vtEnabled = await StorageService.instance.vtLookupsEnabled();
    final batteryEnabled = await StorageService.instance.isBatterySamplingEnabled();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
      _vtEnabled = vtEnabled;
      _batterySamplingEnabled = batteryEnabled;
      _version = '${info.version} (${info.buildNumber})';
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      await StorageService.instance.clearVtApiKey();
    } else {
      await StorageService.instance.setVtApiKey(value);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shranjeno.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'VirusTotal preverjanje',
            subtitle: 'Za sumljive aplikacije se lahko izračuna SHA-256 in preveri '
                'proti bazi znanih groženj na virustotal.com',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _vtEnabled,
                  title: const Text('Omogoči VirusTotal poizvedbe'),
                  subtitle: const Text(
                    'Ko je vklopljeno, se za izbrane aplikacije SHA-256 hash pošlje '
                    'na virustotal.com - nikoli vsebina datoteke same.',
                  ),
                  onChanged: (v) async {
                    setState(() => _vtEnabled = v);
                    await StorageService.instance.setVtLookupsEnabled(v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: 'VirusTotal API ključ',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(onPressed: _saveApiKey, child: const Text('Shrani')),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://www.virustotal.com/gui/my-apikey'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Pridobi ključ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Spremljanje baterije',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _batterySamplingEnabled,
              title: const Text('Periodično beleženje v ozadju'),
              subtitle: const Text('Priporočljivo za analizo praznjenja baterije.'),
              onChanged: (v) async {
                setState(() => _batterySamplingEnabled = v);
                await StorageService.instance.setBatterySamplingEnabled(v);
              },
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'O aplikaciji',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Različica: $_version'),
                const SizedBox(height: 8),
                const Text(
                  'SentryScan izvaja izključno lokalno hevristično analizo na podlagi '
                  'javno dokumentiranih Android API-jev. Ni nadomestilo za profesionalno '
                  'forenzično preiskavo. Najdbe so indikatorji tveganja, ne dokončen dokaz '
                  'okužbe - vsako kritično/visoko najdbo preveri ročno, preden ukrepaš '
                  '(npr. izbrišeš aplikacijo ali ponastaviš napravo).',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
