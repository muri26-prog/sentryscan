import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/scan_service.dart';
import 'theme.dart';

class SentryScanApp extends StatefulWidget {
  const SentryScanApp({super.key});

  @override
  State<SentryScanApp> createState() => _SentryScanAppState();
}

class _SentryScanAppState extends State<SentryScanApp> {
  final _scanService = ScanService();

  @override
  void dispose() {
    _scanService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentryScan',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildSentryScanTheme(Brightness.light),
      darkTheme: buildSentryScanTheme(Brightness.dark),
      home: HomeScreen(scanService: _scanService),
    );
  }
}
