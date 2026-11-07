import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/models/library_query.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/library_data_engine.dart';

MediaTrack _track({
  required String id,
  required String title,
  required String folder,
  String album = 'Album',
  DateTime? modifiedAt,
}) => MediaTrack(
  id: id,
  title: title,
  artist: 'Artist',
  album: album,
  source: TrackSource.local,
  folder: folder,
  modifiedAt: modifiedAt,
  uri: Uri.parse('file:///music/$id.mp3'),
);

void main() {
  group('LibraryIndexSnapshot', () {
    test('publishes immutable identity and folder indexes', () {
      final engine = LibraryDataEngine();
      final first = _track(id: 'first', title: 'First', folder: r'\Music\Live');
      final hidden = _track(
        id: 'hidden',
        title: 'Hidden',
        folder: '/Music/Live',
      );

      final snapshot = engine.rebuild(
        tracks: <MediaTrack>[first, hidden],
        hiddenTrackIds: const <String>{'hidden'},
      );

      expect(snapshot.revision, 1);
      expect(snapshot.allTracks, <MediaTrack>[first, hidden]);
      expect(snapshot.visibleAudioTracks, <MediaTrack>[first]);
      expect(snapshot.hiddenAudioTracks, <MediaTrack>[hidden]);
      expect(snapshot.trackById['hidden'], same(hidden));
      expect(snapshot.tracksInFolder('/Music/Live'), <MediaTrack>[first]);
      expect(snapshot.folderCounts['/Music/Live'], 1);
      expect(snapshot.folders, <String>['/Music/Live']);
      expect(() => snapshot.trackById['other'] = first, throwsUnsupportedError);
    });
  });

  group('LibraryDataEngine queries', () {
    test('sorts before searching and reuses an unchanged query result', () {
      final engine = LibraryDataEngine();
      final tracks = <MediaTrack>[
        _track(
          id: 'z',
          title: 'Yazen Music',
          folder: '/Music',
          modifiedAt: DateTime(2025),
        ),
        _track(
          id: 'a',
          title: 'Yazen Audio',
          folder: '/Music',
          modifiedAt: DateTime(2024),
        ),
        _track(
          id: 'other',
          title: 'Ambient',
          folder: '/Music',
          modifiedAt: DateTime(2026),
        ),
      ];
      engine.rebuild(tracks: tracks, hiddenTrackIds: const <String>[]);
      final source = engine.snapshot.visibleAudioTracks;
      final first = engine.queryTracks(
        source: source,
        sort: LibrarySort.nameAZ,
        filters: const <LibraryFilter>{},
        query: 'yazen',
        isFavorite: (_) => false,
        playCount: (_) => 0,
        lastPlayed: (_) => null,
      );
      final repeated = engine.queryTracks(
        source: source,
        sort: LibrarySort.nameAZ,
        filters: const <LibraryFilter>{},
        query: 'yazen',
        isFavorite: (_) => false,
        playCount: (_) => 0,
        lastPlayed: (_) => null,
      );

      expect(first.map((track) => track.id), <String>['a', 'z']);
      expect(repeated, same(first));
    });

    test('reuses filtered/sorted data while the text query changes', () {
      final engine = LibraryDataEngine();
      engine.rebuild(
        tracks: <MediaTrack>[
          _track(id: 'one', title: 'Yazen One', folder: '/Music'),
          _track(id: 'two', title: 'Yazen Two', folder: '/Music'),
        ],
        hiddenTrackIds: const <String>[],
      );
      final source = engine.snapshot.visibleAudioTracks;
      var favoriteChecks = 0;
      bool isFavorite(MediaTrack track) {
        favoriteChecks++;
        return true;
      }

      List<MediaTrack> query(String text) => engine.queryTracks(
        source: source,
        sort: LibrarySort.nameAZ,
        filters: const <LibraryFilter>{LibraryFilter.favorites},
        query: text,
        isFavorite: isFavorite,
        playCount: (_) => 0,
        lastPlayed: (_) => null,
      );

      expect(query('').length, 2);
      final checksAfterFirstQuery = favoriteChecks;
      expect(query('two').single.id, 'two');
      expect(favoriteChecks, checksAfterFirstQuery);
      expect(checksAfterFirstQuery, 2);
    });

    test('reads play-count sort keys once per track, not per comparison', () {
      final engine = LibraryDataEngine();
      engine.rebuild(
        tracks: <MediaTrack>[
          _track(id: 'one', title: 'One', folder: '/Music'),
          _track(id: 'two', title: 'Two', folder: '/Music'),
          _track(id: 'three', title: 'Three', folder: '/Music'),
          _track(id: 'four', title: 'Four', folder: '/Music'),
        ],
        hiddenTrackIds: const <String>[],
      );
      final source = engine.snapshot.visibleAudioTracks;
      var playCountReads = 0;
      final result = engine.queryTracks(
        source: source,
        sort: LibrarySort.mostPlayed,
        filters: const <LibraryFilter>{},
        query: '',
        isFavorite: (_) => false,
        playCount: (id) {
          playCountReads++;
          return id == 'three' ? 10 : 1;
        },
        lastPlayed: (_) => null,
      );

      expect(result.first.id, 'three');
      expect(playCountReads, source.length);
    });

    test('re-evaluates favorite-dependent results after dynamic revision', () {
      final engine = LibraryDataEngine();
      engine.rebuild(
        tracks: <MediaTrack>[
          _track(id: 'one', title: 'One', folder: '/Music'),
          _track(id: 'two', title: 'Two', folder: '/Music'),
        ],
        hiddenTrackIds: const <String>[],
      );
      final source = engine.snapshot.visibleAudioTracks;
      var favoriteId = 'one';

      List<MediaTrack> query(int revision) => engine.queryTracks(
        source: source,
        sort: LibrarySort.nameAZ,
        filters: const <LibraryFilter>{LibraryFilter.favorites},
        query: '',
        isFavorite: (track) => track.id == favoriteId,
        playCount: (_) => 0,
        lastPlayed: (_) => null,
        dynamicRevision: revision,
      );

      expect(query(0).single.id, 'one');
      favoriteId = 'two';
      expect(query(1).single.id, 'two');
    });
  });
}
