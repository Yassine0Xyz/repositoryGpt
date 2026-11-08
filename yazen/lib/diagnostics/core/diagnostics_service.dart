import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Session recorder for YAZEN Performance Intelligence.
///
/// The in-memory event list is intentionally a bounded dashboard cache. The
/// append-only JSONL journal is the source of truth for a session export.
class DiagnosticsService {
  DiagnosticsService._();
  static final DiagnosticsService instance = DiagnosticsService._();

  static const MethodChannel _native = MethodChannel('yazen/diagnostics');
  static const int _dashboardEventLimit = 12000;
  static const int _pendingJournalLimit = 8192;
  static const int _recentFrameLimit = 1200;

  final Queue<Map<String, Object?>> _events = Queue<Map<String, Object?>>();
  final Queue<String> _pendingJournalLines = Queue<String>();
  final Stopwatch _sessionClock = Stopwatch()..start();
  final List<Map<String, Object?>> _resourceSnapshots =
      <Map<String, Object?>>[];
  final Queue<int> _recentFrameMicros = Queue<int>();
  final Map<int, _PointerSession> _activePointers = <int, _PointerSession>{};
  final _DiagnosticsLifecycleObserver _lifecycleObserver =
      _DiagnosticsLifecycleObserver();

  bool _started = false;
  bool _recording = true;
  bool _deepInvestigation = false;
  bool _journalReady = false;
  bool _journalDraining = false;
  bool _journalSnapshotting = false;
  bool _resourceSnapshotInFlight = false;
  bool _exportInFlight = false;
  Timer? _resourceTimer;
  Timer? _journalTimer;
  Future<PackageInfo>? _packageInfoFuture;
  Future<void>? _journalInitialization;
  IOSink? _journalSink;
  File? _journalFile;
  String? _journalError;
  String _sessionId = 'uninitialized';
  String _currentRoute = 'startup';
  final Map<String, _ScrollSession> _activeScrolls = <String, _ScrollSession>{};
  int _sequence = 0;
  int _spanSequence = 0;
  final Map<String, DiagnosticSpan> _activeSpans = <String, DiagnosticSpan>{};
  int _journalEventCount = 0;
  int _journalQueuedCount = 0;
  int _journalPersistedCount = 0;
  int _journalDroppedCount = 0;
  int _recordingPauseCount = 0;
  int _recordCostSamples = 0;
  int _recordCostTotalUs = 0;
  int _recordCostMaxUs = 0;
  int _journalDrainBatches = 0;
  int _journalDrainTotalUs = 0;
  int _journalDrainMaxUs = 0;
  int _frameCount = 0;
  int _slowFrames = 0;
  int _verySlowFrames = 0;
  int _scrollUpdates = 0;
  int _scrollSessions = 0;
  int _pointerMoves = 0;
  int _pointerSessions = 0;
  int _routeChanges = 0;
  int _artworkLoadsStarted = 0;
  int _artworkLoadsCompleted = 0;
  int _artworkLoadsFailed = 0;
  int _artworkMemoryHits = 0;
  int _artworkMemoryMisses = 0;
  int _artworkDiskHits = 0;
  int _artworkDiskMisses = 0;
  int _artworkGateRejected = 0;
  int _artworkFirstFramesVisible = 0;
  int _artworkVisibleTotalUs = 0;
  int _artworkVisibleMaxUs = 0;
  int _libraryQuerySpans = 0;
  int _libraryTransformSpans = 0;
  int _playbackActionEvents = 0;
  int _diagnosticErrorEvents = 0;
  int _maxFrameMicros = 0;
  int _totalFrameMicros = 0;
  int _totalBuildMicros = 0;
  int _totalRasterMicros = 0;
  int _totalVsyncMicros = 0;
  double _refreshRateHz = 60;
  int _lastFrameElapsedMicros = 0;
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  bool Function(Object, StackTrace)? _previousPlatformErrorHandler;

  bool get recording => _recording;
  bool get deepInvestigation => _deepInvestigation;
  bool get journalReady => _journalReady;
  String get sessionId => _sessionId;
  String? get journalPath => _journalFile?.path;
  String? get journalError => _journalError;
  int get frameCount => _frameCount;
  int get slowFrames => _slowFrames;
  int get verySlowFrames => _verySlowFrames;
  int get scrollUpdates => _scrollUpdates;
  int get scrollSessions => _scrollSessions;
  int get pointerMoves => _pointerMoves;
  int get pointerSessions => _pointerSessions;
  int get routeChanges => _routeChanges;
  int get artworkLoadsStarted => _artworkLoadsStarted;
  int get artworkLoadsCompleted => _artworkLoadsCompleted;
  int get artworkLoadsFailed => _artworkLoadsFailed;
  int get artworkMemoryHits => _artworkMemoryHits;
  int get artworkMemoryMisses => _artworkMemoryMisses;
  int get artworkDiskHits => _artworkDiskHits;
  int get artworkDiskMisses => _artworkDiskMisses;
  int get artworkGateRejected => _artworkGateRejected;
  int get artworkFirstFramesVisible => _artworkFirstFramesVisible;
  double get averageArtworkTimeToVisibleMs =>
      _artworkFirstFramesVisible == 0
          ? 0
          : _artworkVisibleTotalUs / _artworkFirstFramesVisible / 1000;
  int get maxArtworkTimeToVisibleMs => _artworkVisibleMaxUs ~/ 1000;
  int get libraryQuerySpans => _libraryQuerySpans;
  int get libraryTransformSpans => _libraryTransformSpans;
  int get playbackActionEvents => _playbackActionEvents;
  int get diagnosticErrorEvents => _diagnosticErrorEvents;
  int get activeSpanCount => _activeSpans.length;
  int get retainedEventCount => _events.length;
  int get totalJournalEvents => _journalEventCount;
  int get journalDroppedEvents => _journalDroppedCount;
  int get journalPendingCount => _pendingJournalLines.length;
  double get averageSampledRecordCostUs =>
      _recordCostSamples == 0 ? 0 : _recordCostTotalUs / _recordCostSamples;
  int get maxSampledRecordCostUs => _recordCostMaxUs;
  double get averageJournalDrainCostUs =>
      _journalDrainBatches == 0
          ? 0
          : _journalDrainTotalUs / _journalDrainBatches;
  int get maxJournalDrainCostUs => _journalDrainMaxUs;
  int get sessionMilliseconds => _sessionClock.elapsedMilliseconds;
  int get elapsedMicroseconds => _sessionClock.elapsedMicroseconds;
  double get refreshRateHz => _refreshRateHz;
  double get frameBudgetMs =>
      1000 / (_refreshRateHz <= 0 ? 60 : _refreshRateHz);
  double get averageFrameMs =>
      _frameCount == 0 ? 0 : _totalFrameMicros / _frameCount / 1000;
  double get averageBuildMs =>
      _frameCount == 0 ? 0 : _totalBuildMicros / _frameCount / 1000;
  double get averageRasterMs =>
      _frameCount == 0 ? 0 : _totalRasterMicros / _frameCount / 1000;
  double get averageVsyncMs =>
      _frameCount == 0 ? 0 : _totalVsyncMicros / _frameCount / 1000;
  double get estimatedFps => averageFrameMs <= 0 ? 0 : 1000 / averageFrameMs;
  int get p50FrameMs =>
      _percentile(_recentFrameMicros.toList(growable: false), .50) ~/ 1000;
  int get p90FrameMs =>
      _percentile(_recentFrameMicros.toList(growable: false), .90) ~/ 1000;
  int get p95FrameMs =>
      _percentile(_recentFrameMicros.toList(growable: false), .95) ~/ 1000;
  int get p99FrameMs =>
      _percentile(_recentFrameMicros.toList(growable: false), .99) ~/ 1000;
  Map<String, Object?>? get latestResourceSnapshot =>
      _resourceSnapshots.isEmpty ? null : _resourceSnapshots.last;

  void start() {
    if (_started) return;
    _started = true;
    _sessionId =
        'yazen-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}';
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lifecycleObserver.onState = lifecycleChanged;

    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      _previousFlutterErrorHandler?.call(details);
      if (_previousFlutterErrorHandler == null)
        FlutterError.presentError(details);
      record('flutter_error', <String, Object?>{
        'exception': details.exceptionAsString(),
        'library': details.library,
        'context': details.context?.toDescription(),
        'stack': details.stack?.toString(),
      });
    };
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record('uncaught_async_error', <String, Object?>{
        'error': error.toString(),
        'stack': stack.toString(),
      });
      return _previousPlatformErrorHandler?.call(error, stack) ?? false;
    };

    record('session_start', <String, Object?>{
      'sessionId': _sessionId,
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'debugMode': kDebugMode,
      'profileMode': kProfileMode,
      'releaseMode': kReleaseMode,
      'captureMode': 'hybrid',
      'dashboardEventLimit': _dashboardEventLimit,
    });
    _journalInitialization = _initializeJournal();
    unawaited(_journalInitialization!);
    unawaited(_capturePeriodicResourceSnapshot());
    _startResourceTimer();
    _journalTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_drainJournal());
    });
  }

  void _startResourceTimer() {
    _resourceTimer?.cancel();
    _resourceTimer = Timer.periodic(
      Duration(seconds: _deepInvestigation ? 1 : 5),
      (_) {
        if (_recording) unawaited(_capturePeriodicResourceSnapshot());
      },
    );
  }

  Future<void> _initializeJournal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDirectory = Directory(
        '${directory.path}/yazen_performance_sessions',
      );
      await sessionDirectory.create(recursive: true);
      final file = File('${sessionDirectory.path}/$_sessionId.jsonl');
      _journalSink = file.openWrite(mode: FileMode.append);
      _journalFile = file;
      _journalReady = true;
      record('journal_ready', <String, Object?>{'path': file.path});
      await _drainJournal();
    } catch (error, stack) {
      _journalError = '$error';
      record('journal_initialization_failed', <String, Object?>{
        'error': '$error',
        'stack': '$stack',
      });
    }
  }

  void setRecording(bool value) {
    if (_recording == value) return;
    if (value) {
      _recording = true;
      record('recording_resumed');
      unawaited(_capturePeriodicResourceSnapshot());
    } else {
      record('recording_paused');
      _recordingPauseCount++;
      _recording = false;
      unawaited(_drainJournal());
    }
  }

  void setDeepInvestigation(bool value) {
    if (_deepInvestigation == value) return;
    _deepInvestigation = value;
    if (kDebugMode || kProfileMode) {
      debugProfileBuildsEnabled = value;
      debugProfileBuildsEnabledUserWidgets = value;
      debugProfileLayoutsEnabled = value;
      debugProfilePaintsEnabled = value;
    }
    record(
      value ? 'deep_investigation_started' : 'deep_investigation_stopped',
      <String, Object?>{
        'mode': value ? 'maximum_investigation' : 'hybrid_lightweight',
        'widgetBuildLayoutPaintTimelineProfiling':
            (kDebugMode || kProfileMode) && value,
      },
    );
    _startResourceTimer();
    if (value) unawaited(_capturePeriodicResourceSnapshot());
  }

  void record(
    String type, [
    Map<String, Object?> data = const <String, Object?>{},
    String? traceId,
    String? spanId,
    String? parentSpanId,
  ]) {
    if (!_recording && type != 'recording_resumed') return;
    final sequence = ++_sequence;
    final costClock = sequence % 64 == 0 ? (Stopwatch()..start()) : null;
    switch (type) {
      case 'artwork_load_start':
        _artworkLoadsStarted++;
        break;
      case 'artwork_load_complete':
        _artworkLoadsCompleted++;
        break;
      case 'artwork_load_failed':
        _artworkLoadsFailed++;
        _diagnosticErrorEvents++;
        break;
      case 'artwork_memory_cache_hit':
        _artworkMemoryHits++;
        break;
      case 'artwork_memory_cache_miss':
        _artworkMemoryMisses++;
        break;
      case 'artwork_disk_cache_hit':
        _artworkDiskHits++;
        break;
      case 'artwork_disk_cache_miss':
        _artworkDiskMisses++;
        break;
      case 'artwork_gate_wait_rejected':
        _artworkGateRejected++;
        break;
      case 'artwork_first_frame_visible':
        _artworkFirstFramesVisible++;
        final visibleUs = data['timeToFirstVisibleFrameUs'];
        if (visibleUs is num) {
          _artworkVisibleTotalUs += visibleUs.toInt();
          if (visibleUs > _artworkVisibleMaxUs)
            _artworkVisibleMaxUs = visibleUs.toInt();
        }
        break;
      case 'flutter_error':
      case 'uncaught_async_error':
        _diagnosticErrorEvents++;
        break;
    }
    if (type.startsWith('media_query_') && type.endsWith('_start'))
      _libraryQuerySpans++;
    if ((type.startsWith('library_') ||
            type.startsWith('media_song_model_mapping') ||
            type.startsWith('media_video_dart_mapping')) &&
        type.endsWith('_start'))
      _libraryTransformSpans++;
    if (type.startsWith('playback_') ||
        type.startsWith('audio_handler_') ||
        type.startsWith('sleep_timer_') ||
        type.startsWith('equalizer_') ||
        type == 'audio_interruption')
      _playbackActionEvents++;
    if (type.endsWith('_failed') && type != 'artwork_load_failed')
      _diagnosticErrorEvents++;
    final elapsedMicros = _sessionClock.elapsedMicroseconds;
    final event = <String, Object?>{
      'schemaVersion': 2,
      'eventId': 'evt_${sequence.toString().padLeft(9, '0')}',
      'sequence': sequence,
      'sessionId': _sessionId,
      'timestampUtc': DateTime.now().toUtc().toIso8601String(),
      'elapsedUs': elapsedMicros,
      'elapsedMs': elapsedMicros / 1000,
      'route': _currentRoute,
      'type': type,
      if (traceId != null) 'traceId': traceId,
      if (spanId != null) 'spanId': spanId,
      if (parentSpanId != null) 'parentSpanId': parentSpanId,
      'data': data,
    };
    if (_events.length >= _dashboardEventLimit) _events.removeFirst();
    _events.addLast(event);
    _journalEventCount++;
    if (_pendingJournalLines.length >= _pendingJournalLimit) {
      _journalDroppedCount++;
    } else {
      try {
        _pendingJournalLines.addLast(jsonEncode(event));
        _journalQueuedCount++;
      } catch (error) {
        _journalDroppedCount++;
        _journalError ??= 'Event serialization failed: $error';
      }
    }
    if (_pendingJournalLines.length >= 256) unawaited(_drainJournal());
    if (costClock != null) {
      costClock.stop();
      final elapsed = costClock.elapsedMicroseconds;
      _recordCostSamples++;
      _recordCostTotalUs += elapsed;
      if (elapsed > _recordCostMaxUs) _recordCostMaxUs = elapsed;
    }
  }

  Future<void> _drainJournal({bool force = false, int maxLines = 512}) async {
    if (_journalDraining ||
        (_journalSnapshotting && !force) ||
        _journalSink == null ||
        _pendingJournalLines.isEmpty)
      return;
    _journalDraining = true;
    final drainClock = Stopwatch()..start();
    var drained = 0;
    try {
      while (_pendingJournalLines.isNotEmpty && drained < maxLines) {
        _journalSink!.writeln(_pendingJournalLines.removeFirst());
        drained++;
      }
      await _journalSink!.flush();
      _journalPersistedCount += drained;
    } catch (error) {
      _journalError = '$error';
      // Be conservative: an I/O exception may have interrupted a partial batch.
      _journalDroppedCount += drained + _pendingJournalLines.length;
      _pendingJournalLines.clear();
    } finally {
      drainClock.stop();
      if (drained > 0) {
        _journalDrainBatches++;
        _journalDrainTotalUs += drainClock.elapsedMicroseconds;
        if (drainClock.elapsedMicroseconds > _journalDrainMaxUs)
          _journalDrainMaxUs = drainClock.elapsedMicroseconds;
      }
      _journalDraining = false;
    }
  }

  Future<void> _flushAllJournal() async {
    if (_journalSnapshotting) return;
    while (_pendingJournalLines.isNotEmpty && _journalSink != null) {
      if (_journalDraining) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        continue;
      }
      final pendingBeforeDrain = _pendingJournalLines.length;
      await _drainJournal(force: true);
      if (_pendingJournalLines.length >= pendingBeforeDrain &&
          _journalError != null)
        break;
    }
    await _journalSink?.flush();
  }

  DiagnosticSpan startSpan(
    String operation, {
    String? traceId,
    String? parentSpanId,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _spanSequence++;
    final resolvedTraceId =
        traceId ?? 'trace_${_spanSequence.toString().padLeft(8, '0')}';
    final span = DiagnosticSpan(
      traceId: resolvedTraceId,
      spanId: 'span_${_spanSequence.toString().padLeft(8, '0')}',
      parentSpanId: parentSpanId,
      operation: operation,
      startUs: _sessionClock.elapsedMicroseconds,
    );
    _activeSpans[span.spanId] = span;
    record(
      '${operation}_start',
      data,
      span.traceId,
      span.spanId,
      span.parentSpanId,
    );
    return span;
  }

  void endSpan(
    DiagnosticSpan span,
    String outcome, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    final durationUs = _sessionClock.elapsedMicroseconds - span.startUs;
    _activeSpans.remove(span.spanId);
    record(
      '${span.operation}_$outcome',
      <String, Object?>{
        ...data,
        'durationUs': durationUs,
        'durationMs': durationUs / 1000,
      },
      span.traceId,
      span.spanId,
      span.parentSpanId,
    );
  }

  void routeChanged(String route, {required String action}) {
    if (!_recording) return;
    final previous = _currentRoute;
    _currentRoute = route;
    _routeChanges++;
    record('navigation_$action', <String, Object?>{
      'routeName': route,
      'previousRoute': previous,
    });
  }

  void scrollStarted({
    required String axis,
    required double pixels,
    int depth = 0,
    Duration? sourceTimeStamp,
  }) {
    if (!_recording) return;
    _scrollSessions++;
    final key = '$axis:$depth';
    final traceId =
        'trace_scroll_${_scrollSessions.toString().padLeft(6, '0')}';
    final now = _sessionClock.elapsedMicroseconds;
    _activeScrolls[key] = _ScrollSession(
      traceId: traceId,
      startUs: now,
      lastUs: now,
      lastPixels: pixels,
      lastEventTimestamp: sourceTimeStamp,
    );
    record('scroll_start', <String, Object?>{
      'axis': axis,
      'depth': depth,
      'pixels': pixels,
      'sourceTimeStampUs': sourceTimeStamp?.inMicroseconds,
    }, traceId);
  }

  void scrollUpdated({
    required String axis,
    required int depth,
    required double? delta,
    required double pixels,
    required double maxExtent,
    Duration? sourceTimeStamp,
  }) {
    if (!_recording) return;
    _scrollUpdates++;
    final now = _sessionClock.elapsedMicroseconds;
    final session = _activeScrolls['$axis:$depth'];
    final captureIntervalUs = session == null ? null : now - session.lastUs;
    final eventIntervalUs =
        session == null
            ? null
            : _positiveTimestampDeltaUs(
              session.lastEventTimestamp,
              sourceTimeStamp,
            );
    final pixelDelta = session == null ? null : pixels - session.lastPixels;
    final velocity =
        pixelDelta == null
            ? null
            : calculateEventVelocity(
              delta: pixelDelta,
              previousTimestamp: session?.lastEventTimestamp,
              currentTimestamp: sourceTimeStamp,
            );
    if (session != null) {
      session.lastUs = now;
      session.lastPixels = pixels;
      // A missing source timestamp breaks the velocity chain. Never bridge a
      // ballistic/programmatic update with a later drag sample.
      session.lastEventTimestamp = sourceTimeStamp;
    }
    record('scroll_update', <String, Object?>{
      'axis': axis,
      'depth': depth,
      'delta': delta,
      'pixels': pixels,
      'maxExtent': maxExtent,
      'velocityPixelsPerSecond': velocity,
      'velocitySource':
          velocity == null ? 'unavailable' : 'scroll_drag_event_timestamp',
      // intervalUs now matches the timestamp used for velocity. The callback
      // clock is retained separately for diagnostics, not used as finger speed.
      'intervalUs': eventIntervalUs,
      'captureIntervalUs': captureIntervalUs,
      'sourceTimeStampUs': sourceTimeStamp?.inMicroseconds,
      'startToFirstUpdateUs':
          session != null && session.moveCount == 0
              ? now - session.startUs
              : null,
    }, session?.traceId);
    if (session != null) session.moveCount++;
  }

  @visibleForTesting
  static double? calculateEventVelocity({
    required double delta,
    required Duration? previousTimestamp,
    required Duration? currentTimestamp,
  }) {
    final intervalUs = _positiveTimestampDeltaUs(
      previousTimestamp,
      currentTimestamp,
    );
    if (intervalUs == null) return null;
    return delta * 1000000 / intervalUs;
  }

  static int? _positiveTimestampDeltaUs(
    Duration? previousTimestamp,
    Duration? currentTimestamp,
  ) {
    if (previousTimestamp == null || currentTimestamp == null) return null;
    final intervalUs =
        currentTimestamp.inMicroseconds - previousTimestamp.inMicroseconds;
    return intervalUs > 0 ? intervalUs : null;
  }

  void scrollEnded({
    required String axis,
    required int depth,
    required double pixels,
    required double maxExtent,
  }) {
    if (!_recording) return;
    final session = _activeScrolls.remove('$axis:$depth');
    record('scroll_end', <String, Object?>{
      'axis': axis,
      'depth': depth,
      'pixels': pixels,
      'maxExtent': maxExtent,
      'updateCount': session?.moveCount,
      'durationUs':
          session == null
              ? null
              : _sessionClock.elapsedMicroseconds - session.startUs,
    }, session?.traceId);
  }

  void pointerDown(PointerEvent event) {
    if (!_recording) return;
    _pointerSessions++;
    final now = _sessionClock.elapsedMicroseconds;
    final session = _PointerSession(
      traceId: 'trace_pointer_${_pointerSessions.toString().padLeft(6, '0')}',
      startUs: now,
      lastUs: now,
      lastX: event.position.dx,
      lastY: event.position.dy,
      lastEventTimestamp: event.timeStamp,
    );
    _activePointers[event.pointer] = session;
    record('pointer_down', _pointerData(event, session), session.traceId);
  }

  void pointerMove(PointerEvent event) {
    if (!_recording) return;
    final session = _activePointers[event.pointer];
    if (session == null) return;
    final now = _sessionClock.elapsedMicroseconds;
    final captureIntervalUs = now - session.lastUs;
    final eventIntervalUs = _positiveTimestampDeltaUs(
      session.lastEventTimestamp,
      event.timeStamp,
    );
    final dx = event.position.dx - session.lastX;
    final dy = event.position.dy - session.lastY;
    session.moveCount++;
    _pointerMoves++;
    record('pointer_move', <String, Object?>{
      ..._pointerData(event, session),
      'deltaX': dx,
      'deltaY': dy,
      'distanceDelta': math.sqrt(dx * dx + dy * dy),
      // Use the timestamp supplied by the pointer event, not the time at
      // which the app happened to process it. Android may batch/coalesce input.
      'intervalUs': eventIntervalUs,
      'captureIntervalUs': captureIntervalUs,
      'velocitySource':
          eventIntervalUs == null ? 'unavailable' : 'pointer_event_timestamp',
      'velocityXPerSecond':
          eventIntervalUs == null ? null : dx * 1000000 / eventIntervalUs,
      'velocityYPerSecond':
          eventIntervalUs == null ? null : dy * 1000000 / eventIntervalUs,
      'totalDurationUs': now - session.startUs,
      'moveIndex': session.moveCount,
    }, session.traceId);
    session.lastUs = now;
    session.lastEventTimestamp = event.timeStamp;
    session.lastX = event.position.dx;
    session.lastY = event.position.dy;
  }

  void pointerSignal(PointerSignalEvent event) {
    if (!_recording) return;
    final data = <String, Object?>{
      'kind': event.runtimeType.toString(),
      'x': event.position.dx,
      'y': event.position.dy,
    };
    if (event is PointerScrollEvent) {
      data['scrollDeltaX'] = event.scrollDelta.dx;
      data['scrollDeltaY'] = event.scrollDelta.dy;
    }
    record('pointer_signal', data);
  }

  void pointerUp(PointerEvent event) => _finishPointer('pointer_up', event);
  void pointerCancel(PointerEvent event) =>
      _finishPointer('pointer_cancel', event);

  void _finishPointer(String type, PointerEvent event) {
    if (!_recording) return;
    final session = _activePointers.remove(event.pointer);
    if (session == null) return;
    record(type, <String, Object?>{
      ..._pointerData(event, session),
      'moveCount': session.moveCount,
      'durationUs': _sessionClock.elapsedMicroseconds - session.startUs,
    }, session.traceId);
  }

  Map<String, Object?> _pointerData(
    PointerEvent event,
    _PointerSession session,
  ) => <String, Object?>{
    'pointer': event.pointer,
    'kind': event.kind.name,
    'x': event.position.dx,
    'y': event.position.dy,
    'localX': event.localPosition.dx,
    'localY': event.localPosition.dy,
    'buttons': event.buttons,
    'pressure': event.pressure,
    // This is Flutter's pointer-event timestamp, not a raw hardware sensor
    // clock. Keep the legacy key for older report readers during migration.
    'pointerEventTimestampUs': event.timeStamp.inMicroseconds,
    'deviceTimestampUs': event.timeStamp.inMicroseconds,
    'timestampClock': 'flutter_pointer_event',
    'captureElapsedUs': _sessionClock.elapsedMicroseconds,
    'sessionDurationUs': _sessionClock.elapsedMicroseconds - session.startUs,
  };

  void lifecycleChanged(AppLifecycleState state) {
    record('lifecycle', <String, Object?>{'state': state.name});
    if (state == AppLifecycleState.detached) {
      record('session_end', <String, Object?>{'reason': 'app_detached'});
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_flushAllJournal());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_capturePeriodicResourceSnapshot());
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_recording) return;
    for (final timing in timings) {
      final total = timing.totalSpan.inMicroseconds;
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final vsync = timing.vsyncOverhead.inMicroseconds;
      final budgetUs =
          (1000000 / (_refreshRateHz <= 0 ? 60 : _refreshRateHz)).round();
      _frameCount++;
      _totalFrameMicros += total;
      _totalBuildMicros += build;
      _totalRasterMicros += raster;
      _totalVsyncMicros += vsync;
      if (total > _maxFrameMicros) _maxFrameMicros = total;
      if (total > budgetUs) _slowFrames++;
      if (total > budgetUs * 2) _verySlowFrames++;
      _recentFrameMicros.addLast(total);
      if (_recentFrameMicros.length > _recentFrameLimit)
        _recentFrameMicros.removeFirst();
      final elapsed = _sessionClock.elapsedMicroseconds;
      final gap =
          _lastFrameElapsedMicros == 0
              ? null
              : elapsed - _lastFrameElapsedMicros;
      _lastFrameElapsedMicros = elapsed;
      // Every Flutter frame is journaled; slow frames are not the only useful evidence.
      record('frame_timing', <String, Object?>{
        'frameNumber': _frameCount,
        'totalUs': total,
        'buildUs': build,
        'rasterUs': raster,
        'vsyncOverheadUs': vsync,
        'frameBudgetUs': budgetUs,
        'refreshRateHz': _refreshRateHz,
        'overBudget': total > budgetUs,
        'severelyOverBudget': total > budgetUs * 2,
        'intervalSincePreviousFrameUs': gap,
        'activeSpans': _activeSpans.values
            .map(
              (span) => <String, Object?>{
                'traceId': span.traceId,
                'spanId': span.spanId,
                'operation': span.operation,
              },
            )
            .toList(growable: false),
        'activeScrollTraceIds': _activeScrolls.values
            .map((scroll) => scroll.traceId)
            .toList(growable: false),
        'activePointerTraceIds': _activePointers.values
            .map((pointer) => pointer.traceId)
            .toList(growable: false),
      });
    }
  }

  Future<Map<String, Object?>> _resourceSnapshot({
    bool includeStorage = false,
  }) async {
    Map<String, Object?> native = <String, Object?>{};
    try {
      final result = await _native.invokeMapMethod<String, Object?>(
        'resourceSnapshot',
        <String, Object?>{'includeStorage': includeStorage},
      );
      if (result != null) native = result;
    } catch (error) {
      native = <String, Object?>{'nativeSnapshotError': error.toString()};
    }
    final info = await (_packageInfoFuture ??= PackageInfo.fromPlatform());
    final refresh = native['displayRefreshRateHz'];
    if (refresh is num && refresh > 0) _refreshRateHz = refresh.toDouble();
    return <String, Object?>{
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'elapsedUs': _sessionClock.elapsedMicroseconds,
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
      final snapshot = await _resourceSnapshot();
      if (_resourceSnapshots.length >= 1200) _resourceSnapshots.removeAt(0);
      _resourceSnapshots.add(snapshot);
      record('resource_snapshot', snapshot);
    } catch (error) {
      record('resource_snapshot_failed', <String, Object?>{
        'error': error.toString(),
      });
    } finally {
      _resourceSnapshotInFlight = false;
    }
  }

  List<num> _resourceValues(String key) => _resourceSnapshots
      .map((snapshot) => snapshot['process'])
      .whereType<Map>()
      .map((process) => process[key])
      .whereType<num>()
      .where((value) => value >= 0)
      .toList(growable: false);

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
    'sessionId': _sessionId,
    'sessionDurationUs': _sessionClock.elapsedMicroseconds,
    'captureMode': 'hybrid',
    'deepInvestigationEnabledAtExport': _deepInvestigation,
    'frameCount': _frameCount,
    'refreshRateHz': _refreshRateHz,
    'frameBudgetMs': frameBudgetMs,
    'estimatedFpsFromAverageFrameTime': double.parse(
      estimatedFps.toStringAsFixed(2),
    ),
    'averageFrameMs': double.parse(averageFrameMs.toStringAsFixed(3)),
    'averageBuildMs': double.parse(averageBuildMs.toStringAsFixed(3)),
    'averageRasterMs': double.parse(averageRasterMs.toStringAsFixed(3)),
    'averageVsyncOverheadMs': double.parse(averageVsyncMs.toStringAsFixed(3)),
    'recentFramePercentilesMs': <String, int>{
      'p50': p50FrameMs,
      'p90': p90FrameMs,
      'p95': p95FrameMs,
      'p99': p99FrameMs,
    },
    'maxFrameMs': _maxFrameMicros / 1000,
    'framesOverBudget': _slowFrames,
    'framesOverDoubleBudget': _verySlowFrames,
    'scrollSessions': _scrollSessions,
    'scrollUpdates': _scrollUpdates,
    'pointerSessions': _pointerSessions,
    'pointerMoves': _pointerMoves,
    'navigationChanges': _routeChanges,
    'journalEventsObserved': _journalEventCount,
    'journalEventsQueued': _journalQueuedCount,
    'journalEventsPersisted': _journalPersistedCount,
    'dashboardEventsRetained': _events.length,
    'dashboardEventLimit': _dashboardEventLimit,
    'journalEventsDropped': _journalDroppedCount,
    'recordingPauseCount': _recordingPauseCount,
    'diagnosticsOverhead': <String, Object?>{
      'recordCostSampleEveryNEvents': 64,
      'recordCostSamples': _recordCostSamples,
      'averageSampledRecordCostUs':
          _recordCostSamples == 0 ? 0 : _recordCostTotalUs / _recordCostSamples,
      'maxSampledRecordCostUs': _recordCostMaxUs,
      'journalDrainBatches': _journalDrainBatches,
      'averageJournalDrainCostUs':
          _journalDrainBatches == 0
              ? 0
              : _journalDrainTotalUs / _journalDrainBatches,
      'maxJournalDrainCostUs': _journalDrainMaxUs,
    },
    'journalPending': _pendingJournalLines.length,
    'journalPath': _journalFile?.path,
    'journalError': _journalError,
    'peakProcessPssKb': _maxResourceValue('processPssKb'),
    'peakJavaHeapUsedBytes': _maxResourceValue('javaHeapUsedBytes'),
    'averageProcessCpuPercent': _averageResourceValue(
      'processCpuPercentSincePreviousSnapshot',
    ),
    'resourceSnapshotCount': _resourceSnapshots.length,
    'artworkPipeline': <String, num>{
      'loadsStarted': _artworkLoadsStarted,
      'loadsCompleted': _artworkLoadsCompleted,
      'loadsFailed': _artworkLoadsFailed,
      'memoryHits': _artworkMemoryHits,
      'memoryMisses': _artworkMemoryMisses,
      'diskHits': _artworkDiskHits,
      'diskMisses': _artworkDiskMisses,
      'gateRejected': _artworkGateRejected,
      'firstFramesVisible': _artworkFirstFramesVisible,
      'averageTimeToVisibleMs': averageArtworkTimeToVisibleMs,
      'maxTimeToVisibleMs': maxArtworkTimeToVisibleMs,
    },
    'libraryPipeline': <String, int>{
      'querySpans': _libraryQuerySpans,
      'transformSpans': _libraryTransformSpans,
    },
    'playbackActionEvents': _playbackActionEvents,
    'diagnosticErrorEvents': _diagnosticErrorEvents,
  };

  Future<DiagnosticExport> export() async {
    if (_exportInFlight)
      throw StateError('A diagnostics export is already in progress.');
    _exportInFlight = true;
    File? snapshotFile;
    var snapshotEventCount = 0;
    var snapshotObservedCount = 0;
    var snapshotQueuedCount = 0;
    var snapshotPendingCount = 0;
    var snapshotDroppedCount = 0;
    var snapshotSequence = 0;
    var snapshotPauseCount = 0;
    Map<String, Object?>? summaryAtBoundary;
    try {
      await _journalInitialization;
      await _capturePeriodicResourceSnapshot();
      record('report_export_requested');
      // Freeze the journal boundary while the live session continues collecting
      // later events in a separate bounded queue.
      _journalSnapshotting = true;
      snapshotSequence = _sequence;
      snapshotObservedCount = _journalEventCount;
      snapshotQueuedCount = _journalQueuedCount;
      snapshotPendingCount = _pendingJournalLines.length;
      snapshotEventCount = snapshotQueuedCount;
      snapshotDroppedCount = _journalDroppedCount;
      snapshotPauseCount = _recordingPauseCount;
      var pendingAtBoundary = _pendingJournalLines.length;
      summaryAtBoundary = _summary();
      while (_journalDraining) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      pendingAtBoundary = _pendingJournalLines.length;
      while (pendingAtBoundary > 0 && _journalSink != null) {
        final batchSize = pendingAtBoundary < 512 ? pendingAtBoundary : 512;
        await _drainJournal(force: true, maxLines: batchSize);
        pendingAtBoundary -= batchSize;
      }
      await _journalSink?.flush();
      snapshotEventCount = _journalPersistedCount;
      snapshotDroppedCount = _journalDroppedCount;
      if (_journalFile != null && await _journalFile!.exists()) {
        final stampForSnapshot = DateTime.now()
            .toUtc()
            .toIso8601String()
            .replaceAll(':', '-');
        final candidate = File(
          '${_journalFile!.parent.path}/$_sessionId-export-$stampForSnapshot.jsonl',
        );
        try {
          await _journalFile!.copy(candidate.path);
          snapshotFile = candidate;
        } catch (error) {
          _journalError = 'Journal snapshot copy failed: $error';
        }
      }
      // The immutable export copy is ready; resume appending to the live journal
      // before performing the more expensive full-file analysis/export work.
      _journalSnapshotting = false;
      unawaited(_flushAllJournal());

      final resources = await _resourceSnapshot(includeStorage: true);
      final summary = summaryAtBoundary;
      summary['journalEventsObserved'] = snapshotObservedCount;
      summary['journalEventsQueued'] = snapshotQueuedCount;
      summary['journalEventsPersisted'] = snapshotEventCount;
      summary['journalEventsDropped'] = snapshotDroppedCount;
      summary['recordingPauseCount'] = snapshotPauseCount;
      summary['journalPendingAtExportBoundary'] = snapshotPendingCount;
      summary['journalError'] = _journalError;
      summary['exportBoundarySequence'] = snapshotSequence;
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final analysis =
          snapshotFile == null
              ? <String, Object?>{
                'status': 'journal_snapshot_unavailable',
                'error': _journalError ?? 'No journal file was created.',
              }
              : await _buildAnalysisFromJournal(snapshotFile);
      final metadata = <String, Object?>{
        'schemaVersion': 2,
        'product': 'YAZEN Performance Intelligence',
        'sessionId': _sessionId,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'exportBoundarySequence': snapshotSequence,
        'summary': summary,
        'finalResourceSnapshot': resources,
        'resourceSnapshotCountInJournal':
            analysis['eventTypeCounts'] is Map
                ? ((analysis['eventTypeCounts'] as Map)['resource_snapshot'] ??
                    0)
                : 0,
        'journal': <String, Object?>{
          'format': 'JSONL',
          'file':
              snapshotFile?.uri.pathSegments.isNotEmpty == true
                  ? snapshotFile!.uri.pathSegments.last
                  : null,
          'eventsObserved': snapshotObservedCount,
          'eventsQueued': snapshotQueuedCount,
          'eventsPersisted': snapshotEventCount,
          'droppedEvents': snapshotDroppedCount,
          'completeFromSessionStart':
              _journalReady &&
              snapshotDroppedCount == 0 &&
              _journalError == null &&
              snapshotFile != null &&
              snapshotPauseCount == 0 &&
              analysis['eventsRead'] == snapshotEventCount &&
              analysis['missingSequenceNumbers'] == 0 &&
              analysis['outOfOrderEvents'] == 0 &&
              analysis['malformedLines'] == 0,
          'boundarySequence': snapshotSequence,
        },
        'analysis': analysis,
        'notes': <String>[
          'The JSONL journal is the complete ordered event stream through exportBoundarySequence, including every resource snapshot; the dashboard event cache is intentionally bounded.',
          'Events occurring after the export boundary remain in the live journal and are not part of this export snapshot.',
          'A manually paused recording creates a known gap and prevents the export from being labeled complete from session start.',
          'Frame timings are Flutter engine timings. Refresh-rate thresholds are based on the latest native display snapshot.',
          'Pointer movement events are captured while a pointer is down; hover movement is not captured.',
          'CPU and native memory are sampled point-in-time metrics, not per-widget attribution.',
          'Correlations indicate temporal relationships, not proof of causation.',
        ],
      };
      final jsonText = const JsonEncoder.withIndent('  ').convert(metadata);
      final markdown = _buildMarkdownReport(metadata);
      final files = <String, String>{
        'yazen-pi-session-$stamp.json': jsonText,
        'yazen-pi-session-$stamp.md': markdown,
      };
      final saved = <String>[];
      try {
        final nativeResult = await _native.invokeListMethod<String>(
          'saveDiagnosticFiles',
          files,
        );
        if (nativeResult != null) saved.addAll(nativeResult);
      } catch (_) {
        final directory = await getApplicationDocumentsDirectory();
        for (final entry in files.entries) {
          final file = File('${directory.path}/${entry.key}');
          await file.writeAsString(entry.value, flush: true);
          saved.add(file.path);
        }
      }
      if (snapshotFile != null) {
        try {
          final journalResult = await _native
              .invokeMethod<String>('exportDiagnosticJournal', <String, String>{
                'sourcePath': snapshotFile.path,
                'fileName': 'yazen-pi-session-$stamp.jsonl',
              });
          if (journalResult != null) saved.add(journalResult);
          await snapshotFile.delete();
        } catch (error) {
          saved.add(
            'Journal snapshot remains in app documents: ${snapshotFile.path} (Downloads copy failed: $error)',
          );
        }
      } else {
        saved.add(
          'Full journal snapshot unavailable. Check journal initialization/error status in the JSON report.',
        );
      }
      record('report_export_completed', <String, Object?>{
        'files': saved,
        'exportBoundarySequence': snapshotSequence,
      });
      return DiagnosticExport(
        paths: saved,
        eventCount: snapshotEventCount,
        summary: summary,
      );
    } finally {
      _journalSnapshotting = false;
      _exportInFlight = false;
      await _flushAllJournal();
    }
  }

  Future<Map<String, Object?>> _buildAnalysisFromJournal(File? journal) async {
    final eventTypeCounts = <String, int>{};
    final overBudgetByRoute = <String, int>{};
    final activeSpanFrameCounts = <String, int>{};
    final operationDurations = <String, List<int>>{};
    final frameDurations = <int>[];
    final scrollVelocities = <double>[];
    final pointerVelocities = <double>[];
    final resourceValues = <String, List<num>>{};
    final threadCpuTickTotals = <String, int>{};
    final scrollDurationsUs = <int>[];
    var totalEventsRead = 0;
    var overBudgetFrames = 0;
    var severeFrames = 0;
    var pointerMoveSamples = 0;
    var scrollUpdateSamples = 0;
    var malformedLines = 0;
    var missingSequenceNumbers = 0;
    var outOfOrderEvents = 0;
    int? previousSequence;

    if (journal != null && await journal.exists()) {
      try {
        await for (final line in journal
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (line.trim().isEmpty) continue;
          try {
            final decoded = jsonDecode(line);
            if (decoded is! Map) continue;
            totalEventsRead++;
            final sequence = decoded['sequence'];
            if (sequence is num) {
              final currentSequence = sequence.toInt();
              if (previousSequence != null &&
                  currentSequence > previousSequence + 1) {
                missingSequenceNumbers +=
                    currentSequence - previousSequence - 1;
              } else if (previousSequence != null &&
                  currentSequence <= previousSequence) {
                outOfOrderEvents++;
              }
              previousSequence = currentSequence;
            }
            final type = decoded['type']?.toString() ?? 'unknown';
            eventTypeCounts[type] = (eventTypeCounts[type] ?? 0) + 1;
            final route = decoded['route']?.toString() ?? 'unknown';
            final data =
                decoded['data'] is Map
                    ? (decoded['data'] as Map).cast<String, Object?>()
                    : const <String, Object?>{};
            if (type == 'frame_timing') {
              final totalUs = data['totalUs'];
              if (totalUs is num) frameDurations.add(totalUs.round());
              if (data['overBudget'] == true) {
                overBudgetFrames++;
                final activeScrolls = data['activeScrollTraceIds'];
                if (activeScrolls is List && activeScrolls.isNotEmpty)
                  activeSpanFrameCounts['scroll_gesture'] =
                      (activeSpanFrameCounts['scroll_gesture'] ?? 0) + 1;
                final activePointers = data['activePointerTraceIds'];
                if (activePointers is List && activePointers.isNotEmpty)
                  activeSpanFrameCounts['pointer_gesture'] =
                      (activeSpanFrameCounts['pointer_gesture'] ?? 0) + 1;
                overBudgetByRoute[route] = (overBudgetByRoute[route] ?? 0) + 1;
                final active = data['activeSpans'];
                if (active is List) {
                  for (final span in active.whereType<Map>()) {
                    final operation =
                        span['operation']?.toString() ?? 'unknown';
                    activeSpanFrameCounts[operation] =
                        (activeSpanFrameCounts[operation] ?? 0) + 1;
                  }
                }
              }
              if (data['severelyOverBudget'] == true) severeFrames++;
            } else if (type == 'scroll_update') {
              scrollUpdateSamples++;
              final velocity = data['velocityPixelsPerSecond'];
              if (velocity is num) scrollVelocities.add(velocity.toDouble());
            } else if (type == 'pointer_move') {
              pointerMoveSamples++;
              final vx = data['velocityXPerSecond'];
              final vy = data['velocityYPerSecond'];
              if (vx is num) pointerVelocities.add(vx.abs().toDouble());
              if (vy is num) pointerVelocities.add(vy.abs().toDouble());
            } else if (type == 'scroll_end') {
              final duration = data['durationUs'];
              if (duration is num) scrollDurationsUs.add(duration.round());
            } else if (type == 'resource_snapshot') {
              final process = data['process'];
              if (process is Map) {
                for (final key in <String>[
                  'processPssKb',
                  'processCpuPercentSincePreviousSnapshot',
                  'javaHeapUsedBytes',
                  'nativeHeapAllocatedBytes',
                  'deviceAvailableMemoryBytes',
                ]) {
                  final value = process[key];
                  if (value is num && value >= 0)
                    (resourceValues[key] ??= <num>[]).add(value);
                }
                final threads = process['threadCpuSamples'];
                if (threads is List) {
                  for (final thread in threads.whereType<Map>()) {
                    final name = thread['name']?.toString() ?? 'unknown';
                    final ticks = thread['deltaTicksSincePreviousSnapshot'];
                    if (ticks is num && ticks >= 0)
                      threadCpuTickTotals[name] =
                          (threadCpuTickTotals[name] ?? 0) + ticks.toInt();
                  }
                }
              }
            }
            if (type.endsWith('_complete') ||
                type.endsWith('_failed') ||
                type.endsWith('_rejected') ||
                type.endsWith('_superseded')) {
              final duration = data['durationUs'];
              if (duration is num) {
                final operation = type.substring(0, type.lastIndexOf('_'));
                (operationDurations[operation] ??= <int>[]).add(
                  duration.round(),
                );
              }
            }
          } catch (_) {
            malformedLines++;
          }
        }
      } catch (error) {
        return <String, Object?>{
          'status': 'journal_read_failed',
          'error': '$error',
          'eventTypeCounts': eventTypeCounts,
          'eventsReadBeforeFailure': totalEventsRead,
        };
      }
    }

    final correlated = activeSpanFrameCounts.entries
      .map(
        (entry) => <String, Object?>{
          'operation': entry.key,
          'overBudgetFramesDuringOperation': entry.value,
          'classification': 'correlated_only',
          'confidence': 'medium',
        },
      )
      .toList(growable: false)..sort(
      (a, b) => (b['overBudgetFramesDuringOperation'] as int).compareTo(
        a['overBudgetFramesDuringOperation'] as int,
      ),
    );

    final operationSummary = <String, Object?>{};
    for (final entry in operationDurations.entries) {
      final values = entry.value..sort();
      operationSummary[entry.key] = <String, Object?>{
        'count': values.length,
        'averageDurationMs':
            values.reduce((a, b) => a + b) / values.length / 1000,
        'p95DurationMs': _percentile(values, .95) / 1000,
        'maxDurationMs': values.last / 1000,
      };
    }

    final velocitySummary =
        scrollVelocities.isEmpty
            ? null
            : <String, Object?>{
              'sampleCount': scrollVelocities.length,
              'averageAbsolutePixelsPerSecond':
                  scrollVelocities.map((v) => v.abs()).reduce((a, b) => a + b) /
                  scrollVelocities.length,
              'maxAbsolutePixelsPerSecond': scrollVelocities
                  .map((v) => v.abs())
                  .reduce((a, b) => a > b ? a : b),
            };
    final pointerVelocitySummary =
        pointerVelocities.isEmpty
            ? null
            : <String, Object?>{
              'axisVelocitySamples': pointerVelocities.length,
              'averageAbsolutePixelsPerSecond':
                  pointerVelocities.reduce((a, b) => a + b) /
                  pointerVelocities.length,
              'maxAbsolutePixelsPerSecond': pointerVelocities.reduce(
                (a, b) => a > b ? a : b,
              ),
            };
    final resourceSummary = <String, Object?>{};
    for (final entry in resourceValues.entries) {
      final values = entry.value;
      resourceSummary[entry.key] = <String, Object?>{
        'sampleCount': values.length,
        'average': values.reduce((a, b) => a + b) / values.length,
        'maximum': values.reduce((a, b) => a > b ? a : b),
      };
    }
    final topThreads =
        threadCpuTickTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return <String, Object?>{
      'status':
          journal == null ? 'journal_unavailable' : 'complete_journal_scan',
      'eventsRead': totalEventsRead,
      'malformedLines': malformedLines,
      'missingSequenceNumbers': missingSequenceNumbers,
      'outOfOrderEvents': outOfOrderEvents,
      'eventTypeCounts': eventTypeCounts,
      'frameAnalysis': <String, Object?>{
        'frameSamples': frameDurations.length,
        'overBudgetFrames': overBudgetFrames,
        'severelyOverBudgetFrames': severeFrames,
        'fullSessionPercentilesMs': <String, num>{
          'p50': _percentile(frameDurations, .50) / 1000,
          'p90': _percentile(frameDurations, .90) / 1000,
          'p95': _percentile(frameDurations, .95) / 1000,
          'p99': _percentile(frameDurations, .99) / 1000,
        },
        'overBudgetFramesByRoute': overBudgetByRoute,
      },
      'interactionAnalysis': <String, Object?>{
        'scrollUpdateSamples': scrollUpdateSamples,
        'pointerMoveSamples': pointerMoveSamples,
        'scrollVelocity': velocitySummary,
        'scrollVelocitySource': 'scroll_drag_event_timestamp_only',
        'pointerAxisVelocity': pointerVelocitySummary,
        'pointerVelocitySource': 'flutter_pointer_event_timestamp',
        'scrollGestureDurationMs': <String, Object?>{
          'count': scrollDurationsUs.length,
          'average':
              scrollDurationsUs.isEmpty
                  ? null
                  : scrollDurationsUs.reduce((a, b) => a + b) /
                      scrollDurationsUs.length /
                      1000,
          'maximum':
              scrollDurationsUs.isEmpty
                  ? null
                  : scrollDurationsUs.reduce((a, b) => a > b ? a : b) / 1000,
        },
      },
      'resourceAnalysis': resourceSummary,
      'topThreadsByRawCpuTicks': topThreads
          .take(12)
          .map(
            (entry) => <String, Object?>{
              'name': entry.key,
              'deltaTicks': entry.value,
            },
          )
          .toList(growable: false),
      'operationDurations': operationSummary,
      'activeSpanFrameCorrelations': correlated,
      'classificationPolicy': <String>[
        'observed',
        'correlated',
        'likely_contributor',
        'confirmed',
      ],
      'limitations': <String>[
        'An active span overlapping an over-budget frame is temporal correlation, not proof that the span caused the frame delay.',
        'CPU remains process-level sampled telemetry; per-thread attribution is not yet implemented.',
        'Exact per-widget memory attribution is not generally available from in-app instrumentation.',
        'Only events delivered to Flutter and operations explicitly instrumented by YAZEN can be included.',
        'Pointer velocity uses PointerEvent timestamps; scroll velocity is reported only when drag source timestamps are available. Ballistic and programmatic scroll updates have no velocity estimate.',
      ],
    };
  }

  String _buildMarkdownReport(Map<String, Object?> metadata) {
    final summary = (metadata['summary'] as Map).cast<String, Object?>();
    final analysis = (metadata['analysis'] as Map).cast<String, Object?>();
    final buffer =
        StringBuffer()
          ..writeln('# YAZEN Performance Intelligence — Session Report')
          ..writeln()
          ..writeln('- Session: `${_sessionId}`')
          ..writeln('- Generated: `${metadata['generatedAt']}`')
          ..writeln(
            '- Journal events observed: `${summary['journalEventsObserved']}`',
          )
          ..writeln(
            '- Journal events persisted: `${summary['journalEventsPersisted']}`',
          )
          ..writeln(
            '- Journal events dropped: `${summary['journalEventsDropped']}`',
          )
          ..writeln()
          ..writeln('## Frame performance')
          ..writeln('- Refresh rate: ${summary['refreshRateHz']} Hz')
          ..writeln('- Frame budget: ${summary['frameBudgetMs']} ms')
          ..writeln('- Frames: ${summary['frameCount']}')
          ..writeln('- Average frame: ${summary['averageFrameMs']} ms')
          ..writeln(
            '- Percentiles (recent window): ${summary['recentFramePercentilesMs']}',
          )
          ..writeln('- Over budget: ${summary['framesOverBudget']}')
          ..writeln(
            '- Over double budget: ${summary['framesOverDoubleBudget']}',
          )
          ..writeln()
          ..writeln('## Interaction capture')
          ..writeln('- Scroll sessions: ${summary['scrollSessions']}')
          ..writeln('- Scroll updates: ${summary['scrollUpdates']}')
          ..writeln('- Pointer sessions: ${summary['pointerSessions']}')
          ..writeln('- Pointer move samples: ${summary['pointerMoves']}')
          ..writeln()
          ..writeln('## Resource metrics')
          ..writeln('- Peak PSS: ${summary['peakProcessPssKb']} KB')
          ..writeln(
            '- Peak Java heap: ${summary['peakJavaHeapUsedBytes']} bytes',
          )
          ..writeln(
            '- Average sampled process CPU: ${summary['averageProcessCpuPercent']}%',
          )
          ..writeln()
          ..writeln('## Correlation analysis')
          ..writeln(const JsonEncoder.withIndent('  ').convert(analysis))
          ..writeln()
          ..writeln('## Completeness')
          ..writeln('- Journal ready: $_journalReady')
          ..writeln('- Journal error: ${_journalError ?? 'none'}')
          ..writeln('- Dropped event count: $_journalDroppedCount')
          ..writeln(
            '- The companion JSONL file contains the ordered raw event stream.',
          );
    return buffer.toString();
  }

  static int _percentile(List<int> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.of(values)..sort();
    final index = ((sorted.length - 1) * percentile).ceil().clamp(
      0,
      sorted.length - 1,
    );
    return sorted[index];
  }

  Future<void> dispose() async {
    _resourceTimer?.cancel();
    _journalTimer?.cancel();
    record('session_end', <String, Object?>{'reason': 'service_dispose'});
    await _flushAllJournal();
    await _journalSink?.close();
    _journalSink = null;
  }
}

class DiagnosticSpan {
  const DiagnosticSpan({
    required this.traceId,
    required this.spanId,
    required this.parentSpanId,
    required this.operation,
    required this.startUs,
  });
  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final String operation;
  final int startUs;
}

class _ScrollSession {
  _ScrollSession({
    required this.traceId,
    required this.startUs,
    required this.lastUs,
    required this.lastPixels,
    required this.lastEventTimestamp,
  });
  final String traceId;
  final int startUs;
  int lastUs;
  double lastPixels;
  Duration? lastEventTimestamp;
  int moveCount = 0;
}

class _PointerSession {
  _PointerSession({
    required this.traceId,
    required this.startUs,
    required this.lastUs,
    required this.lastX,
    required this.lastY,
    required this.lastEventTimestamp,
  });
  final String traceId;
  final int startUs;
  int lastUs;
  double lastX;
  double lastY;
  Duration lastEventTimestamp;
  int moveCount = 0;
}

class DiagnosticExport {
  const DiagnosticExport({
    required this.paths,
    required this.eventCount,
    required this.summary,
  });
  final List<String> paths;
  final int eventCount;
  final Map<String, Object?> summary;
}

class _DiagnosticsLifecycleObserver with WidgetsBindingObserver {
  void Function(AppLifecycleState state)? onState;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      onState?.call(state);
}
