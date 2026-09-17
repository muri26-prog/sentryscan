import 'package:flutter/material.dart';

import '../services/scan_service.dart';
import 'scan_report_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.scanService});

  final ScanService scanService;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  String _stage = 'Pripravljam pregled ...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    try {
      final report = await widget.scanService.runScan(
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScanReportScreen(scanService: widget.scanService, report: report),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pregled v teku')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _error != null
                ? [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Napaka med pregledom: $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _runScan();
                      },
                      child: const Text('Poskusi znova'),
                    ),
                  ]
                : [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(_stage, textAlign: TextAlign.center),
                  ],
          ),
        ),
      ),
    );
  }
}
