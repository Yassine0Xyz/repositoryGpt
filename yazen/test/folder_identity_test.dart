import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/folder_identity.dart';

void main() {
  MediaTrack track(String id, String folder) => MediaTrack(
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    source: TrackSource.local,
    folder: folder,
  );

  test('normalizes full paths without merging equal basenames', () {
    final folders = folderIdentities(<MediaTrack>[
      track('a', '/Music/ArtistA/Live/'),
      track('b', r'\Music\ArtistB\Live'),
      track('c', '/Music/ArtistA/Live'),
    ]);

    expect(folders, <String>['/Music/ArtistA/Live', '/Music/ArtistB/Live']);
    expect(
      normalizeFolderIdentity(r'\Music\ArtistA\Live\'),
      '/Music/ArtistA/Live',
    );
  });

  test('display labels are relative to the Android storage root', () {
    expect(
      folderDisplayName('/storage/emulated/0/Music/Downloads'),
      'Music · Downloads',
    );
    expect(
      folderDisplayName('/storage/emulated/0/Download/WhatsApp'),
      'Download · WhatsApp',
    );
    expect(folderDisplayName('/Music/ArtistA/Live'), 'Music · ArtistA · Live');
    expect(folderDisplayName('/Music'), 'Music');
  });

  test('filters tracks by normalized full folder identity', () {
    final first = track('first', '/Music/ArtistA/Live/');
    final sibling = track('sibling', '/Music/ArtistB/Live');
    final normalizedMatch = track('normalized', r'\Music\ArtistA\Live');
    final parent = track('parent', '/Music/ArtistA');
    final child = track('child', '/Music/ArtistA/Live');
    final samePrefixSibling = track(
      'prefix-sibling',
      '/Music/ArtistA/LiveMore',
    );
    final differentCase = track('different-case', '/music/ArtistA/Live');
    const withoutFolder = MediaTrack(
      id: 'no-folder',
      title: 'no-folder',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
    );

    expect(
      tracksInFolder(<MediaTrack>[
        first,
        sibling,
        normalizedMatch,
        parent,
        child,
        samePrefixSibling,
        differentCase,
        withoutFolder,
      ], r'\Music\ArtistA\Live\').map((item) => item.id),
      <String>['first', 'normalized', 'child'],
    );
    expect(
      tracksInFolder(<MediaTrack>[
        child,
        differentCase,
      ], '/music/ArtistA/Live').map((item) => item.id),
      <String>['different-case'],
    );
    expect(tracksInFolder(<MediaTrack>[first], '  '), isEmpty);
  });
}
