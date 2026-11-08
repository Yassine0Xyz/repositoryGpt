import 'dart:async';

import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/media_track.dart';
import '../diagnostics/core/diagnostics_service.dart';
import 'folder_identity.dart';

class MediaLibraryService {
  MediaLibraryService({
    OnAudioQuery? audioQuery,
    Future<bool> Function()? permissionStatus,
    Future<bool> Function()? permissionRequest,
    Future<bool> Function()? videoPermissionStatus,
    Future<bool> Function()? videoPermissionRequest,
  }) : _audioQuery = audioQuery ?? OnAudioQuery(),
       _permissionStatusReader = permissionStatus,
       _permissionRequester = permissionRequest,
       _videoPermissionStatusReader = videoPermissionStatus,
       _videoPermissionRequester = videoPermissionRequest;

  static const MethodChannel _localMediaChannel = MethodChannel(
    'yazen/local_media',
  );

  final OnAudioQuery _audioQuery;
  final Future<bool> Function()? _permissionStatusReader;
  final Future<bool> Function()? _permissionRequester;
  final Future<bool> Function()? _videoPermissionStatusReader;
  final Future<bool> Function()? _videoPermissionRequester;
  bool? _permissionGranted;
  Future<bool>? _permissionRequest;

  bool? get permissionGranted => _permissionGranted;

  Future<bool> ensurePermission({bool requestIfDenied = true}) {
    if (_permissionGranted == true) return Future<bool>.value(true);
    return _runPermissionOperation(() async {
      final granted = await _readPermissionStatus();
      if (granted || !requestIfDenied) return granted;
      return _requestPermissionDirect();
    });
  }

  /// Re-checks the current grant without opening a permission prompt.
  /// Denials are not cached, so grants made in system Settings are observable.
  Future<bool> recheckPermission() =>
      _runPermissionOperation(_readPermissionStatus);

  /// Requests permission only when the caller explicitly asks the user.
  Future<bool> requestPermission() {
    if (_permissionGranted == true) return Future<bool>.value(true);
    return _runPermissionOperation(() async {
      if (await _readPermissionStatus()) return true;
      return _requestPermissionDirect();
    });
  }

  Future<bool> _runPermissionOperation(Future<bool> Function() operation) {
    final activeRequest = _permissionRequest;
    if (activeRequest != null) return activeRequest;
    final request = Future<bool>.sync(operation);
    _permissionRequest = request;
    return request.whenComplete(() {
      if (identical(_permissionRequest, request)) _permissionRequest = null;
    });
  }

  Future<bool> _readPermissionStatus() async {
    try {
      final granted =
          await (_permissionStatusReader?.call() ??
              _audioQuery.permissionsStatus());
      _permissionGranted = granted ? true : null;
      return granted;
    } catch (_) {
      _permissionGranted = null;
      return false;
    }
  }

  Future<bool> _requestPermissionDirect() async {
    try {
      final granted =
          await (_permissionRequester?.call() ??
              _audioQuery.permissionsRequest());
      _permissionGranted = granted ? true : null;
      return granted;
    } catch (_) {
      _permissionGranted = null;
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _localMediaChannel.invokeMethod<bool>('openAppSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> shareAudioTracks(Iterable<MediaTrack> tracks) async {
    final ids = _mediaStoreIds(tracks);
    if (ids.isEmpty) throw ArgumentError('Select at least one audio track.');
    await _localMediaChannel.invokeMethod<void>(
      'shareAudioTracks',
      <String, Object?>{'ids': ids},
    );
  }

  Future<int> deleteAudioTracks(Iterable<MediaTrack> tracks) async {
    final ids = _mediaStoreIds(tracks);
    if (ids.isEmpty) throw ArgumentError('Select at least one audio track.');
    final deleted = await _localMediaChannel.invokeMethod<List<dynamic>>(
      'deleteAudioTracks',
      <String, Object?>{'ids': ids},
    );
    return deleted?.length ?? 0;
  }

  List<int> _mediaStoreIds(Iterable<MediaTrack> tracks) {
    final ids = <int>[];
    for (final track in tracks) {
      if (track.isVideo) {
        throw UnsupportedError('Only audio tracks can be shared or deleted.');
      }
      final id = int.tryParse(track.id);
      if (id == null) {
        throw UnsupportedError(
          'This track is not stored in the Android media library.',
        );
      }
      ids.add(id);
    }
    return ids;
  }

  Future<List<MediaTrack>> querySongs() =>
      _measure<List<MediaTrack>>('media_query_all_songs', () async {
        if (!await ensurePermission()) return const <MediaTrack>[];
        final songs = await _audioQuery.querySongs(
          sortType: SongSortType.TITLE,
          orderType: OrderType.ASC_OR_SMALLER,
          ignoreCase: true,
        );
        return _toMediaTracks(songs);
      });

  Future<List<MediaTrack>> querySongsFrom(
    AudiosFromType type,
    Object where,
  ) => _measure<List<MediaTrack>>('media_query_filtered_songs', () async {
    if (!await ensurePermission()) return const <MediaTrack>[];
    final songs = await _audioQuery.queryAudiosFrom(
      type,
      where,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );
    return _toMediaTracks(songs);
  });

  Future<List<MediaTrack>> querySongsInFolder(String folder) async {
    final songs = await querySongs();
    return tracksInFolder(songs, folder);
  }

  List<MediaTrack> _toMediaTracks(Iterable<SongModel> songs) {
    final span = DiagnosticsService.instance.startSpan('media_song_model_mapping', data: <String, Object?>{'inputCount': songs is List ? songs.length : null});
    try {
      final tracks = List<MediaTrack>.unmodifiable(songs.map(MediaTrack.fromSong));
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{'trackCount': tracks.length});
      return tracks;
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{'error': error.toString()});
      rethrow;
    }
  }

  Future<List<ArtistModel>> queryArtists() =>
      _measure<List<ArtistModel>>('media_query_artists', () async {
        if (!await ensurePermission()) return const <ArtistModel>[];
        return _audioQuery.queryArtists(
          sortType: ArtistSortType.ARTIST,
          orderType: OrderType.ASC_OR_SMALLER,
          ignoreCase: true,
        );
      });

  Future<List<AlbumModel>> queryAlbums() =>
      _measure<List<AlbumModel>>('media_query_albums', () async {
        if (!await ensurePermission()) return const <AlbumModel>[];
        return _audioQuery.queryAlbums(
          sortType: AlbumSortType.ALBUM,
          orderType: OrderType.ASC_OR_SMALLER,
          ignoreCase: true,
        );
      });

  Future<List<PlaylistModel>> queryPlaylists() =>
      _measure<List<PlaylistModel>>('media_query_playlists', () async {
        if (!await ensurePermission()) return const <PlaylistModel>[];
        return _audioQuery.queryPlaylists(
          sortType: PlaylistSortType.PLAYLIST,
          orderType: OrderType.ASC_OR_SMALLER,
          ignoreCase: true,
        );
      });

  Future<List<String>> queryFolders() async {
    final span = DiagnosticsService.instance.startSpan('media_folder_identity_build');
    try {
      final songs = await querySongs();
      final folders = folderIdentities(songs);
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{'trackCount': songs.length, 'folderCount': folders.length});
      return folders;
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{'error': error.toString()});
      rethrow;
    }
  }

  Future<List<MediaTrack>> queryVideos({bool requestPermission = true}) =>
      _measure<List<MediaTrack>>('media_query_videos', () async {
    final bool granted;
    try {
      granted =
          requestPermission
              ? await (_videoPermissionRequester?.call() ??
                      _localMediaChannel.invokeMethod<bool>(
                        'requestVideoPermission',
                      )) ??
                  false
              : await (_videoPermissionStatusReader?.call() ??
                      _localMediaChannel.invokeMethod<bool>(
                        'videoPermissionStatus',
                      )) ??
                  false;
    } on MissingPluginException {
      return const <MediaTrack>[];
    }
    if (!granted) return const <MediaTrack>[];

    final raw = await _localMediaChannel.invokeMethod<List<dynamic>>(
      'queryVideos',
    );
    if (raw == null) return const <MediaTrack>[];
    final mappingSpan = DiagnosticsService.instance.startSpan('media_video_dart_mapping', data: <String, Object?>{'rawEntryCount': raw.length});
    try {
      final mapped = raw
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) {
            final path = entry['path']?.toString() ?? '';
            final uri = entry['uri']?.toString();
            final title = entry['title']?.toString() ?? 'Local video';
            final durationMs =
                entry['durationMs'] is num
                    ? (entry['durationMs'] as num).toInt()
                    : 0;
            final sizeBytes =
                entry['sizeBytes'] is num
                    ? (entry['sizeBytes'] as num).toInt()
                    : null;
            final dateAdded =
                entry['dateAdded'] is num
                    ? (entry['dateAdded'] as num).toInt()
                    : 0;
            return MediaTrack.fromLocalVideo(
              path: path,
              contentUri: uri,
              title: title,
              duration:
                  durationMs > 0 ? Duration(milliseconds: durationMs) : null,
              sizeBytes: sizeBytes,
              modifiedAt:
                  dateAdded > 0
                      ? DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000)
                      : null,
            );
          })
          .toList(growable: false);
      DiagnosticsService.instance.endSpan(mappingSpan, 'complete', <String, Object?>{'trackCount': mapped.length});
      return mapped;
    } catch (error) {
      DiagnosticsService.instance.endSpan(mappingSpan, 'failed', <String, Object?>{'error': error.toString()});
      rethrow;
    }
  });

  Future<T> _measure<T>(String operation, Future<T> Function() work) async {
    final span = DiagnosticsService.instance.startSpan(operation);
    try {
      final result = await work();
      final count = result is Iterable ? result.length : null;
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{'itemCount': count});
      return result;
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{'error': error.toString()});
      rethrow;
    }
  }
}
