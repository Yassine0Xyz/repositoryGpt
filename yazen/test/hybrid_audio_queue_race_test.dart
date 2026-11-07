import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/controllers/hybrid_music_controller.dart';
import 'package:yazen/core/theme/theme_provider.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/hybrid_audio_handler.dart';
import 'package:yazen/services/local_playlist_manager.dart';
import 'package:yazen/services/media_library_service.dart';
import 'package:yazen/services/playback_state_store.dart';
import 'package:yazen/services/playback_policies.dart';
import 'package:yazen/screens/collections/playlist_details_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'rapid queue operations leave Dart and player sequences consistent',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );

      final tracks = List<MediaTrack>.generate(8, _track);
      await handler.playTrackQueue(tracks.take(4).toList());

      final pending = <Future<void>>[];
      for (var index = 0; index < 48; index++) {
        switch (index % 6) {
          case 0:
            pending.add(handler.addToQueue(tracks[index % tracks.length]));
          case 1:
            pending.add(handler.removeFromQueue(index % 5));
          case 2:
            pending.add(handler.moveInQueue(0, 1));
          case 3:
            pending.add(handler.playTrack(tracks[index % tracks.length]));
          case 4:
            pending.add(
              handler.playTrackQueue(tracks.take(1 + index % 4).toList()),
            );
          case 5:
            pending.add(
              handler.addToQueue(tracks[(index + 1) % tracks.length]),
            );
        }
      }
      await Future.wait(pending);

      expect(handler.queueTracks.length, player.sequence.length);

      await handler.clearQueue();
      expect(handler.queueTracks, isEmpty);
      expect(player.sequence, isEmpty);
      await handler.dispose();
      await player.close();
    },
  );

  test(
    'rapid taps on a large queue interrupt once and play the newest selection',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      await handler.playTrackQueue(<MediaTrack>[_track(-1)]);

      final libraryTracks = List<MediaTrack>.generate(500, _track);
      player.nextSetAudioSourcesGate = Completer<void>();
      final delayedStop = Completer<void>();
      player.nextStopGate = delayedStop;

      final first = handler.playTrackQueue(libraryTracks, initialIndex: 0);
      for (
        var attempt = 0;
        attempt < 100 && !player.waitingForSource;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(player.waitingForSource, isTrue);

      final taps = <Future<void>>[];
      for (var index = 1; index < 100; index++) {
        taps.add(handler.playTrackQueue(libraryTracks, initialIndex: index));
      }
      expect(player.stopCount, 1);
      expect(delayedStop.isCompleted, isFalse);

      delayedStop.complete();
      await Future.wait(<Future<void>>[
        first,
        ...taps,
      ]).timeout(const Duration(seconds: 2));

      expect(handler.activeTrack?.id, libraryTracks[99].id);
      expect(handler.queueTracks, hasLength(libraryTracks.length));
      expect(player.sequence, hasLength(libraryTracks.length));
      expect(player.currentIndex, 99);
      expect(
        (player.sequence[99].tag as MediaItem).title,
        libraryTracks[99].title,
      );
      expect(player.sourcePreloadHistory, isNotEmpty);
      expect(player.sourcePreloadHistory.every((preload) => !preload), isTrue);
      expect(player.stopCount, 1);
      expect(player.playing, isTrue);

      await handler.dispose();
      await player.close();
    },
  );

  test(
    'rapid taps on the same large queue seek in place and keep only newest history',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      final libraryTracks = List<MediaTrack>.generate(500, _track);
      await handler.playTrackQueue(libraryTracks, initialIndex: 0);
      expect(player.sourceSetCount, 1);

      final manager = LocalPlaylistManager();
      await manager.initialize();
      final controller = HybridMusicController(
        library: _FakeMediaLibrary(songs: libraryTracks),
        audioHandler: handler,
        playlistManager: manager,
      );
      final taps = <Future<void>>[];
      for (var index = 0; index < 100; index++) {
        taps.add(controller.playTrackQueue(libraryTracks, initialIndex: index));
      }
      await Future.wait(taps).timeout(const Duration(seconds: 2));

      expect(player.sourceSetCount, 1);
      expect(player.stopCount, 0);
      expect(player.currentIndex, 99);
      expect(handler.activeTrack?.id, libraryTracks[99].id);
      expect(manager.playCount(libraryTracks[99].id), 1);
      expect(
        libraryTracks
            .take(99)
            .every((track) => manager.playCount(track.id) == 0),
        isTrue,
      );

      await handler.dispose();
      controller.dispose();
      await player.close();
    },
  );

  test('Repeat All manual Next wraps from the final queue item', () async {
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    await handler.playTrackQueue(<MediaTrack>[
      _track(1),
      _track(2),
    ], initialIndex: 1);
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    await handler.skipToNext();

    expect(player.currentIndex, 0);
    expect(player.position, Duration.zero);
    expect(player.playing, isTrue);

    await handler.dispose();
    await player.close();
  });

  test('manual queue navigation wraps in both directions', () async {
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    await handler.playTrackQueue(<MediaTrack>[_track(1), _track(2), _track(3)]);

    await handler.skipToPrevious();
    expect(player.currentIndex, 2);
    await handler.skipToNext();
    expect(player.currentIndex, 0);

    await handler.playQueueIndex(2);
    await handler.skipToNext();
    expect(player.currentIndex, 0);
    await handler.skipToPrevious();
    expect(player.currentIndex, 2);

    await handler.dispose();
    await player.close();
  });

  test('Repeat All completion advances through the queue and wraps', () async {
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    await handler.playTrackQueue(<MediaTrack>[_track(1), _track(2), _track(3)]);
    await handler.setRepeatMode(AudioServiceRepeatMode.all);

    player.emitProcessingState(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 1);
    expect(player.playing, isTrue);

    player.emitProcessingState(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 2);

    player.emitProcessingState(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 0);
    expect(player.playing, isTrue);

    await handler.dispose();
    await player.close();
  });

  test('track completion wraps automatically at the queue boundary', () async {
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    await handler.playTrackQueue(<MediaTrack>[
      _track(1),
      _track(2),
    ], initialIndex: 1);

    player.emitProcessingState(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);

    expect(player.currentIndex, 0);
    expect(player.position, Duration.zero);
    expect(player.playing, isTrue);

    await handler.dispose();
    await player.close();
  });

  test('opening a folder reuses the loaded library tracks', () async {
    final songs = <MediaTrack>[
      _folderTrack(1, '/Music/ArtistA/Live'),
      _folderTrack(2, '/Music/ArtistB/Live'),
      _folderTrack(3, r'\Music\ArtistA\Live\'),
    ];
    final library = _FakeMediaLibrary(songs: songs);
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final controller = HybridMusicController(
      library: library,
      audioHandler: handler,
      playlistManager: manager,
    );

    await controller.loadLibrary();
    expect(library.songQueries, 1);

    final tracks = await controller.tracksForFolder(r'\Music\ArtistA\Live\');
    expect(tracks.map((track) => track.id), <String>['queue-1', 'queue-3']);
    expect(library.songQueries, 1);

    controller.dispose();
    await handler.dispose();
    await player.close();
  });

  test('library refresh keeps the current list visible until replacement is ready', () async {
    final songs = <MediaTrack>[_folderTrack(1, '/Music/Old')];
    final library = _FakeMediaLibrary(songs: songs);
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final controller = HybridMusicController(
      library: library,
      audioHandler: handler,
      playlistManager: manager,
    );

    await controller.loadLibrary();
    final replacement = Completer<List<MediaTrack>>();
    library.songQueryCompleter = replacement;
    final refresh = controller.refreshLibrary();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isLoading, isFalse);
    expect(controller.localSongs.single.id, 'queue-1');

    replacement.complete(<MediaTrack>[_folderTrack(2, '/Music/New')]);
    await refresh;
    expect(controller.localSongs.single.id, 'queue-2');

    controller.dispose();
    await handler.dispose();
    await player.close();
  });

  test('folder queries use the refreshed library snapshot', () async {
    final songs = <MediaTrack>[_folderTrack(1, '/Music/Old')];
    final library = _FakeMediaLibrary(songs: songs);
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final controller = HybridMusicController(
      library: library,
      audioHandler: handler,
      playlistManager: manager,
    );

    await controller.loadLibrary();
    expect(
      (await controller.tracksForFolder('/Music/Old')).map((track) => track.id),
      <String>['queue-1'],
    );

    songs
      ..clear()
      ..add(_folderTrack(2, '/Music/New'));
    await controller.refreshLibrary();

    expect(await controller.tracksForFolder('/Music/Old'), isEmpty);
    expect(
      (await controller.tracksForFolder('/Music/New')).map((track) => track.id),
      <String>['queue-2'],
    );
    expect(library.songQueries, 2);

    controller.dispose();
    await handler.dispose();
    await player.close();
  });

  testWidgets(
    'playlist rename supports cancel, validation, trimming, duplicates, and save errors',
    (tester) async {
      var failWrites = false;
      var playlistWrites = 0;
      final manager = LocalPlaylistManager(
        writeString: (key, value) async {
          final preferences = await SharedPreferences.getInstance();
          final saved = await preferences.setString(key, value);
          if (key == 'yazen.custom_playlists.v1') {
            playlistWrites++;
            if (failWrites) {
              failWrites = false;
              return false;
            }
          }
          return saved;
        },
      );
      await manager.initialize();
      final target = await manager.createPlaylist('Original');
      final existing = await manager.createPlaylist('Existing');

      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      final controller = HybridMusicController(
        library: _FakeMediaLibrary(songs: const <MediaTrack>[]),
        audioHandler: handler,
        playlistManager: manager,
      );
      final theme = ThemeProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<dynamic>>[
            ChangeNotifierProvider<HybridMusicController>.value(
              value: controller,
            ),
            ChangeNotifierProvider<LocalPlaylistManager>.value(value: manager),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: MaterialApp(
            theme: theme.theme,
            home: PlaylistDetailsScreen(playlistId: target.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final writesBeforeDialog = playlistWrites;
      Future<void> openRenameDialog() async {
        await tester.tap(find.byTooltip('Playlist options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename playlist'));
        await tester.pumpAndSettle();
      }

      await openRenameDialog();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(manager.playlists.first.name, 'Original');
      expect(playlistWrites, writesBeforeDialog);

      await openRenameDialog();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(manager.playlists.first.name, 'Original');
      expect(playlistWrites, writesBeforeDialog);

      await openRenameDialog();
      await tester.enterText(find.byType(TextField), '  Existing  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        manager.playlists
            .firstWhere((playlist) => playlist.id == target.id)
            .name,
        'Existing',
      );
      expect(
        manager.playlists
            .firstWhere((playlist) => playlist.id == existing.id)
            .name,
        'Existing',
      );
      expect(find.text('Existing'), findsOneWidget);

      failWrites = true;
      await openRenameDialog();
      await tester.enterText(find.byType(TextField), 'Not persisted');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.textContaining('Unable to save playlist name'),
        findsOneWidget,
      );
      expect(
        manager.playlists
            .firstWhere((playlist) => playlist.id == target.id)
            .name,
        'Existing',
      );
      expect(find.text('Existing'), findsOneWidget);
      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(
        restored.playlists
            .firstWhere((playlist) => playlist.id == target.id)
            .name,
        'Existing',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await player.close();
      theme.dispose();
      manager.dispose();
    },
  );

  test('successive track selections reuse a loaded 500-song queue', () async {
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    final tracks = List<MediaTrack>.generate(500, _track);
    await handler.playTrackQueue(tracks, initialIndex: 0);

    for (var index = 1; index < 100; index++) {
      await handler.playTrackQueue(tracks, initialIndex: index);
    }

    expect(player.sourceSetCount, 1);
    expect(player.stopCount, 0);
    expect(player.sequence, hasLength(500));
    expect(player.currentIndex, 99);
    expect(handler.activeTrack?.id, tracks[99].id);
    expect(player.playing, isTrue);

    await handler.dispose();
    await player.close();
  });

  test(
    'repairs the mirrored queue after a partial player mutation failure',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      await handler.playTrackQueue(<MediaTrack>[_track(0)]);
      player.failNextAddAfterMutation = true;

      await expectLater(
        handler.addToQueue(_track(1)),
        throwsA(isA<StateError>()),
      );

      expect(handler.queueTracks.length, player.sequence.length);
      expect(handler.queueTracks, isEmpty);
      expect(player.sequence, isEmpty);
      await handler.dispose();
      await player.close();
    },
  );

  test('end-of-track sleep timer pauses during repeat-one playback', () async {
    final player = _FakeAudioPlayer()..duration = const Duration(seconds: 10);
    final handler = HybridAudioHandler(
      player: player,
      playbackStore: const PlaybackStateStore(),
    );
    await handler.playTrack(_track(0));
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    handler.setSleepTimer(null, mode: SleepTimerMode.endOfCurrentTrack);

    player.emitPosition(const Duration(milliseconds: 9700));
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(player.playing, isFalse);
    expect(handler.sleepTimerMode, SleepTimerMode.duration);
    await handler.dispose();
    await player.close();
  });

  test(
    'track replacement and notification stop do not wait for song end',
    () async {
      final player = _FakeAudioPlayer();
      final firstPlaybackGate = Completer<void>();
      player.nextPlayGate = firstPlaybackGate;
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );

      final firstSelection = handler.playTrackQueue(<MediaTrack>[
        _track(0),
        _track(1),
      ]);
      for (var attempt = 0; attempt < 100 && !player.playing; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(player.playing, isTrue);
      await firstSelection.timeout(const Duration(seconds: 1));

      await handler.playTrack(_track(2)).timeout(const Duration(seconds: 1));
      expect(handler.activeTrack?.id, _track(2).id);
      expect(handler.queueTracks.map((track) => track.id), <String>[
        _track(2).id,
      ]);
      expect(player.playing, isTrue);

      final state = await handler.playbackState.first;
      expect(
        state.controls.any(
          (control) =>
              control.action == MediaAction.stop &&
              control.androidIcon == 'drawable/yazen_notification_close',
        ),
        isTrue,
      );
      await handler.stop().timeout(const Duration(seconds: 1));
      expect(handler.queueTracks, isEmpty);
      expect(handler.activeTrack, isNull);
      expect(player.sequence, isEmpty);
      expect(player.playing, isFalse);

      if (!firstPlaybackGate.isCompleted) firstPlaybackGate.complete();
      await handler.dispose();
      await player.close();
    },
  );

  test(
    'restore skips missing files and remaps a missing current track',
    () async {
      final directory = await Directory.systemTemp.createTemp('yazen-restore-');
      final before = File('${directory.path}/before.mp3');
      final after = File('${directory.path}/after.mp3');
      await before.writeAsBytes(<int>[1]);
      await after.writeAsBytes(<int>[2]);
      final missing = File('${directory.path}/deleted.mp3');
      final store = const PlaybackStateStore();
      await store.save(
        queue: <MediaTrack>[
          _fileTrack('before', before),
          _fileTrack('deleted', missing),
          _fileTrack('after', after),
        ],
        currentIndex: 1,
        position: const Duration(seconds: 35),
        playing: false,
      );
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(player: player, playbackStore: store);

      await handler.restoreLastPlayback();
      await store.idle;

      expect(handler.queueTracks.map((track) => track.id), <String>[
        'before',
        'after',
      ]);
      expect(player.currentIndex, 1);
      expect(player.position, Duration.zero);
      final repaired = await store.load();
      expect(repaired?.queue.map((track) => track.id), <String>[
        'before',
        'after',
      ]);
      expect(repaired?.currentIndex, 1);
      expect(repaired?.position, Duration.zero);

      await handler.dispose();
      await player.close();
      await directory.delete(recursive: true);
    },
  );

  test('restore accepts persisted HTTP(S) remote tracks', () async {
    final store = const PlaybackStateStore();
    final remote = MediaTrack(
      id: 'remote-1',
      title: 'Remote track',
      artist: 'Remote artist',
      album: 'Remote album',
      source: TrackSource.remote,
      uri: Uri.parse('https://example.com/audio.mp3'),
      headers: const <String, String>{'Authorization': 'Bearer test'},
    );
    await store.save(
      queue: <MediaTrack>[remote],
      currentIndex: 0,
      position: const Duration(seconds: 12),
      playing: true,
    );
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(player: player, playbackStore: store);
    await handler.restoreLastPlayback();

    expect(handler.queueTracks.single.id, 'remote-1');
    expect(player.currentIndex, 0);
    expect(player.position, const Duration(seconds: 12));
    expect(player.playing, isTrue);

    await handler.dispose();
    await player.close();
  });

  test('restore clears storage when every saved file is missing', () async {
    final directory = await Directory.systemTemp.createTemp('yazen-restore-');
    final missing = File('${directory.path}/deleted.mp3');
    final store = const PlaybackStateStore();
    await store.save(
      queue: <MediaTrack>[_fileTrack('deleted', missing)],
      currentIndex: 0,
      position: Duration.zero,
      playing: false,
    );
    final player = _FakeAudioPlayer();
    final handler = HybridAudioHandler(player: player, playbackStore: store);

    await handler.restoreLastPlayback();

    expect(handler.queueTracks, isEmpty);
    expect(player.sequence, isEmpty);
    expect(await store.load(), isNull);

    await handler.dispose();
    await player.close();
    await directory.delete(recursive: true);
  });

  test(
    'play-history updates retain identities of cached library lists',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      final track = MediaTrack(
        id: 'cache-track',
        title: 'Cache track',
        artist: 'Artist',
        album: 'Album',
        source: TrackSource.local,
        folder: '/Music/Artist/Album',
        uri: Uri.parse('file:///tmp/cache-track.mp3'),
      );
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final controller = HybridMusicController(
        library: _FakeMediaLibrary(songs: <MediaTrack>[track]),
        audioHandler: handler,
        playlistManager: manager,
      );
      await controller.loadLibrary(requestPermission: false);
      final localSongs = controller.localSongs;
      final visibleTracks = controller.visibleTracks;
      final hiddenTracks = controller.hiddenTracks;
      final folders = controller.folders;

      await manager.recordPlayed(track);

      expect(identical(controller.localSongs, localSongs), isTrue);
      expect(identical(controller.visibleTracks, visibleTracks), isTrue);
      expect(identical(controller.hiddenTracks, hiddenTracks), isTrue);
      expect(identical(controller.folders, folders), isTrue);

      await manager.updateTrackMetadata(
        track.id,
        title: 'Edited cache track',
        artist: 'Artist',
        album: 'Album',
      );
      expect(identical(controller.localSongs, localSongs), isFalse);
      expect(controller.localSongs.single.title, 'Edited cache track');

      await handler.dispose();
      controller.dispose();
      await player.close();
    },
  );

  test(
    'permission denial is recovered on resume, refresh, and request',
    () async {
      final player = _FakeAudioPlayer();
      final handler = HybridAudioHandler(
        player: player,
        playbackStore: const PlaybackStateStore(),
      );
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final library = _FakeMediaLibrary(
        songs: <MediaTrack>[_track(0)],
        granted: false,
      );
      final controller = HybridMusicController(
        library: library,
        audioHandler: handler,
        playlistManager: manager,
      );
      await controller.loadLibrary(requestPermission: false);
      expect(controller.permissionRequired, isTrue);
      expect(controller.localSongs, isEmpty);

      library.granted = true;
      await controller.handleAppResumed();
      expect(controller.permissionRequired, isFalse);
      expect(controller.localSongs, hasLength(1));

      library.granted = false;
      await controller.refreshLibrary();
      expect(controller.permissionRequired, isTrue);
      expect(controller.localSongs, isEmpty);

      library.granted = true;
      expect(await controller.openMediaPermissionSettings(), isTrue);
      expect(library.settingsOpens, 1);
      await controller.requestMediaPermission();
      expect(library.permissionRequests, 1);
      expect(controller.permissionRequired, isFalse);
      expect(controller.localSongs, hasLength(1));

      await handler.dispose();
      controller.dispose();
      await player.close();
    },
  );
}

MediaTrack _track(int index) => MediaTrack(
  id: 'queue-$index',
  title: 'Queue $index',
  artist: 'Test artist',
  album: 'Test album',
  source: TrackSource.local,
  uri: Uri.parse('file:///tmp/queue-$index.mp3'),
);

MediaTrack _folderTrack(int index, String folder) => MediaTrack(
  id: 'queue-$index',
  title: 'Queue $index',
  artist: 'Test artist',
  album: 'Test album',
  source: TrackSource.local,
  uri: Uri.parse('file:///tmp/queue-$index.mp3'),
  folder: folder,
);

MediaTrack _fileTrack(String id, File file) => MediaTrack(
  id: id,
  title: id,
  artist: 'Test artist',
  album: 'Test album',
  source: TrackSource.local,
  uri: file.absolute.uri,
);

class _FakeAudioPlayer implements AudioPlayer {
  final _currentIndexController = StreamController<int?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _playbackEventController = StreamController<PlaybackEvent>.broadcast();
  final _processingStateController =
      StreamController<ProcessingState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final List<AudioSource> _sources = <AudioSource>[];
  int? _currentIndex;
  bool _playing = false;
  double _volume = 1.0;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration? _duration;
  LoopMode _loopMode = LoopMode.off;
  bool failNextAddAfterMutation = false;
  int stopCount = 0;
  Completer<void>? nextPlayGate;
  Completer<void>? _activePlayGate;
  Completer<void>? nextSetAudioSourcesGate;
  Completer<void>? nextStopGate;
  Completer<void>? _activeSetAudioSourcesGate;
  bool _activeSetAudioSourcesInterrupted = false;
  int sourceSetCount = 0;
  final List<bool> sourcePreloadHistory = <bool>[];
  bool get waitingForSource => _activeSetAudioSourcesGate != null;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      _playbackEventController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  List<IndexedAudioSource> get sequence =>
      _sources.expand((source) => source.sequence).toList(growable: false);

  @override
  int? get currentIndex => _currentIndex;

  @override
  bool get playing => _playing;

  @override
  double get volume => _volume;

  @override
  double get speed => _speed;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  set duration(Duration? value) => _duration = value;

  void emitPosition(Duration value) {
    _position = value;
    _positionController.add(value);
  }

  void emitProcessingState(ProcessingState value) {
    _processingStateController.add(value);
  }

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  ProcessingState get processingState =>
      _sources.isEmpty ? ProcessingState.idle : ProcessingState.ready;

  @override
  LoopMode get loopMode => _loopMode;

  @override
  bool get hasNext =>
      _currentIndex != null && _currentIndex! < _sources.length - 1;

  @override
  bool get hasPrevious => _currentIndex != null && _currentIndex! > 0;

  @override
  int? get androidAudioSessionId => null;

  @override
  Stream<int?> get androidAudioSessionIdStream => const Stream<int?>.empty();

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) => setAudioSources(
    <AudioSource>[audioSource],
    preload: preload,
    initialIndex: initialIndex,
    initialPosition: initialPosition,
  );

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    sourceSetCount++;
    sourcePreloadHistory.add(preload);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final gate = nextSetAudioSourcesGate;
    nextSetAudioSourcesGate = null;
    if (gate != null) {
      _activeSetAudioSourcesGate = gate;
      _activeSetAudioSourcesInterrupted = false;
      await gate.future;
      final interrupted = _activeSetAudioSourcesInterrupted;
      _activeSetAudioSourcesGate = null;
      if (interrupted) {
        _activeSetAudioSourcesInterrupted = false;
        throw StateError('Source load interrupted by newer selection');
      }
    }
    _sources
      ..clear()
      ..addAll(audioSources);
    _currentIndex = _sources.isEmpty ? null : (initialIndex ?? 0);
    _position = initialPosition ?? Duration.zero;
    return null;
  }

  @override
  Future<void> addAudioSource(AudioSource audioSource) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _sources.add(audioSource);
    _currentIndex ??= 0;
    if (failNextAddAfterMutation) {
      failNextAddAfterMutation = false;
      throw StateError('Simulated partial playlist update');
    }
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _sources.removeAt(index);
    if (_sources.isEmpty) {
      _currentIndex = null;
    } else if (_currentIndex == null || _currentIndex! >= _sources.length) {
      _currentIndex = _sources.length - 1;
    } else if (index < _currentIndex!) {
      _currentIndex = _currentIndex! - 1;
    }
  }

  @override
  Future<void> moveAudioSource(int currentIndex, int newIndex) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final source = _sources.removeAt(currentIndex);
    _sources.insert(newIndex, source);
    if (_currentIndex == currentIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex != null &&
        currentIndex < _currentIndex! &&
        newIndex >= _currentIndex!) {
      _currentIndex = _currentIndex! - 1;
    } else if (_currentIndex != null &&
        currentIndex > _currentIndex! &&
        newIndex <= _currentIndex!) {
      _currentIndex = _currentIndex! + 1;
    }
  }

  @override
  Future<void> clearAudioSources() async {
    _sources.clear();
    _currentIndex = null;
  }

  @override
  Future<void> play() async {
    _playing = true;
    final gate = nextPlayGate;
    nextPlayGate = null;
    _activePlayGate = gate;
    if (gate != null) await gate.future;
    if (identical(_activePlayGate, gate)) _activePlayGate = null;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _playing = false;
    _position = Duration.zero;
    final sourceGate = _activeSetAudioSourcesGate;
    if (sourceGate != null) {
      _activeSetAudioSourcesInterrupted = true;
      if (!sourceGate.isCompleted) sourceGate.complete();
    }
    final gate = _activePlayGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    final stopGate = nextStopGate;
    nextStopGate = null;
    if (stopGate != null) await stopGate.future;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _position = position ?? Duration.zero;
    if (index != null) _currentIndex = index;
  }

  @override
  Future<void> seekToNext() async {
    if (hasNext) _currentIndex = _currentIndex! + 1;
  }

  @override
  Future<void> seekToPrevious() async {
    if (hasPrevious) _currentIndex = _currentIndex! - 1;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setLoopMode(LoopMode loopMode) async {
    _loopMode = loopMode;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {}

  Future<void> close() async {
    await _currentIndexController.close();
    await _playerStateController.close();
    await _playbackEventController.close();
    await _processingStateController.close();
    await _positionController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaLibrary extends MediaLibraryService {
  _FakeMediaLibrary({required this.songs, this.granted = true});

  final List<MediaTrack> songs;
  bool granted;
  int settingsOpens = 0;
  int permissionRequests = 0;
  int songQueries = 0;
  Completer<List<MediaTrack>>? songQueryCompleter;

  @override
  Future<bool> ensurePermission({bool requestIfDenied = true}) async => granted;

  @override
  Future<bool> recheckPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpens++;
    return true;
  }

  @override
  Future<List<MediaTrack>> querySongs() async {
    songQueries++;
    final pending = songQueryCompleter;
    if (pending != null) return pending.future;
    return songs;
  }

  @override
  Future<List<MediaTrack>> queryVideos({bool requestPermission = true}) async =>
      const <MediaTrack>[];

  @override
  Future<List<ArtistModel>> queryArtists() async => const <ArtistModel>[];

  @override
  Future<List<AlbumModel>> queryAlbums() async => const <AlbumModel>[];

  @override
  Future<List<PlaylistModel>> queryPlaylists() async => const <PlaylistModel>[];
}
