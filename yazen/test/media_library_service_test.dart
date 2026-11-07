import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/services/media_library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localMediaChannel = MethodChannel('yazen/local_media');

  test(
    'a denial is not cached and a later settings grant is observed',
    () async {
      var granted = false;
      var statusReads = 0;
      var requests = 0;
      final service = MediaLibraryService(
        permissionStatus: () async {
          statusReads++;
          return granted;
        },
        permissionRequest: () async {
          requests++;
          return granted;
        },
      );

      expect(await service.ensurePermission(requestIfDenied: false), isFalse);
      expect(service.permissionGranted, isNull);

      granted = true;
      expect(await service.recheckPermission(), isTrue);
      expect(service.permissionGranted, isTrue);
      expect(await service.ensurePermission(), isTrue);
      expect(statusReads, 2);
      expect(requests, 0);
    },
  );

  test(
    'an explicit request is deduplicated while permission UI is open',
    () async {
      final permissionResult = Completer<bool>();
      var statusReads = 0;
      var requests = 0;
      final service = MediaLibraryService(
        permissionStatus: () async {
          statusReads++;
          return false;
        },
        permissionRequest: () {
          requests++;
          return permissionResult.future;
        },
      );

      final first = service.requestPermission();
      final second = service.requestPermission();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      permissionResult.complete(false);
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(service.permissionGranted, isNull);
      expect(statusReads, 1);
    },
  );

  test('refresh checks permission without showing a new prompt', () async {
    var granted = false;
    var requests = 0;
    final service = MediaLibraryService(
      permissionStatus: () async => granted,
      permissionRequest: () async {
        requests++;
        return granted;
      },
    );

    expect(await service.ensurePermission(requestIfDenied: false), isFalse);
    granted = true;
    expect(await service.recheckPermission(), isTrue);
    expect(requests, 0);
  });

  test(
    'video permission request awaits a delayed result before scanning',
    () async {
      final permissionResult = Completer<bool>();
      var scans = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localMediaChannel, (call) async {
            if (call.method == 'queryVideos') scans++;
            return <dynamic>[];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localMediaChannel, null),
      );
      final service = MediaLibraryService(
        videoPermissionRequest: () => permissionResult.future,
      );
      var completed = false;
      final videos = service.queryVideos().whenComplete(() => completed = true);

      await Future<void>.delayed(const Duration(milliseconds: 1550));
      expect(completed, isFalse);
      expect(scans, 0);
      permissionResult.complete(true);
      expect(await videos, isEmpty);
      expect(scans, 1);
    },
  );

  test('denied video permission does not scan the library', () async {
    var scans = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localMediaChannel, (call) async {
          if (call.method == 'queryVideos') scans++;
          return <dynamic>[];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localMediaChannel, null),
    );
    final service = MediaLibraryService(
      videoPermissionRequest: () async => false,
    );

    expect(await service.queryVideos(), isEmpty);
    expect(scans, 0);
  });

  test(
    'existing and settings-granted video permissions are rechecked',
    () async {
      var granted = false;
      var requests = 0;
      var scans = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localMediaChannel, (call) async {
            if (call.method == 'queryVideos') scans++;
            return <dynamic>[];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localMediaChannel, null),
      );
      final service = MediaLibraryService(
        videoPermissionStatus: () async => granted,
        videoPermissionRequest: () async {
          requests++;
          return granted;
        },
      );

      expect(await service.queryVideos(requestPermission: false), isEmpty);
      granted = true;
      expect(await service.queryVideos(requestPermission: false), isEmpty);
      expect(await service.queryVideos(), isEmpty);
      expect(requests, 1);
      expect(scans, 2);
    },
  );

  test('folder queries preserve full path identity', () async {
    final service = _FolderLibrary(<MediaTrack>[
      _track('artist-a', '/Music/ArtistA/Live'),
      _track('artist-b', '/Music/ArtistB/Live'),
    ]);

    expect(await service.queryFolders(), <String>[
      '/Music/ArtistA/Live',
      '/Music/ArtistB/Live',
    ]);
    expect(
      (await service.querySongsInFolder(
        '/Music/ArtistA/Live',
      )).map((track) => track.id),
      <String>['artist-a'],
    );
  });
}

MediaTrack _track(String id, String folder) => MediaTrack(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  source: TrackSource.local,
  folder: folder,
  uri: Uri.parse('file:///Music/$id.mp3'),
);

class _FolderLibrary extends MediaLibraryService {
  _FolderLibrary(this.tracks);

  final List<MediaTrack> tracks;

  @override
  Future<bool> ensurePermission({bool requestIfDenied = true}) async => true;

  @override
  Future<List<MediaTrack>> querySongs() async => tracks;
}
