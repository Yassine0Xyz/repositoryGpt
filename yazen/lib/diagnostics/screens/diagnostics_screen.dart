import 'dart:async';

import 'package:flutter/material.dart';

import '../core/diagnostics_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = DiagnosticsService.instance;
    final process = (diagnostics.latestResourceSnapshot?['process'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final pssKb = process['processPssKb'] as num?;
    final cpuPercent = process['processCpuPercentSincePreviousSnapshot'] as num?;
    final javaHeap = process['javaHeapUsedBytes'] as num?;
    final refreshRate = process['displayRefreshRateHz'] as num?;
    return Scaffold(
      appBar: AppBar(title: const Text('Performance diagnostics')),
      body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const Text('LIVE SESSION', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
                  _Metric(label: 'Estimated FPS', value: diagnostics.estimatedFps.toStringAsFixed(1)),
                  _Metric(label: 'Average frame', value: '${diagnostics.averageFrameMs.toStringAsFixed(2)} ms'),
                  _Metric(label: 'P95 recent frame', value: '${diagnostics.p95FrameMs} ms'),
                  _Metric(label: 'Frames >16.67 ms', value: '${diagnostics.slowFrames}'),
                  _Metric(label: 'Frames >33.33 ms', value: '${diagnostics.verySlowFrames}'),
                  _Metric(label: 'Process PSS', value: pssKb == null ? '—' : '${(pssKb / 1024).toStringAsFixed(1)} MB'),
                  _Metric(label: 'CPU (sampled)', value: cpuPercent == null || cpuPercent < 0 ? 'Sampling…' : '${cpuPercent.toStringAsFixed(1)}%'),
                  _Metric(label: 'Java heap', value: javaHeap == null ? '—' : '${(javaHeap / (1024 * 1024)).toStringAsFixed(1)} MB'),
                  _Metric(label: 'Display refresh', value: refreshRate == null ? '—' : '${refreshRate.toStringAsFixed(0)} Hz'),
                  _Metric(label: 'Scroll updates', value: '${diagnostics.scrollUpdates}'),
                  _Metric(label: 'Navigation changes', value: '${diagnostics.routeChanges}'),
                  _Metric(label: 'Session', value: _duration(diagnostics.sessionMilliseconds)),
                ]),
                const SizedBox(height: 12),
                Text('Build ${diagnostics.averageBuildMs.toStringAsFixed(2)} ms  •  Raster ${diagnostics.averageRasterMs.toStringAsFixed(2)} ms', style: Theme.of(context).textTheme.bodySmall),
              ]),
            )),
            const SizedBox(height: 12),
            Card(child: SwitchListTile(
              title: const Text('Record diagnostics'),
              subtitle: const Text('Temporarily pause or resume event collection'),
              value: diagnostics.recording,
              onChanged: (value) => setState(() => diagnostics.setRecording(value)),
            )),
            const SizedBox(height: 12),
            Card(child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export full session logs'),
              subtitle: const Text('JSON data and readable TXT report saved to Downloads'),
              onTap: _export,
            )),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Measurements are collected locally for temporary diagnosis. Frame timings are Flutter engine timings; memory, CPU and storage are native point-in-time snapshots. The recorder keeps a bounded event history to limit its own overhead.', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
    );
  }

  Future<void> _export() async {
    try {
      final result = await DiagnosticsService.instance.export();
      if (!mounted) return;
      showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Diagnostic report exported'),
        content: SelectableText('${result.eventCount} events saved:\n\n${result.paths.join('\n\n')}'),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  String _duration(int ms) {
    final seconds = ms ~/ 1000;
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(width: 145, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Text(label, style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 3),
    Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
  ]));
}

