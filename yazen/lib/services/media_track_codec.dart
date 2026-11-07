import '../models/media_track.dart';

Map<String, dynamic> mediaTrackToJson(MediaTrack track) => <String, dynamic>{
  'id': track.id,
  'title': track.title,
  'artist': track.artist,
  'album': track.album,
  'source': track.source.name,
  'kind': track.kind.name,
  'uri': track.uri?.toString(),
  'headers': track.headers,
  'artworkUri': track.artworkUri?.toString(),
  'durationMs': track.duration?.inMilliseconds,
  'folder': track.folder,
  'sizeBytes': track.sizeBytes,
  'modifiedAt': track.modifiedAt?.toIso8601String(),
};

MediaTrack mediaTrackFromJson(Map<String, dynamic> json) {
  final sourceName = json['source']?.toString() ?? TrackSource.local.name;
  final source = TrackSource.values.firstWhere(
    (item) => item.name == sourceName,
    orElse: () => TrackSource.local,
  );
  final kindName = json['kind']?.toString() ?? MediaKind.audio.name;
  final kind = MediaKind.values.firstWhere(
    (item) => item.name == kindName,
    orElse: () => MediaKind.audio,
  );
  final durationMs = json['durationMs'];
  final rawHeaders = json['headers'];
  final headers =
      rawHeaders is Map
          ? <String, String>{
            for (final entry in rawHeaders.entries)
              entry.key.toString(): entry.value.toString(),
          }
          : null;
  return MediaTrack(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Unknown title',
    artist: json['artist']?.toString() ?? 'Unknown artist',
    album: json['album']?.toString() ?? 'Unknown album',
    source: source,
    kind: kind,
    uri: _tryParseUri(json['uri']),
    headers: headers,
    artworkUri: _tryParseUri(json['artworkUri']),
    duration:
        durationMs is num ? Duration(milliseconds: durationMs.toInt()) : null,
    folder: json['folder']?.toString(),
    sizeBytes:
        json['sizeBytes'] is num ? (json['sizeBytes'] as num).toInt() : null,
    modifiedAt: DateTime.tryParse(json['modifiedAt']?.toString() ?? ''),
  );
}

Uri? _tryParseUri(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return Uri.tryParse(text);
}
