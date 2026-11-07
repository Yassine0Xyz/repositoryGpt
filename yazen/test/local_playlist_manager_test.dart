import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/local_playlist_manager.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaTrack track({String id = 'local-song-1'}) => MediaTrack(
    id: id,
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    source: TrackSource.local,
    uri: Uri.parse('file:///music/$id.mp3'),
    duration: const Duration(minutes: 3),
  );

  test('persists favorites and custom playlists', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Daily mix');
    await manager.addToPlaylist(playlist.id, track());
    await manager.addToPlaylist(playlist.id, track());
    await manager.toggleFavorite(track());

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playlists.single.name, 'Daily mix');
    expect(restored.playlists.single.tracks, hasLength(1));
    expect(restored.favorites, hasLength(1));
    expect(restored.isFavorite(track()), isTrue);
  });

  test('custom playlists retain local file URIs after reload', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Linux files');
    final audioFile = MediaTrack(
      id: 'local-file:/home/user/Music/song.flac',
      title: 'song',
      artist: 'Unknown artist',
      album: 'Local files',
      source: TrackSource.local,
      uri: Uri.file('/home/user/Music/song.flac'),
    );
    await manager.addToPlaylist(playlist.id, audioFile);

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playlists.single.tracks.single.uri, audioFile.uri);
  });

  test(
    'a failed write does not prevent a later snapshot from persisting',
    () async {
      var failNextWrite = true;
      final manager = LocalPlaylistManager(
        writeString: (key, value) async {
          if (failNextWrite) {
            failNextWrite = false;
            throw StateError('simulated storage failure');
          }
          final preferences = await SharedPreferences.getInstance();
          return preferences.setString(key, value);
        },
      );
      await manager.initialize();

      await expectLater(manager.createPlaylist('First'), throwsStateError);
      await manager.toggleFavorite(track());

      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.playlists.single.name, 'First');
      expect(restored.isFavorite(track()), isTrue);
    },
  );

  test(
    'queued snapshots preserve operation order and the latest state',
    () async {
      final playlistSnapshots = <List<String>>[];
      final manager = LocalPlaylistManager(
        writeString: (key, value) async {
          if (key == 'yazen.custom_playlists.v1') {
            final decoded = jsonDecode(value) as List<dynamic>;
            playlistSnapshots.add(
              decoded
                  .cast<Map<String, dynamic>>()
                  .map((item) => item['name']! as String)
                  .toList(),
            );
          }
          final preferences = await SharedPreferences.getInstance();
          return preferences.setString(key, value);
        },
      );
      await manager.initialize();
      final playlist = await manager.createPlaylist('First');
      await manager.renamePlaylist(playlist.id, 'Last');

      expect(playlistSnapshots, <List<String>>[
        <String>['First'],
        <String>['Last'],
      ]);
      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.playlists.single.name, 'Last');
    },
  );

  test('bulk actions persist and use the last added track as cover', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Batch mix');
    final second = track(id: 'local-song-2');
    await manager.addToFavorites(<MediaTrack>[track(), second]);
    await manager.addTracksToPlaylist(playlist.id, <MediaTrack>[
      track(),
      second,
    ]);

    expect(manager.favorites, hasLength(2));
    expect(manager.playlists.single.tracks, hasLength(2));
    expect(manager.playlists.single.coverTrack?.id, 'local-song-2');

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playlists.single.coverTrack?.id, 'local-song-2');
  });

  test(
    'favorite membership stays current after toggle and bulk changes',
    () async {
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final first = track(id: 'favorite-first');
      final second = track(id: 'favorite-second');

      expect(manager.isFavorite(first), isFalse);
      await manager.toggleFavorite(first);
      expect(manager.isFavorite(first), isTrue);
      await manager.toggleFavorite(first);
      expect(manager.isFavorite(first), isFalse);

      await manager.addToFavorites(<MediaTrack>[first, second]);
      expect(manager.isFavorite(first), isTrue);
      expect(manager.isFavorite(second), isTrue);
      await manager.toggleFavorite(second);
      expect(manager.isFavorite(second), isFalse);

      await manager.clearFavorites();
      expect(manager.isFavorite(first), isFalse);
      expect(manager.isFavorite(second), isFalse);
    },
  );

  test('renames a playlist, trims its name, and persists the change', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final playlist = await manager.createPlaylist('Temporary');
    await manager.renamePlaylist(playlist.id, '  Renamed  ');
    expect(manager.playlists.single.name, 'Renamed');

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playlists.single.name, 'Renamed');

    await manager.deletePlaylist(playlist.id);
    expect(manager.playlists, isEmpty);
  });

  test(
    'allows duplicate names without changing other playlist identities',
    () async {
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final first = await manager.createPlaylist('First');
      final second = await manager.createPlaylist('Second');

      await manager.renamePlaylist(first.id, '  Second  ');

      expect(
        manager.playlists.map((playlist) => (playlist.id, playlist.name)),
        <(String, String)>[(first.id, 'Second'), (second.id, 'Second')],
      );
      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(
        restored.playlists.map((playlist) => (playlist.id, playlist.name)),
        <(String, String)>[(first.id, 'Second'), (second.id, 'Second')],
      );
    },
  );

  test(
    'rejects an empty playlist name without changing memory or storage',
    () async {
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final playlist = await manager.createPlaylist('Temporary');

      await expectLater(
        manager.renamePlaylist(playlist.id, '   '),
        throwsFormatException,
      );
      expect(manager.playlists.single.name, 'Temporary');
      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.playlists.single.name, 'Temporary');
    },
  );

  test(
    'failed playlist rename rolls back memory and persisted storage',
    () async {
      var failAfterWriting = false;
      final manager = LocalPlaylistManager(
        writeString: (key, value) async {
          final preferences = await SharedPreferences.getInstance();
          final stored = await preferences.setString(key, value);
          if (key == 'yazen.custom_playlists.v1' && failAfterWriting) {
            failAfterWriting = false;
            return false;
          }
          return stored;
        },
      );
      await manager.initialize();
      final playlist = await manager.createPlaylist('Before');
      failAfterWriting = true;

      await expectLater(
        manager.renamePlaylist(playlist.id, 'After'),
        throwsStateError,
      );

      expect(manager.playlists.single.name, 'Before');
      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.playlists.single.name, 'Before');
    },
  );

  test(
    'concurrent playlist renames are serialized and persist the last name',
    () async {
      final writerEntered = Completer<void>();
      final releaseWriter = Completer<void>();
      var shouldPauseRename = false;
      final manager = LocalPlaylistManager(
        writeString: (key, value) async {
          if (key == 'yazen.custom_playlists.v1' && shouldPauseRename) {
            final saved =
                (jsonDecode(value) as List<dynamic>).single
                    as Map<String, dynamic>;
            if (saved['name'] == 'First rename') {
              shouldPauseRename = false;
              writerEntered.complete();
              await releaseWriter.future;
            }
          }
          final preferences = await SharedPreferences.getInstance();
          return preferences.setString(key, value);
        },
      );
      await manager.initialize();
      final playlist = await manager.createPlaylist('Original');
      shouldPauseRename = true;

      final firstRename = manager.renamePlaylist(playlist.id, 'First rename');
      await writerEntered.future;
      expect(manager.playlists.single.name, 'Original');
      final secondRename = manager.renamePlaylist(playlist.id, 'Final rename');
      releaseWriter.complete();
      await Future.wait(<Future<void>>[firstRename, secondRename]);

      expect(manager.playlists.single.name, 'Final rename');
      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.playlists.single.name, 'Final rename');
    },
  );

  test('records play count and applies metadata overrides', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    await manager.recordPlayed(track());
    await manager.recordPlayed(track());
    await manager.updateTrackMetadata(
      track().id,
      title: 'Edited title',
      artist: 'Edited artist',
      album: 'Edited album',
    );

    expect(manager.playCount(track().id), 2);
    final edited = manager.applyMetadata(<MediaTrack>[track()]).single;
    expect(edited.title, 'Edited title');
    expect(edited.artist, 'Edited artist');
    expect(edited.album, 'Edited album');

    final restored = LocalPlaylistManager();
    await restored.initialize();
    expect(restored.playCount(track().id), 2);
    expect(
      restored.applyMetadata(<MediaTrack>[track()]).single.title,
      'Edited title',
    );
  });

  test(
    'hides tracks and clears cover when the final track is removed',
    () async {
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final playlist = await manager.createPlaylist('Hidden');
      await manager.addToPlaylist(playlist.id, track());
      await manager.setHidden(<String>[track().id], hidden: true);
      await manager.removeFromPlaylist(playlist.id, track().id);

      expect(manager.isHidden(track().id), isTrue);
      expect(manager.playlists.single.tracks, isEmpty);
      expect(manager.playlists.single.coverTrack, isNull);
    },
  );

  test(
    'cover follows addition history rather than reordered track position',
    () async {
      final manager = LocalPlaylistManager();
      await manager.initialize();
      final playlist = await manager.createPlaylist('History');
      final first = track(id: 'first');
      final second = track(id: 'second');
      final latest = track(id: 'latest');
      await manager.addTracksToPlaylist(playlist.id, <MediaTrack>[
        first,
        second,
        latest,
      ]);
      await manager.moveWithinPlaylist(playlist.id, 2, 0);

      expect(manager.playlists.single.coverTrack?.id, latest.id);
      await manager.removeFromPlaylist(playlist.id, latest.id);
      expect(manager.playlists.single.coverTrack?.id, second.id);

      final restored = LocalPlaylistManager();
      await restored.initialize();
      expect(restored.playlists.single.coverTrack?.id, second.id);
    },
  );

  test('play history does not invalidate library track overlays', () async {
    final manager = LocalPlaylistManager();
    await manager.initialize();
    final initialRevision = manager.libraryOverlayRevision;

    await manager.recordPlayed(track());
    expect(manager.libraryOverlayRevision, initialRevision);

    await manager.updateTrackMetadata(
      track().id,
      title: 'Edited',
      artist: 'Artist',
      album: 'Album',
    );
    expect(manager.libraryOverlayRevision, initialRevision + 1);

    await manager.setHidden(<String>[track().id], hidden: true);
    expect(manager.libraryOverlayRevision, initialRevision + 2);
  });
}
