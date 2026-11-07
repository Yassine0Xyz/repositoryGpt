import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:yazen/models/media_track.dart';

void main() {
  test(
    'maps SongModel size, modification time, and folder without file stat',
    () {
      final track = MediaTrack.fromSong(
        SongModel(<String, dynamic>{
          '_id': 42,
          '_data': '/Music/Artist/Album/song.mp3',
          '_size': 4096,
          'date_modified': 1700000000,
          'duration': 90000,
          'title': 'Song',
          'artist': 'Artist',
          'album': 'Album',
          'album_id': 7,
        }),
      );

      expect(track.albumId, 7);
      expect(track.sizeBytes, 4096);
      expect(
        track.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(track.folder, '/Music/Artist/Album');
    },
  );

  test('leaves modification time unknown when MediaStore has no timestamp', () {
    final track = MediaTrack.fromSong(
      SongModel(<String, dynamic>{
        '_id': 43,
        '_data': '/Music/song.mp3',
        '_size': 1,
        'date_modified': null,
        'duration': null,
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
      }),
    );

    expect(track.modifiedAt, isNull);
    expect(track.sizeBytes, 1);
  });
}
