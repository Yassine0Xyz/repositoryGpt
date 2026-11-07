import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_track.dart';
import 'media_track_codec.dart';

class EchoPlaylist {
  const EchoPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    this.coverTrackId,
    this.additionOrder,
  });

  final String id;
  final String name;
  final List<MediaTrack> tracks;
  final String? coverTrackId;
  final List<String>? additionOrder;

  MediaTrack? get coverTrack {
    final id = coverTrackId;
    if (id == null) return latestAddedTrack;
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return latestAddedTrack;
  }

  List<String> get effectiveAdditionOrder {
    final known = additionOrder ?? tracks.map((track) => track.id).toList();
    return List<String>.unmodifiable(<String>[
      ...known,
      ...tracks.map((track) => track.id).where((id) => !known.contains(id)),
    ]);
  }

  MediaTrack? get latestAddedTrack {
    final byId = <String, MediaTrack>{
      for (final track in tracks) track.id: track,
    };
    for (final id in effectiveAdditionOrder.reversed) {
      final track = byId[id];
      if (track != null) return track;
    }
    return null;
  }

  EchoPlaylist copyWith({
    String? name,
    List<MediaTrack>? tracks,
    String? coverTrackId,
    List<String>? additionOrder,
    bool clearCoverTrackId = false,
  }) {
    return EchoPlaylist(
      id: id,
      name: name ?? this.name,
      tracks: List<MediaTrack>.unmodifiable(tracks ?? this.tracks),
      coverTrackId:
          clearCoverTrackId ? null : (coverTrackId ?? this.coverTrackId),
      additionOrder: List<String>.unmodifiable(
        additionOrder ??
            this.additionOrder ??
            this.tracks.map((track) => track.id),
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'tracks': tracks.map(mediaTrackToJson).toList(growable: false),
    if (coverTrackId != null) 'coverTrackId': coverTrackId,
    if (additionOrder != null) 'additionOrder': additionOrder,
  };

  factory EchoPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'];
    final tracks =
        rawTracks is List
            ? rawTracks
                .whereType<Map>()
                .map(
                  (item) => mediaTrackFromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
            : const <MediaTrack>[];
    return EchoPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled playlist',
      tracks: List<MediaTrack>.unmodifiable(tracks),
      coverTrackId: json['coverTrackId']?.toString(),
      additionOrder:
          json['additionOrder'] is List
              ? (json['additionOrder'] as List)
                  .map((item) => item.toString())
                  .toList(growable: false)
              : tracks.map((track) => track.id).toList(growable: false),
    );
  }
}

/// Persistent metadata for user-created playlists and favorites on this device.
class LocalPlaylistManager extends ChangeNotifier {
  LocalPlaylistManager({
    Future<bool> Function(String key, String value)? writeString,
  }) : _writeStringOverride = writeString;

  static const _playlistsKey = 'yazen.custom_playlists.v1';
  static const _favoritesKey = 'yazen.favorite_tracks.v1';
  static const _historyKey = 'yazen.play_history.v1';
  static const _metadataKey = 'yazen.track_metadata.v1';
  static const _hiddenKey = 'yazen.hidden_tracks.v1';

  SharedPreferences? _preferences;
  final Future<bool> Function(String key, String value)? _writeStringOverride;
  List<EchoPlaylist> _playlists = const <EchoPlaylist>[];
  List<MediaTrack> _favorites = const <MediaTrack>[];
  Set<String>? _favoriteIdsCache;
  Map<String, int> _playCounts = <String, int>{};
  final Map<String, DateTime> _lastPlayed = <String, DateTime>{};
  Map<String, Map<String, String>> _metadata = <String, Map<String, String>>{};
  Set<String> _hiddenIds = <String>{};
  bool _isReady = false;
  Future<void> _writeChain = Future<void>.value();
  int _libraryOverlayRevision = 0;

  bool get isReady => _isReady;
  int get libraryOverlayRevision => _libraryOverlayRevision;
  List<EchoPlaylist> get playlists => _playlists;
  List<MediaTrack> get favorites => _favorites;
  Set<String> get hiddenIds => Set<String>.unmodifiable(_hiddenIds);

  bool isFavorite(MediaTrack track) => _favoriteIds.contains(track.id);

  Set<String> get _favoriteIds =>
      _favoriteIdsCache ??= _favorites.map((track) => track.id).toSet();

  void _invalidateFavoriteIds() => _favoriteIdsCache = null;

  Future<void> initialize() async {
    if (_isReady) return;
    _preferences = await SharedPreferences.getInstance();
    try {
      final savedPlaylists = _preferences!.getString(_playlistsKey);
      final savedFavorites = _preferences!.getString(_favoritesKey);
      _playlists =
          savedPlaylists == null
              ? const <EchoPlaylist>[]
              : _decodePlaylists(savedPlaylists);
      _favorites =
          savedFavorites == null
              ? const <MediaTrack>[]
              : _decodeTracks(savedFavorites);
      _invalidateFavoriteIds();
      _playCounts = _decodeIntMap(_preferences!.getString(_historyKey));
      _metadata = _decodeMetadata(_preferences!.getString(_metadataKey));
      _hiddenIds = _decodeStringSet(_preferences!.getString(_hiddenKey));
    } on FormatException {
      _playlists = const <EchoPlaylist>[];
      _favorites = const <MediaTrack>[];
      _invalidateFavoriteIds();
    }
    _isReady = true;
    // The controller may have indexed songs before this async initialization;
    // publish one overlay revision so metadata and hidden IDs are applied.
    _libraryOverlayRevision++;
    notifyListeners();
  }

  int playCount(String trackId) => _playCounts[trackId] ?? 0;

  DateTime? lastPlayed(String trackId) => _lastPlayed[trackId];

  List<MediaTrack> applyMetadata(Iterable<MediaTrack> tracks) => tracks
      .map((track) {
        final values = _metadata[track.id];
        return values == null
            ? track
            : track.copyWith(
              title: values['title'],
              artist: values['artist'],
              album: values['album'],
            );
      })
      .toList(growable: false);

  Future<void> recordPlayed(MediaTrack track) async {
    _ensureReady();
    _playCounts[track.id] = playCount(track.id) + 1;
    _lastPlayed[track.id] = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// Stores a safe app-local metadata override. It deliberately does not
  /// rewrite the user's media file or MediaStore entry without explicit
  /// Android write-permission support.
  Future<void> updateTrackMetadata(
    String trackId, {
    required String title,
    required String artist,
    required String album,
  }) async {
    _ensureReady();
    final values = <String, String>{
      'title': title.trim().isEmpty ? 'Unknown title' : title.trim(),
      'artist': artist.trim().isEmpty ? 'Unknown artist' : artist.trim(),
      'album': album.trim().isEmpty ? 'Unknown album' : album.trim(),
    };
    _metadata[trackId] = values;
    _libraryOverlayRevision++;
    MediaTrack update(MediaTrack track) =>
        track.id == trackId
            ? track.copyWith(
              title: values['title'],
              artist: values['artist'],
              album: values['album'],
            )
            : track;
    _favorites = List<MediaTrack>.unmodifiable(_favorites.map(update));
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map(
            (playlist) => playlist.copyWith(
              tracks: playlist.tracks.map(update).toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setHidden(
    Iterable<String> trackIds, {
    required bool hidden,
  }) async {
    _ensureReady();
    final previous = Set<String>.of(_hiddenIds);
    if (hidden) {
      _hiddenIds.addAll(trackIds);
    } else {
      _hiddenIds.removeAll(trackIds);
    }
    if (!setEquals(previous, _hiddenIds)) _libraryOverlayRevision++;
    notifyListeners();
    await _persist();
  }

  bool isHidden(String trackId) => _hiddenIds.contains(trackId);

  Future<void> toggleFavorite(MediaTrack track) async {
    _ensureReady();
    final next = List<MediaTrack>.from(_favorites);
    final existingIndex = next.indexWhere((item) => item.id == track.id);
    if (existingIndex >= 0) {
      next.removeAt(existingIndex);
    } else {
      next.add(track);
    }
    _favorites = List<MediaTrack>.unmodifiable(next);
    _invalidateFavoriteIds();
    notifyListeners();
    await _persist();
  }

  Future<EchoPlaylist> createPlaylist(String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Playlist name cannot be empty.');
    }
    final playlist = EchoPlaylist(
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      name: normalized,
      tracks: const <MediaTrack>[],
    );
    _playlists = List<EchoPlaylist>.unmodifiable(<EchoPlaylist>[
      ..._playlists,
      playlist,
    ]);
    notifyListeners();
    await _persist();
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    _ensureReady();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Playlist name cannot be empty.');
    }
    await _enqueueWrite<void>(() async {
      final previousPlaylists = _playlists;
      final playlistIndex = previousPlaylists.indexWhere(
        (playlist) => playlist.id == playlistId,
      );
      if (playlistIndex < 0) {
        throw StateError('Playlist no longer exists.');
      }
      if (previousPlaylists[playlistIndex].name == normalized) return;

      final playlistKey = _playlistsKey;
      final previousSnapshot =
          _preferences!.getString(playlistKey) ?? _encodePlaylists();
      final candidate = List<EchoPlaylist>.unmodifiable(
        previousPlaylists
            .map(
              (playlist) =>
                  playlist.id == playlistId
                      ? playlist.copyWith(name: normalized)
                      : playlist,
            )
            .toList(growable: false),
      );
      final candidateSnapshot = _encodePlaylists(candidate);

      try {
        if (!await _writeString(playlistKey, candidateSnapshot)) {
          throw StateError('Failed to persist the playlist name.');
        }
      } catch (error, stackTrace) {
        try {
          if (!await _writeString(playlistKey, previousSnapshot)) {
            throw StateError('Playlist rollback was not persisted.');
          }
        } catch (rollbackError) {
          Error.throwWithStackTrace(
            StateError(
              'Unable to save playlist name ($error); restoring the previous '
              'saved name also failed ($rollbackError).',
            ),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      _playlists = List<EchoPlaylist>.unmodifiable(
        _playlists
            .map(
              (playlist) =>
                  playlist.id == playlistId
                      ? playlist.copyWith(name: normalized)
                      : playlist,
            )
            .toList(growable: false),
      );
      notifyListeners();
    });
  }

  Future<void> deletePlaylist(String playlistId) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists.where((playlist) => playlist.id != playlistId),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> addToFavorites(Iterable<MediaTrack> tracks) async {
    _ensureReady();
    final next = List<MediaTrack>.from(_favorites);
    for (final track in tracks) {
      if (!next.any((item) => item.id == track.id)) next.add(track);
    }
    _favorites = List<MediaTrack>.unmodifiable(next);
    _invalidateFavoriteIds();
    notifyListeners();
    await _persist();
  }

  Future<void> addToPlaylist(String playlistId, MediaTrack track) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId ||
                playlist.tracks.any((item) => item.id == track.id)) {
              return playlist;
            }
            return playlist.copyWith(
              tracks: <MediaTrack>[...playlist.tracks, track],
              coverTrackId: track.id,
              additionOrder: <String>[
                ...playlist.effectiveAdditionOrder,
                track.id,
              ],
            );
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    Iterable<MediaTrack> tracks,
  ) async {
    _ensureReady();
    final additions = <MediaTrack>[];
    for (final track in tracks) {
      if (!additions.any((item) => item.id == track.id)) additions.add(track);
    }
    if (additions.isEmpty) return;
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId) return playlist;
            final next = List<MediaTrack>.from(playlist.tracks);
            final addedIds = <String>[];
            for (final track in additions) {
              if (!next.any((item) => item.id == track.id)) {
                next.add(track);
                addedIds.add(track.id);
              }
            }
            return addedIds.isEmpty
                ? playlist
                : playlist.copyWith(
                  tracks: next,
                  coverTrackId: addedIds.last,
                  additionOrder: <String>[
                    ...playlist.effectiveAdditionOrder,
                    ...addedIds,
                  ],
                );
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveWithinPlaylist(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    _ensureReady();
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId ||
                oldIndex < 0 ||
                oldIndex >= playlist.tracks.length ||
                newIndex < 0 ||
                newIndex >= playlist.tracks.length) {
              return playlist;
            }
            final tracks = List<MediaTrack>.from(playlist.tracks);
            final track = tracks.removeAt(oldIndex);
            tracks.insert(newIndex, track);
            return playlist.copyWith(tracks: tracks);
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) =>
      removeTracksFromPlaylist(playlistId, <String>{trackId});

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    Iterable<String> trackIds,
  ) async {
    _ensureReady();
    final ids = trackIds.toSet();
    if (ids.isEmpty) return;
    _playlists = List<EchoPlaylist>.unmodifiable(
      _playlists
          .map((playlist) {
            if (playlist.id != playlistId) return playlist;
            final tracks = playlist.tracks
                .where((track) => !ids.contains(track.id))
                .toList(growable: false);
            final additionOrder = playlist.effectiveAdditionOrder
                .where((id) => !ids.contains(id))
                .toList(growable: false);
            final coverId = playlist.coverTrackId;
            final nextCoverId =
                coverId != null && tracks.any((track) => track.id == coverId)
                    ? coverId
                    : (additionOrder.isEmpty ? null : additionOrder.last);
            return nextCoverId == null
                ? playlist.copyWith(
                  tracks: tracks,
                  additionOrder: additionOrder,
                  clearCoverTrackId: true,
                )
                : playlist.copyWith(
                  tracks: tracks,
                  additionOrder: additionOrder,
                  coverTrackId: nextCoverId,
                );
          })
          .toList(growable: false),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> clearFavorites() async {
    _ensureReady();
    _favorites = const <MediaTrack>[];
    _invalidateFavoriteIds();
    notifyListeners();
    await _persist();
  }

  void _ensureReady() {
    if (!_isReady) {
      throw StateError(
        'LocalPlaylistManager.initialize() must complete before use.',
      );
    }
  }

  String _encodePlaylists([List<EchoPlaylist>? playlists]) => jsonEncode(
    (playlists ?? _playlists)
        .map((playlist) => playlist.toJson())
        .toList(growable: false),
  );

  Future<bool> _writeString(String key, String value) async {
    final override = _writeStringOverride;
    if (override != null) return override(key, value);
    return _preferences!.setString(key, value);
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final result = _writeChain.then<T>((_) => operation());
    _writeChain = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Local playlist persistence failed: $error\n$stackTrace');
      },
    );
    return result;
  }

  Future<void> _persist() {
    if (_preferences == null) return Future<void>.value();
    return _enqueueWrite<void>(() async {
      final snapshot = <String, String>{
        _playlistsKey: _encodePlaylists(),
        _favoritesKey: jsonEncode(
          _favorites.map(mediaTrackToJson).toList(growable: false),
        ),
        _historyKey: jsonEncode(<String, dynamic>{
          'counts': _playCounts,
          'lastPlayed': _lastPlayed.map(
            (key, value) => MapEntry(key, value.toIso8601String()),
          ),
        }),
        _metadataKey: jsonEncode(_metadata),
        _hiddenKey: jsonEncode(_hiddenIds.toList()),
      };
      for (final entry in snapshot.entries) {
        if (!await _writeString(entry.key, entry.value)) {
          throw StateError('Failed to persist local playlist data.');
        }
      }
    });
  }

  List<EchoPlaylist> _decodePlaylists(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid playlist data.');
    return List<EchoPlaylist>.unmodifiable(
      decoded
          .whereType<Map>()
          .map((item) => EchoPlaylist.fromJson(Map<String, dynamic>.from(item)))
          .where((playlist) => playlist.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  List<MediaTrack> _decodeTracks(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Invalid favorite data.');
    return List<MediaTrack>.unmodifiable(
      decoded
          .whereType<Map>()
          .map((item) => mediaTrackFromJson(Map<String, dynamic>.from(item)))
          .where((track) => track.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, int> _decodeIntMap(String? value) {
    if (value == null) return <String, int>{};
    try {
      final decoded = jsonDecode(value);
      final counts = decoded is Map ? decoded['counts'] : decoded;
      final last = decoded is Map ? decoded['lastPlayed'] : null;
      if (last is Map) {
        for (final entry in last.entries) {
          final date = DateTime.tryParse(entry.value.toString());
          if (date != null) _lastPlayed[entry.key.toString()] = date;
        }
      }
      return counts is Map
          ? <String, int>{
            for (final entry in counts.entries)
              entry.key.toString():
                  entry.value is num ? (entry.value as num).toInt() : 0,
          }
          : <String, int>{};
    } catch (_) {
      return <String, int>{};
    }
  }

  Map<String, Map<String, String>> _decodeMetadata(String? value) {
    if (value == null) return <String, Map<String, String>>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return <String, Map<String, String>>{};
      return <String, Map<String, String>>{
        for (final entry in decoded.entries)
          entry.key.toString():
              entry.value is Map
                  ? <String, String>{
                    for (final field in (entry.value as Map).entries)
                      field.key.toString(): field.value.toString(),
                  }
                  : <String, String>{},
      };
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  Set<String> _decodeStringSet(String? value) {
    if (value == null) return <String>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is List
          ? decoded.map((item) => item.toString()).toSet()
          : <String>{};
    } catch (_) {
      return <String>{};
    }
  }
}
