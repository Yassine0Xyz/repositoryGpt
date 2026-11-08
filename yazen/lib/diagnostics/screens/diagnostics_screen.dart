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
  bool _exporting = false;

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
    final process =
        (diagnostics.latestResourceSnapshot?['process'] as Map?)
            ?.cast<String, Object?>() ??
        const <String, Object?>{};
    final pssKb = process['processPssKb'] as num?;
    final cpuPercent =
        process['processCpuPercentSincePreviousSnapshot'] as num?;
    final javaHeap = process['javaHeapUsedBytes'] as num?;
    final nativeHeap = process['nativeHeapAllocatedBytes'] as num?;
    final threadSamples =
        (process['threadCpuSamples'] as List?)?.whereType<Map>().toList(
          growable: false,
        ) ??
        const <Map>[];
    return Scaffold(
      appBar: AppBar(title: const Text('YAZEN Performance Intelligence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _sectionCard(
            context,
            title: 'LIVE PERFORMANCE',
            subtitle: 'Refresh-rate-aware frame monitoring',
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: <Widget>[
                _Metric(
                  label: 'Build mode',
                  value: diagnostics.buildMode.toUpperCase(),
                ),
                _Metric(
                  label: 'Display refresh',
                  value: '${diagnostics.refreshRateHz.toStringAsFixed(0)} Hz',
                ),
                _Metric(
                  label: 'Frame budget',
                  value: '${diagnostics.frameBudgetMs.toStringAsFixed(2)} ms',
                ),
                _Metric(
                  label: 'Estimated FPS*',
                  value: diagnostics.estimatedFps.toStringAsFixed(1),
                ),
                _Metric(
                  label: 'Average frame',
                  value: '${diagnostics.averageFrameMs.toStringAsFixed(2)} ms',
                ),
                _Metric(
                  label: 'P50 / P90',
                  value:
                      '${diagnostics.p50FrameMs.toStringAsFixed(2)} / ${diagnostics.p90FrameMs.toStringAsFixed(2)} ms',
                ),
                _Metric(
                  label: 'P95 / P99',
                  value:
                      '${diagnostics.p95FrameMs.toStringAsFixed(2)} / ${diagnostics.p99FrameMs.toStringAsFixed(2)} ms',
                ),
                _Metric(
                  label: 'Over budget',
                  value: '${diagnostics.slowFrames}',
                ),
                _Metric(
                  label: 'Over 2× budget',
                  value: '${diagnostics.verySlowFrames}',
                ),
                _Metric(
                  label: 'Build / Raster',
                  value:
                      '${diagnostics.averageBuildMs.toStringAsFixed(1)} / ${diagnostics.averageRasterMs.toStringAsFixed(1)} ms',
                ),
                _Metric(
                  label: 'VSync overhead',
                  value: '${diagnostics.averageVsyncMs.toStringAsFixed(2)} ms',
                ),
                _Metric(
                  label: 'Session duration',
                  value: _duration(diagnostics.sessionMilliseconds),
                ),
                _Metric(
                  label: 'Frames captured',
                  value: '${diagnostics.frameCount}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'CPU & MEMORY SNAPSHOT',
            subtitle: 'Native process snapshots; not per-widget attribution',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 14,
                  children: <Widget>[
                    _Metric(
                      label: 'Process PSS',
                      value:
                          pssKb == null
                              ? '—'
                              : '${(pssKb / 1024).toStringAsFixed(1)} MB',
                    ),
                    _Metric(
                      label: 'Process CPU',
                      value:
                          cpuPercent == null || cpuPercent < 0
                              ? 'Sampling…'
                              : '${cpuPercent.toStringAsFixed(1)}%',
                    ),
                    _Metric(
                      label: 'Java heap',
                      value:
                          javaHeap == null
                              ? '—'
                              : '${(javaHeap / (1024 * 1024)).toStringAsFixed(1)} MB',
                    ),
                    _Metric(
                      label: 'Native heap',
                      value:
                          nativeHeap == null
                              ? '—'
                              : '${(nativeHeap / (1024 * 1024)).toStringAsFixed(1)} MB',
                    ),
                  ],
                ),
                if (threadSamples.isNotEmpty) ...<Widget>[
                  const Divider(height: 24),
                  const Text(
                    'Top active threads (raw CPU ticks since prior sample)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final thread in threadSamples.take(6))
                    _StatusLine(
                      label:
                          '${thread['name'] ?? 'unknown'} · TID ${thread['threadId']}',
                      value:
                          '${thread['deltaTicksSincePreviousSnapshot'] ?? '—'} ticks',
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'ARTWORK PIPELINE',
            subtitle: 'Memory/disk cache, request gate and source/decode spans',
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: <Widget>[
                _Metric(
                  label: 'Loads started',
                  value: '${diagnostics.artworkLoadsStarted}',
                ),
                _Metric(
                  label: 'Success / null / exception',
                  value:
                      '${diagnostics.artworkLoadsSucceeded} / ${diagnostics.artworkLoadsReturnedNull} / ${diagnostics.artworkLoadsExceptionFailed}',
                ),
                _Metric(
                  label: 'Memory hit / miss',
                  value:
                      '${diagnostics.artworkMemoryHits} / ${diagnostics.artworkMemoryMisses}',
                ),
                _Metric(
                  label: 'Disk hit / miss',
                  value:
                      '${diagnostics.artworkDiskHits} / ${diagnostics.artworkDiskMisses}',
                ),
                _Metric(
                  label: 'Gate rejected',
                  value: '${diagnostics.artworkGateRejected}',
                ),
                _Metric(
                  label: 'Evicted / queue full',
                  value:
                      '${diagnostics.artworkGateQueueEvicted} / ${diagnostics.artworkGateQueueFull}',
                ),
                _Metric(
                  label: 'Disk writes ok / skip / reject / fail',
                  value:
                      '${diagnostics.artworkDiskWritesSucceeded} / ${diagnostics.artworkDiskWritesSkipped} / ${diagnostics.artworkDiskWritesRejected} / ${diagnostics.artworkDiskWritesFailed}',
                ),
                _Metric(
                  label: 'Disk gate evicted / queue full',
                  value:
                      '${diagnostics.artworkDiskWriteGateQueueEvicted} / ${diagnostics.artworkDiskWriteGateQueueFull}',
                ),
                _Metric(
                  label: 'First frames visible',
                  value: '${diagnostics.artworkFirstFramesVisible}',
                ),
                _Metric(
                  label: 'Avg / max visible',
                  value:
                      '${diagnostics.averageArtworkTimeToVisibleMs.toStringAsFixed(1)} / ${diagnostics.maxArtworkTimeToVisibleMs} ms',
                ),
                _Metric(
                  label: 'Active spans',
                  value: '${diagnostics.activeSpanCount}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'VIDEO THUMBNAIL PIPELINE',
            subtitle:
                'Memory cache, deduplication, bounded decode gate and source result',
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: <Widget>[
                _Metric(
                  label: 'Loads started',
                  value: '${diagnostics.videoThumbnailLoadsStarted}',
                ),
                _Metric(
                  label: 'Success / null / failed',
                  value:
                      '${diagnostics.videoThumbnailLoadsSucceeded} / ${diagnostics.videoThumbnailLoadsReturnedNull} / ${diagnostics.videoThumbnailLoadsFailed}',
                ),
                _Metric(
                  label: 'Cache hit / miss',
                  value:
                      '${diagnostics.videoThumbnailCacheHits} / ${diagnostics.videoThumbnailCacheMisses}',
                ),
                _Metric(
                  label: 'Deduplicated / gate rejected',
                  value:
                      '${diagnostics.videoThumbnailRequestsDeduplicated} / ${diagnostics.videoThumbnailGateRejected}',
                ),
                _Metric(
                  label: 'Cache evictions / visible',
                  value:
                      '${diagnostics.videoThumbnailCacheEvictions} / ${diagnostics.videoThumbnailFirstFramesVisible}',
                ),
                _Metric(
                  label: 'Avg / max visible',
                  value:
                      '${diagnostics.averageVideoThumbnailTimeToVisibleMs.toStringAsFixed(1)} / ${diagnostics.maxVideoThumbnailTimeToVisibleMs} ms',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'LIBRARY & PLAYBACK PIPELINE',
            subtitle: 'Query/mapping/sort/search stages and user operations',
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: <Widget>[
                _Metric(
                  label: 'Library query spans',
                  value: '${diagnostics.libraryQuerySpans}',
                ),
                _Metric(
                  label: 'Transform spans',
                  value: '${diagnostics.libraryTransformSpans}',
                ),
                _Metric(
                  label: 'Playback events',
                  value: '${diagnostics.playbackActionEvents}',
                ),
                _Metric(
                  label: 'Framework reports / async errors / failed spans',
                  value:
                      '${diagnostics.flutterFrameworkReportEvents} / ${diagnostics.uncaughtAsyncErrorEvents} / ${diagnostics.failedSpanEvents}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'DIAGNOSTICS OVERHEAD',
            subtitle:
                'Sampled recorder cost and asynchronous journal write cost',
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: <Widget>[
                _Metric(
                  label: 'Avg record sample',
                  value:
                      '${diagnostics.averageSampledRecordCostUs.toStringAsFixed(1)} µs',
                ),
                _Metric(
                  label: 'Max record sample',
                  value: '${diagnostics.maxSampledRecordCostUs} µs',
                ),
                _Metric(
                  label: 'Avg journal drain',
                  value:
                      '${diagnostics.averageJournalDrainCostUs.toStringAsFixed(1)} µs',
                ),
                _Metric(
                  label: 'Max journal drain',
                  value: '${diagnostics.maxJournalDrainCostUs} µs',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'INTERACTION JOURNAL',
            subtitle: 'Raw scroll updates and pointer movement while pressed',
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: <Widget>[
                _Metric(
                  label: 'Scroll sessions',
                  value: '${diagnostics.scrollSessions}',
                ),
                _Metric(
                  label: 'Scroll samples',
                  value: '${diagnostics.scrollUpdates}',
                ),
                _Metric(
                  label: 'Pointer sessions',
                  value: '${diagnostics.pointerSessions}',
                ),
                _Metric(
                  label: 'Pointer up / cancel',
                  value:
                      '${diagnostics.pointerCompleted} / ${diagnostics.pointerCancelled}',
                ),
                _Metric(
                  label: 'Tap / drag / long-press candidates',
                  value:
                      '${diagnostics.pointerTapCandidates} / ${diagnostics.pointerDragCandidates} / ${diagnostics.pointerLongPressCandidates}',
                ),
                _Metric(
                  label: 'Pointer move samples',
                  value: '${diagnostics.pointerMoves}',
                ),
                _Metric(
                  label: 'Scroll completed',
                  value: '${diagnostics.scrollCompleted}',
                ),
                _Metric(
                  label: 'Interrupted pointer / scroll',
                  value:
                      '${diagnostics.pointerInterrupted} / ${diagnostics.scrollInterrupted}',
                ),
                _Metric(
                  label: 'Route changes',
                  value: '${diagnostics.routeChanges}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'SESSION RECORDING',
            subtitle:
                'Append-only JSONL journal; the dashboard cache is not the export source',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Record diagnostics'),
                  subtitle: const Text(
                    'Pause/resume event collection for this session',
                  ),
                  value: diagnostics.recording,
                  onChanged:
                      (value) =>
                          setState(() => diagnostics.setRecording(value)),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Maximum Investigation'),
                  subtitle: const Text(
                    '1s native snapshots + Flutter build/layout/paint timelines in Debug/Profile; lightweight Hybrid monitoring remains active',
                  ),
                  value: diagnostics.deepInvestigation,
                  onChanged:
                      (value) => setState(
                        () => diagnostics.setDeepInvestigation(value),
                      ),
                ),
                const SizedBox(height: 8),
                _StatusLine(
                  label: 'Journal',
                  value:
                      diagnostics.journalReady
                          ? 'Writing session events'
                          : 'Initializing…',
                  good: diagnostics.journalReady,
                ),
                _StatusLine(
                  label: 'Journal events',
                  value: '${diagnostics.totalJournalEvents}',
                ),
                _StatusLine(
                  label: 'Pending / dropped',
                  value:
                      '${diagnostics.journalPendingCount} / ${diagnostics.journalDroppedEvents}',
                ),
                _StatusLine(
                  label: 'Dashboard cache',
                  value: '${diagnostics.retainedEventCount} events (bounded)',
                ),
                if (diagnostics.journalError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Journal warning: ${diagnostics.journalError}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (diagnostics.journalPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      diagnostics.journalPath!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading:
                  _exporting
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.file_download_outlined),
              title: const Text('Export complete session'),
              subtitle: const Text(
                'JSONL raw event journal + JSON analysis + Markdown report',
              ),
              enabled: !_exporting,
              onTap: _exporting ? null : _export,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '*Estimated FPS is derived from average Flutter frame duration, not a hardware FPS counter. Pointer samples are captured while a pointer is down; hover movement is excluded. JSONL is the ordered raw journal. If the journal reports dropped events or an I/O error, the export explicitly reports that limitation.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await DiagnosticsService.instance.export();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Session export completed'),
              content: SelectableText(
                '${result.eventCount} journal events persisted.\n\n${result.paths.join('\n\n')}',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
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
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    this.good = false,
  });
  final String label;
  final String value;
  final bool good;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: good ? Colors.green : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
