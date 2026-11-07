import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/media_track_codec.dart';
import 'package:yazen/services/playback_state_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round-trips local audio and video tracks through the codec', () {
    final tracks = <MediaTrack>[
      MediaTrack(
        id: 'local-1',
        title: 'Local Song',
        artist: 'Artist',
        album: 'Album',
        source: TrackSource.local,
        uri: Uri.parse('file:///music/song.mp3'),
      ),
      MediaTrack(
        id: 'local-video-1',
        title: 'Local Video',
        artist: 'On this device',
        album: 'Local videos',
        source: TrackSource.local,
        kind: MediaKind.video,
        uri: Uri.parse('file:///movies/video.mp4'),
        artworkUri: Uri.parse('content://media/external/video/media/1'),
      ),
    ];

    final decoded =
        tracks.map(mediaTrackToJson).map(mediaTrackFromJson).toList();
    expect(
      decoded.map((track) => track.id).toList(),
      tracks.map((track) => track.id).toList(),
    );
    expect(decoded.last.isVideo, isTrue);
    expect(decoded.last.uri, tracks.last.uri);
  });

  test('stores queue and progress separately and round-trips them', () async {
    const store = PlaybackStateStore();
    final track = MediaTrack(
      id: 'round-trip',
      title: 'Round Trip',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
      uri: Uri.parse('file:///music/round-trip.mp3'),
    );

    await store.save(
      queue: <MediaTrack>[track],
      currentIndex: 0,
      position: const Duration(seconds: 42),
      playing: true,
      repeatMode: 3,
      shuffleMode: 1,
      speed: 1.5,
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(PlaybackStateStore.legacyKey), isNull);
    final queuePayload = jsonDecode(
      preferences.getString(PlaybackStateStore.queueKey)!,
    );
    final progressPayload = jsonDecode(
      preferences.getString(PlaybackStateStore.progressKey)!,
    );
    expect(queuePayload, isA<List>());
    expect((queuePayload as List).single['id'], 'round-trip');
    expect(progressPayload, <String, dynamic>{
      'version': PlaybackStateStore.payloadVersion,
      'currentIndex': 0,
      'positionMs': 42000,
      'playing': true,
      'repeatMode': 3,
      'shuffleMode': 1,
      'speed': 1.5,
    });

    final snapshot = await store.load();
    expect(snapshot!.queue.single.id, 'round-trip');
    expect(snapshot.currentIndex, 0);
    expect(snapshot.position, const Duration(seconds: 42));
    expect(snapshot.playing, isTrue);
    expect(snapshot.repeatMode, 3);
    expect(snapshot.shuffleMode, 1);
    expect(snapshot.speed, 1.5);
  });

  test('migrates a legacy v1 snapshot into both v2 keys', () async {
    final track = MediaTrack(
      id: 'legacy-track',
      title: 'Legacy Track',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
      uri: Uri.parse('file:///music/legacy.mp3'),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      PlaybackStateStore.legacyKey: jsonEncode(<String, dynamic>{
        'queue': <Map<String, dynamic>>[mediaTrackToJson(track)],
        'currentIndex': 99,
        'positionMs': 2 * 24 * 60 * 60 * 1000,
        'playing': true,
        'repeatMode': 99,
        'speed': 99.0,
      }),
    });

    const store = PlaybackStateStore();
    final snapshot = await store.load();
    expect(snapshot, isNotNull);
    expect(snapshot!.queue.single.id, 'legacy-track');
    expect(snapshot.currentIndex, 0);
    expect(snapshot.position, const Duration(days: 1));
    expect(snapshot.playing, isTrue);
    expect(snapshot.repeatMode, 3);
    expect(snapshot.speed, 3.0);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(PlaybackStateStore.queueKey), isNotNull);
    expect(preferences.getString(PlaybackStateStore.progressKey), isNotNull);
    expect(preferences.getString(PlaybackStateStore.legacyKey), isNull);
  });

  test(
    'retries a partially written legacy migration on the next load',
    () async {
      const track = MediaTrack(
        id: 'partial-legacy',
        title: 'Partial Legacy',
        artist: 'Artist',
        album: 'Album',
        source: TrackSource.local,
      );
      final preferences = _ThrowOnProgressWritePreferences(<String, String>{
        PlaybackStateStore.legacyKey: jsonEncode(<String, dynamic>{
          'queue': <Map<String, dynamic>>[mediaTrackToJson(track)],
          'currentIndex': 0,
          'positionMs': 1234,
          'playing': false,
          'repeatMode': 1,
          'speed': 1.0,
        }),
      });
      final store = PlaybackStateStore(
        preferencesLoader: () async => preferences,
      );

      await expectLater(store.load(), throwsA(isA<StateError>()));
      final snapshot = await store.load();

      expect(snapshot, isNotNull);
      expect(snapshot!.queue.single.id, 'partial-legacy');
      expect(snapshot.position, const Duration(milliseconds: 1234));
      expect(preferences.getString(PlaybackStateStore.legacyKey), isNull);
    },
  );

  test('serializes clear after a queued save', () async {
    const store = PlaybackStateStore();
    const track = MediaTrack(
      id: 'clear-track',
      title: 'Clear Track',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
    );

    final save = store.saveQueue(<MediaTrack>[track]);
    final clear = store.clear();
    await Future.wait(<Future<void>>[save, clear]);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(PlaybackStateStore.queueKey), isNull);
    expect(preferences.getString(PlaybackStateStore.progressKey), isNull);
    expect(preferences.getString(PlaybackStateStore.legacyKey), isNull);
  });

  test('continues with a successful save after one operation throws', () async {
    final preferences = _ThrowOncePreferences();
    final store = PlaybackStateStore(
      preferencesLoader: () async => preferences,
    );
    const track = MediaTrack(
      id: 'recovery-track',
      title: 'Recovery Track',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
    );

    await expectLater(
      store.saveQueue(<MediaTrack>[track]),
      throwsA(isA<StateError>()),
    );
    await store.saveQueue(<MediaTrack>[track]);
    expect(preferences.getString(PlaybackStateStore.queueKey), isNotNull);
  });

  test(
    'treats false SharedPreferences results as persistence failures',
    () async {
      final preferences = _FalseResultPreferences();
      final store = PlaybackStateStore(
        preferencesLoader: () async => preferences,
      );
      const track = MediaTrack(
        id: 'false-result-track',
        title: 'False Result Track',
        artist: 'Artist',
        album: 'Album',
        source: TrackSource.local,
      );

      await expectLater(
        store.saveQueue(<MediaTrack>[track]),
        throwsA(isA<StateError>()),
      );
      expect(preferences.values, isEmpty);

      preferences.failWrites = false;
      await store.saveQueue(<MediaTrack>[track]);
      expect(preferences.getString(PlaybackStateStore.queueKey), isNotNull);

      preferences.failWrites = true;
      await expectLater(store.clear(), throwsA(isA<StateError>()));
      expect(preferences.getString(PlaybackStateStore.queueKey), isNotNull);
    },
  );

  test('saves and clamps a playback snapshot', () async {
    const store = PlaybackStateStore();
    final track = MediaTrack(
      id: 'local-1',
      title: 'Local Song',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
      uri: Uri.parse('file:///music/song.mp3'),
    );

    await store.save(
      queue: <MediaTrack>[track],
      currentIndex: 99,
      position: const Duration(days: 2),
      playing: true,
    );

    final snapshot = await store.load();
    expect(snapshot, isNotNull);
    expect(snapshot!.currentIndex, 0);
    expect(snapshot.position, const Duration(days: 1));
    expect(snapshot.playing, isTrue);
    expect(snapshot.shuffleMode, 0);
  });
}

class _ThrowOncePreferences implements PlaybackStatePreferences {
  bool _throw = true;
  final Map<String, String> values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (_throw) {
      _throw = false;
      throw StateError('one storage failure');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }
}

class _FalseResultPreferences implements PlaybackStatePreferences {
  bool failWrites = true;
  final Map<String, String> values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (failWrites) return false;
    values.remove(key);
    return true;
  }
}

class _ThrowOnProgressWritePreferences implements PlaybackStatePreferences {
  _ThrowOnProgressWritePreferences(this.values);

  final Map<String, String> values;
  bool _throw = true;

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (key == PlaybackStateStore.progressKey && _throw) {
      _throw = false;
      throw StateError('one progress migration failure');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }
}
