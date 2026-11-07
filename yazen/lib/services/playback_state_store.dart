import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_track.dart';
import 'media_track_codec.dart';

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.currentIndex,
    required this.position,
    required this.playing,
    this.repeatMode = 0,
    this.shuffleMode = 0,
    this.speed = 1.0,
  });

  final List<MediaTrack> queue;
  final int currentIndex;
  final Duration position;
  final bool playing;
  final int repeatMode;
  final int shuffleMode;
  final double speed;
}

/// The small storage surface used by [PlaybackStateStore].
abstract interface class PlaybackStatePreferences {
  String? getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class _SharedPreferencesAdapter implements PlaybackStatePreferences {
  _SharedPreferencesAdapter(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);
}

class PlaybackStateStore {
  static const payloadVersion = 2;
  static const queueKey = 'echo.playback_queue.v2';
  static const progressKey = 'echo.playback_progress.v2';
  static const legacyKey = 'echo.playback_snapshot.v1';

  static Future<void> _operations = Future<void>.value();

  const PlaybackStateStore({
    Future<PlaybackStatePreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader;

  final Future<PlaybackStatePreferences> Function()? _preferencesLoader;

  Future<PlaybackStatePreferences> _getPreferences() async {
    final loader = _preferencesLoader;
    if (loader != null) return loader();
    return _SharedPreferencesAdapter(await SharedPreferences.getInstance());
  }

  Future<T> _enqueue<T>(
    Future<T> Function(PlaybackStatePreferences preferences) operation,
  ) {
    final result = _operations.then<T>((_) async {
      final preferences = await _getPreferences();
      return operation(preferences);
    });
    // Keep later operations usable after this operation fails, while returning
    // the original future so this operation's error reaches its caller.
    _operations = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  /// Completes when all operations queued before this call have settled.
  Future<void> get idle => _operations;

  Future<void> saveQueue(List<MediaTrack> queue) {
    return _enqueue<void>((preferences) async {
      final payload = queue.map(mediaTrackToJson).toList(growable: false);
      await _setString(preferences, queueKey, jsonEncode(payload));
    });
  }

  Future<void> saveProgress({
    required int currentIndex,
    required Duration position,
    required bool playing,
    int repeatMode = 0,
    int shuffleMode = 0,
    double speed = 1.0,
  }) {
    return _enqueue<void>((preferences) async {
      final payload = <String, dynamic>{
        'version': payloadVersion,
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'playing': playing,
        'repeatMode': repeatMode,
        'shuffleMode': shuffleMode,
        'speed': speed,
      };
      await _setString(preferences, progressKey, jsonEncode(payload));
    });
  }

  Future<void> save({
    required List<MediaTrack> queue,
    required int currentIndex,
    required Duration position,
    required bool playing,
    int repeatMode = 0,
    int shuffleMode = 0,
    double speed = 1.0,
  }) async {
    await _enqueue<void>((preferences) async {
      final queuePayload = queue.map(mediaTrackToJson).toList(growable: false);
      final progressPayload = <String, dynamic>{
        'version': payloadVersion,
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'playing': playing,
        'repeatMode': repeatMode,
        'shuffleMode': shuffleMode,
        'speed': speed,
      };
      await _setString(preferences, queueKey, jsonEncode(queuePayload));
      await _setString(preferences, progressKey, jsonEncode(progressPayload));
    });
  }

  Future<PlaybackSnapshot?> load() async {
    return _enqueue<PlaybackSnapshot?>((preferences) async {
      var queueRaw = preferences.getString(queueKey);
      var progressRaw = preferences.getString(progressKey);

      // Retain the old value until both v2 writes succeed, so a failed
      // migration can be retried without data loss.
      if (queueRaw == null || progressRaw == null) {
        final legacy = _decodeLegacy(preferences.getString(legacyKey));
        if (legacy != null) {
          if (queueRaw == null) {
            await _setString(
              preferences,
              queueKey,
              jsonEncode(
                legacy.queue.map(mediaTrackToJson).toList(growable: false),
              ),
            );
          }
          if (progressRaw == null) {
            await _setString(
              preferences,
              progressKey,
              jsonEncode(<String, dynamic>{
                'version': payloadVersion,
                'currentIndex': legacy.currentIndex,
                'positionMs': legacy.position.inMilliseconds,
                'playing': legacy.playing,
                'repeatMode': legacy.repeatMode,
                'shuffleMode': legacy.shuffleMode,
                'speed': legacy.speed,
              }),
            );
          }
          await _remove(preferences, legacyKey);
          queueRaw ??= preferences.getString(queueKey);
          progressRaw ??= preferences.getString(progressKey);
        }
      }

      final queue = _decodeQueue(queueRaw);
      if (queue == null || queue.isEmpty) return null;
      return _snapshot(queue, _decodeProgress(progressRaw));
    });
  }

  Future<void> clear() async {
    await _enqueue<void>((preferences) async {
      await _remove(preferences, queueKey);
      await _remove(preferences, progressKey);
      await _remove(preferences, legacyKey);
    });
  }

  static Future<void> _setString(
    PlaybackStatePreferences preferences,
    String key,
    String value,
  ) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Failed to persist playback preference: $key');
    }
  }

  static Future<void> _remove(
    PlaybackStatePreferences preferences,
    String key,
  ) async {
    if (!await preferences.remove(key)) {
      throw StateError('Failed to remove playback preference: $key');
    }
  }

  static List<MediaTrack>? _decodeQueue(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final queue = <MediaTrack>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final track = mediaTrackFromJson(Map<String, dynamic>.from(item));
          if (track.id.isNotEmpty) queue.add(track);
        } on Object {
          // Ignore malformed tracks while retaining valid queue entries.
        }
      }
      return List<MediaTrack>.unmodifiable(queue);
    } on Object {
      return null;
    }
  }

  static PlaybackSnapshot? _decodeLegacy(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final queue = _decodeQueue(jsonEncode(decoded['queue']));
      if (queue == null || queue.isEmpty) return null;
      return _snapshot(queue, _decodeProgress(jsonEncode(decoded)));
    } on Object {
      return null;
    }
  }

  static Map<String, dynamic> _decodeProgress(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on Object {
      // Treat malformed progress as defaults while retaining a valid queue.
    }
    return <String, dynamic>{};
  }

  static PlaybackSnapshot _snapshot(
    List<MediaTrack> queue,
    Map<String, dynamic> progress,
  ) {
    final rawIndex = _asInt(progress['currentIndex'], 0);
    final positionMs = _asInt(progress['positionMs'], 0);
    final repeatMode = _asInt(progress['repeatMode'], 0);
    final shuffleMode = _asInt(progress['shuffleMode'], 0);
    final speed = _asDouble(progress['speed'], 1.0);
    return PlaybackSnapshot(
      queue: List<MediaTrack>.unmodifiable(queue),
      currentIndex: rawIndex.clamp(0, queue.length - 1).toInt(),
      position: Duration(
        milliseconds: positionMs.clamp(0, 24 * 60 * 60 * 1000).toInt(),
      ),
      playing: progress['playing'] == true,
      repeatMode: repeatMode.clamp(0, 3).toInt(),
      shuffleMode: shuffleMode.clamp(0, 2).toInt(),
      speed: speed.clamp(0.25, 3.0).toDouble(),
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is num && value.isFinite) return value.toInt();
    return fallback;
  }

  static double _asDouble(dynamic value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    return fallback;
  }
}
