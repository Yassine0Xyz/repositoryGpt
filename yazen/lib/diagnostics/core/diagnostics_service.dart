import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Temporary, isolated performance recorder. Remove this folder and the two
/// integration points documented in docs/TEMP_DIAGNOSTICS_REMOVAL.md to revert.
class DiagnosticsService {
  DiagnosticsService._();
  static final DiagnosticsService instance = DiagnosticsService._();

  static const MethodChannel _native = MethodChannel('yazen/diagnostics');
  static const int _maxEvents = 12000;

  final Queue<Map<String, Object?>> _events = Queue<Map<String, Object?>>();
  final Stopwatch _sessionClock = Stopwatch()..start();
  bool _started = false;
  bool _recording = true;
  Timer? _resourceTimer;
  bool _resourceSnapshotInFlight = false;
  Future<PackageInfo>? _packageInfoFuture;
  final List<Map<String, Object?>> _resourceSnapshots = <Map<String, Object?>>[];
  int _frameCount = 0;
  int _slowFrames = 0;
  int _verySlowFrames = 0;
  int _scrollUpdates = 0;
  int _scrollSessions = 0;
  int _routeChanges = 0;
  int _maxFrameMicros = 0;
  int _totalFrameMicros = 0;
  int _totalBuildMicros = 0;
  int _totalRasterMicros = 0;
  final List<int> _recentFrameMicros = <int>[];
  String _currentRoute = 'startup';
  int? _previousScrollElapsedMs;
  int? _scrollStartElapsedMs;
  double? _previousScrollPixels;
  final _DiagnosticsLifecycleObserver _lifecycleObserver = _DiagnosticsLifecycleObserver();

  bool get recording => _recording;
  int get frameCount => _frameCount;
  int get slowFrames => _slowFrames;
  int get verySlowFrames => _verySlowFrames;
  int get scrollUpdates => _scrollUpdates;
  int get scrollSessions => _scrollSessions;
  int get routeChanges => _routeChanges;
  int get retainedEventCount => _events.length;
  double get averageFrameMs => _frameCount == 0 ? 0 : _totalFrameMicros / _frameCount / 1000;
  double get averageBuildMs => _frameCount == 0 ? 0 : _totalBuildMicros / _frameCount / 1000;
  double get averageRasterMs => _frameCount == 0 ? 0 : _totalRasterMicros / _frameCount / 1000;
  double get estimatedFps => averageFrameMs <= 0 ? 0 : 1000 / averageFrameMs;
  int get sessionMilliseconds => _sessionClock.elapsedMilliseconds;
  Map<String, Object?>? get latestResourceSnapshot => _resourceSnapshots.isEmpty ? null : _resourceSnapshots.last;
  int get p95FrameMs => _percentile(_recentFrameMicros, .95) ~/ 1000;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lifecycleObserver.onState = lifecycleChanged;
    record('session_start', <String, Object?>{
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'debugMode': kDebugMode,
      'profileMode': kProfileMode,
      'releaseMode': kReleaseMode,
    });
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record('flutter_error', <String, Object?>{
        'exception': details.exceptionAsString(),
        'library': details.library,
        'context': details.context?.toDescription(),
        'stack': details.stack?.toString(),
      });
    };
    unawaited(_capturePeriodicResourceSnapshot());
    _resourceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_recording) unawaited(_capturePeriodicResourceSnapshot());
    });
    PlatformDispatcher.instance.onError = (error, stack) {
      record('uncaught_async_error', <String, Object?>{
        'error': error.toString(),
        'stack': stack.toString(),
      });
      return false;
    };
  }

  void setRecording(bool value) {
    if (value) {
      _recording = true;
      record('recording_resumed');
      unawaited(_capturePeriodicResourceSnapshot());
    } else {
      record('recording_paused');
      _recording = false;
    }
  }

  void record(String type, [Map<String, Object?> data = const <String, Object?>{}]) {
    if (!_recording && type != 'recording_resumed') return;
    final event = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'elapsedMs': _sessionClock.elapsedMilliseconds,
      'route': _currentRoute,
      'type': type,
      'data': data,
    };
    if (_events.length >= _maxEvents) _events.removeFirst();
    _events.addLast(event);
  }

  void routeChanged(String route, {required String action}) {
    if (!_recording) return;
    _currentRoute = route;
    _routeChanges++;
    record('navigation_$action', <String, Object?>{'routeName': route});
  }

  void scrollStarted({required String axis, required double pixels}) {
    if (!_recording) return;
    _scrollSessions++;
    _scrollStartElapsedMs = _sessionClock.elapsedMilliseconds;
    _previousScrollElapsedMs = null;
    _previousScrollPixels = pixels;
    record('scroll_start', <String, Object?>{'axis': axis, 'pixels': pixels});
  }

  void scrollUpdated({required double? delta, required double pixels, required double maxExtent}) {
    if (!_recording) return;
    _scrollUpdates++;
    final now = _sessionClock.elapsedMilliseconds;
    final previousTime = _previousScrollElapsedMs;
    final previousPixels = _previousScrollPixels;
    final elapsed = previousTime == null ? null : now - previousTime;
    final velocity = (elapsed != null && elapsed > 0 && previousPixels != null)
        ? ((pixels - previousPixels) / elapsed * 1000)
        : null;
    _previousScrollElapsedMs = now;
    _previousScrollPixels = pixels;
    // Per-update samples make fast-drag responsiveness measurable and can be
    // correlated with slow-frame events on the same session timeline.
    record('scroll_update', <String, Object?>{
      'delta': delta,
      'pixels': pixels,
      'maxExtent': maxExtent,
      'estimatedPixelsPerSecond': velocity,
      'intervalMs': elapsed,
      'startToFirstUpdateMs': previousTime == null && _scrollStartElapsedMs != null ? now - _scrollStartElapsedMs! : null,
    });
  }

  void scrollEnded({required double pixels, required double maxExtent}) {
    if (!_recording) return;
    record('scroll_end', <String, Object?>{'pixels': pixels, 'maxExtent': maxExtent});
    _scrollStartElapsedMs = null;
    _previousScrollElapsedMs = null;
    _previousScrollPixels = null;
  }

  void lifecycleChanged(AppLifecycleState state) {
    record('lifecycle', <String, Object?>{'state': state.name});
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_recording) return;
    for (final timing in timings) {
      final total = timing.totalSpan.inMicroseconds;
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      _frameCount++;
      _totalFrameMicros += total;
      _totalBuildMicros += build;
      _totalRasterMicros += raster;
      if (total > _maxFrameMicros) _maxFrameMicros = total;
      if (total > 16667) _slowFrames++;
      if (total > 33333) _verySlowFrames++;
      _recentFrameMicros.add(total);
      if (_recentFrameMicros.length > 600) _recentFrameMicros.removeAt(0);
      if (total > 25000 || build > 16000 || raster > 16000) {
        record('slow_frame', <String, Object?>{
          'frameNumber': _frameCount,
          'totalMs': total / 1000,
          'buildMs': build / 1000,
          'rasterMs': raster / 1000,
          'vsyncOverheadMs': timing.vsyncOverhead.inMicroseconds / 1000,
        });
      }
    }
  }

  Future<Map<String, Object?>> _resourceSnapshot({bool includeStorage = true}) async {
    Map<String, Object?> native = <String, Object?>{};
    try {
      final result = await _native.invokeMapMethod<String, Object?>('resourceSnapshot', <String, Object?>{'includeStorage': includeStorage});
      if (result != null) native = result;
    } catch (error) {
      native = <String, Object?>{'nativeSnapshotError': error.toString()};
    }
    final info = await (_packageInfoFuture ??= PackageInfo.fromPlatform());
    return <String, Object?>{
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'app': <String, Object?>{
        'name': info.appName,
        'package': info.packageName,
        'version': info.version,
        'build': info.buildNumber,
      },
      'platform': <String, Object?>{
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'localeName': Platform.localeName,
        'numberOfProcessors': Platform.numberOfProcessors,
      },
      'process': native,
    };
  }

  Future<void> _capturePeriodicResourceSnapshot() async {
    if (_resourceSnapshotInFlight || !_recording) return;
    _resourceSnapshotInFlight = true;
    try {
      final snapshot = await _resourceSnapshot(includeStorage: false);
      if (_resourceSnapshots.length >= 600) _resourceSnapshots.removeAt(0);
      _resourceSnapshots.add(snapshot);
      record('resource_snapshot', snapshot);
    } catch (error) {
      record('resource_snapshot_failed', <String, Object?>{'error': error.toString()});
    } finally {
      _resourceSnapshotInFlight = false;
    }
  }

  List<num> _resourceValues(String key) {
    return _resourceSnapshots
        .map((snapshot) => snapshot['process'])
        .whereType<Map>()
        .map((process) => process[key])
        .whereType<num>()
        .where((value) => value >= 0)
        .toList(growable: false);
  }

  num? _maxResourceValue(String key) {
    final values = _resourceValues(key);
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  double? _averageResourceValue(String key) {
    final values = _resourceValues(key);
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Map<String, Object?> _summary() => <String, Object?>{
    'sessionDurationMs': _sessionClock.elapsedMilliseconds,
    'frameCount': _frameCount,
    'estimatedFpsFromAverageFrameTime': double.parse(estimatedFps.toStringAsFixed(2)),
    'averageFrameMs': double.parse(averageFrameMs.toStringAsFixed(3)),
    'averageBuildMs': double.parse(averageBuildMs.toStringAsFixed(3)),
    'averageRasterMs': double.parse(averageRasterMs.toStringAsFixed(3)),
    'p95RecentFrameMs': p95FrameMs,
    'maxFrameMs': _maxFrameMicros / 1000,
    'framesOver16_67ms': _slowFrames,
    'framesOver33_33ms': _verySlowFrames,
    'scrollSessions': _scrollSessions,
    'scrollUpdates': _scrollUpdates,
    'navigationChanges': _routeChanges,
    'eventsRetained': _events.length,
    'eventLimit': _maxEvents,
    'peakProcessPssKb': _maxResourceValue('processPssKb'),
    'peakJavaHeapUsedBytes': _maxResourceValue('javaHeapUsedBytes'),
    'averageProcessCpuPercent': _averageResourceValue('processCpuPercentSincePreviousSnapshot'),
  };

  Future<DiagnosticExport> export() async {
    record('report_export_requested');
    final resources = await _resourceSnapshot(includeStorage: true);
    final includedEventCount = _events.length;
    final jsonReport = <String, Object?>{
      'schemaVersion': 1,
      'product': 'YAZEN-PLAYER temporary diagnostics',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'summary': _summary(),
      'resourceSnapshot': resources,
      'resourceSnapshotsDuringSession': List<Map<String, Object?>>.unmodifiable(_resourceSnapshots),
      'events': List<Map<String, Object?>>.unmodifiable(_events),
      'notes': <String>[
        'Frame timings are Flutter engine timings captured through addTimingsCallback.',
        'FPS is estimated from average frame duration; it is not a hardware display refresh measurement.',
        'Native process memory and CPU values are point-in-time snapshots where supported.',
        'The event buffer is bounded; oldest events are discarded after the configured limit.',
      ],
    };
    final json = const JsonEncoder.withIndent('  ').convert(jsonReport);
    final text = StringBuffer()
      ..writeln('YAZEN-PLAYER DIAGNOSTIC SESSION')
      ..writeln('Generated: ${jsonReport['generatedAt']}')
      ..writeln('\nSUMMARY')
      ..writeln(const JsonEncoder.withIndent('  ').convert(_summary()))
      ..writeln('\nRESOURCE SNAPSHOT')
      ..writeln(const JsonEncoder.withIndent('  ').convert(resources))
      ..writeln('\nEVENT LOG (${_events.length} events)');
    for (final event in _events) {
      text.writeln('${event['timestamp']} +${event['elapsedMs']}ms [${event['type']}] route=${event['route']} ${jsonEncode(event['data'])}');
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final files = <String, String>{
      'yazen-diagnostics-$stamp.json': json,
      'yazen-diagnostics-$stamp.txt': text.toString(),
    };
    final saved = <String>[];
    try {
      final nativeResult = await _native.invokeListMethod<String>('saveDiagnosticFiles', <String, String>{
        for (final entry in files.entries) entry.key: entry.value,
      });
      if (nativeResult != null && nativeResult.isNotEmpty) saved.addAll(nativeResult);
    } catch (_) {
      final directory = await getApplicationDocumentsDirectory();
      for (final entry in files.entries) {
        final file = File('${directory.path}/${entry.key}');
        await file.writeAsString(entry.value, flush: true);
        saved.add(file.path);
      }
    }
    record('report_export_completed', <String, Object?>{'files': saved});
    return DiagnosticExport(paths: saved, eventCount: includedEventCount, summary: _summary());
  }

  static int _percentile(List<int> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.of(values)..sort();
    final index = ((sorted.length - 1) * percentile).ceil().clamp(0, sorted.length - 1);
    return sorted[index];
  }
}

class DiagnosticExport {
  const DiagnosticExport({required this.paths, required this.eventCount, required this.summary});
  final List<String> paths;
  final int eventCount;
  final Map<String, Object?> summary;
}

class _DiagnosticsLifecycleObserver with WidgetsBindingObserver {
  void Function(AppLifecycleState state)? onState;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onState?.call(state);
  }
}
