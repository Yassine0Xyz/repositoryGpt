import 'package:flutter_test/flutter_test.dart';

import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/library_search_service.dart';

void main() {
  MediaTrack track({
    required String id,
    required String title,
    required String artist,
    Duration duration = const Duration(minutes: 3),
  }) => MediaTrack(
    id: id,
    title: title,
    artist: artist,
    album: 'Album',
    source: TrackSource.local,
    uri: Uri.parse('file:///music/$id.mp3'),
    duration: duration,
  );

  test('searches title, artist and normalizes common Arabic forms', () {
    const service = LibrarySearchService();
    final tracks = <MediaTrack>[
      track(id: '1', title: 'ليلة هادئة', artist: 'Yazen'),
      track(id: '2', title: 'Morning', artist: 'Other'),
    ];

    expect(service.search(tracks, 'yazen').single.id, '1');
    expect(service.search(tracks, 'ليله').single.id, '1');
  });

  test('applies duration and kind filters', () {
    const service = LibrarySearchService();
    final tracks = <MediaTrack>[
      track(
        id: 'short',
        title: 'Short',
        artist: 'A',
        duration: const Duration(seconds: 30),
      ),
      track(
        id: 'long',
        title: 'Long',
        artist: 'B',
        duration: const Duration(minutes: 5),
      ),
    ];
    final result = service.search(
      tracks,
      '',
      filters: const LibrarySearchFilters(
        minDuration: Duration(minutes: 2),
        maxDuration: Duration(minutes: 6),
        kind: MediaKind.audio,
      ),
    );
    expect(result.map((item) => item.id), <String>['long']);
  });

  test('normalizes folders and keeps metadata caches instance-specific', () {
    const service = LibrarySearchService();
    final arabicFolder = const MediaTrack(
      id: 'arabic-folder',
      title: 'Old title',
      artist: 'Artist',
      album: 'Album',
      source: TrackSource.local,
      folder: '/مُوسيقى/ألبوم',
    );
    final updatedMetadata = track(
      id: 'arabic-folder',
      title: 'New title',
      artist: 'Artist',
    );

    expect(
      service.search(
        <MediaTrack>[arabicFolder],
        '',
        filters: const LibrarySearchFilters(folder: '/موسيقى/ألبوم'),
      ),
      hasLength(1),
    );
    expect(service.search(<MediaTrack>[arabicFolder], 'old'), hasLength(1));
    expect(service.search(<MediaTrack>[updatedMetadata], 'new'), hasLength(1));
    expect(service.search(<MediaTrack>[updatedMetadata], 'old'), isEmpty);
  });
}
