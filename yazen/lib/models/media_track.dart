import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

/// A source-agnostic audio/video item used by the UI and playback layer.
class MediaTrack {
  const MediaTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.source,
    this.kind = MediaKind.audio,
    this.albumId,
    this.uri,
    this.headers,
    this.artworkUri,
    this.duration,
    this.folder,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final TrackSource source;
  final MediaKind kind;
  final int? albumId;
  final Uri? uri;
  final Map<String, String>? headers;
  final Uri? artworkUri;
  final Duration? duration;
  final String? folder;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  MediaTrack copyWith({
    String? title,
    String? artist,
    String? album,
    int? sizeBytes,
    DateTime? modifiedAt,
  }) {
    return MediaTrack(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      source: source,
      kind: kind,
      albumId: albumId,
      uri: uri,
      headers: headers,
      artworkUri: artworkUri,
      duration: duration,
      folder: folder,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  bool get isLocal => source == TrackSource.local;
  bool get isRemote => source == TrackSource.remote;
  bool get isVideo => kind == MediaKind.video;

  MediaItem toMediaItem() {
    return MediaItem(
      id: uri?.toString() ?? id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: artworkUri,
      extras: <String, dynamic>{
        'trackId': id,
        'source': source.name,
        'kind': kind.name,
      },
    );
  }

  factory MediaTrack.fromSong(SongModel song) {
    final path = song.data;
    final folder = p.posix.dirname(path.replaceAll(r'\', '/'));
    final modifiedSeconds = song.dateModified;
    return MediaTrack(
      id: song.id.toString(),
      title: song.title.trim().isEmpty ? 'Unknown title' : song.title,
      artist:
          song.artist?.trim().isEmpty ?? true ? 'Unknown artist' : song.artist!,
      album: song.album?.trim().isEmpty ?? true ? 'Unknown album' : song.album!,
      source: TrackSource.local,
      albumId: song.albumId,
      uri: Uri.file(path),
      artworkUri: Uri.parse(
        'content://media/external/audio/media/${song.id}/albumart',
      ),
      duration:
          song.duration == null ? null : Duration(milliseconds: song.duration!),
      folder: folder == '.' ? null : folder,
      sizeBytes: song.size,
      modifiedAt:
          modifiedSeconds == null || modifiedSeconds <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(modifiedSeconds * 1000),
    );
  }

  factory MediaTrack.fromLocalVideo({
    required String path,
    required String title,
    Duration? duration,
    String? contentUri,
    int? sizeBytes,
    DateTime? modifiedAt,
  }) {
    final normalized = contentUri?.trim() ?? '';
    final uri =
        normalized.isNotEmpty
            ? Uri.tryParse(normalized) ?? Uri.file(path)
            : Uri.file(path);
    return MediaTrack(
      id: 'local-video:${uri.toString()}',
      title: title.trim().isEmpty ? 'Local video' : title.trim(),
      artist: 'On this device',
      album: 'Local videos',
      source: TrackSource.local,
      kind: MediaKind.video,
      uri: uri,
      duration: duration,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
    );
  }
}

enum MediaKind { audio, video }

enum TrackSource { local, remote }

enum LibraryTab {
  videos('Local Videos'),
  songs('Songs'),
  playlists('Playlists'),
  folders('Folders'),
  artists('Artists'),
  albums('Albums'),
  hidden('Hidden Files');

  const LibraryTab(this.label);
  final String label;
}
