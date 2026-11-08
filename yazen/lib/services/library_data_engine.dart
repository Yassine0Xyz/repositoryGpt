import '../models/library_query.dart';
import '../models/media_track.dart';
import 'folder_identity.dart';
import 'library_search_service.dart';
import '../diagnostics/core/diagnostics_service.dart';

/// Immutable, indexed view of one complete local-library generation.
///
/// Lists and maps are frozen at construction so widgets and query code can
/// safely retain references while a later scan builds a replacement snapshot.
class LibraryIndexSnapshot {
  LibraryIndexSnapshot._({
    required this.revision,
    required this.allTracks,
    required this.visibleAudioTracks,
    required this.hiddenAudioTracks,
    required this.trackById,
    required this.visibleTracksByFolder,
    required this.folderCounts,
    required this.folders,
  });

  factory LibraryIndexSnapshot.build({
    required int revision,
    required Iterable<MediaTrack> tracks,
    required Iterable<String> hiddenTrackIds,
  }) {
    final all = List<MediaTrack>.unmodifiable(tracks);
    final hiddenIds = hiddenTrackIds.toSet();
    final visible = <MediaTrack>[];
    final hidden = <MediaTrack>[];
    final byId = <String, MediaTrack>{};
    final byFolder = <String, List<MediaTrack>>{};

    for (final track in all) {
      byId[track.id] = track;
      if (hiddenIds.contains(track.id)) {
        hidden.add(track);
        continue;
      }
      visible.add(track);
      final folder = track.folder;
      if (folder == null || folder.isEmpty) continue;
      final identity = normalizeFolderIdentity(folder);
      if (identity.isEmpty) continue;
      (byFolder[identity] ??= <MediaTrack>[]).add(track);
    }

    final folderList = byFolder.keys.toList(growable: false)
      ..sort((a, b) {
        final byLabel = folderDisplayName(
          a,
        ).toLowerCase().compareTo(folderDisplayName(b).toLowerCase());
        return byLabel == 0 ? a.compareTo(b) : byLabel;
      });

    return LibraryIndexSnapshot._(
      revision: revision,
      allTracks: all,
      visibleAudioTracks: List<MediaTrack>.unmodifiable(visible),
      hiddenAudioTracks: List<MediaTrack>.unmodifiable(hidden),
      trackById: Map<String, MediaTrack>.unmodifiable(byId),
      visibleTracksByFolder: Map<String, List<MediaTrack>>.unmodifiable({
        for (final entry in byFolder.entries)
          entry.key: List<MediaTrack>.unmodifiable(entry.value),
      }),
      folderCounts: Map<String, int>.unmodifiable({
        for (final entry in byFolder.entries) entry.key: entry.value.length,
      }),
      folders: List<String>.unmodifiable(folderList),
    );
  }

  final int revision;
  final List<MediaTrack> allTracks;
  final List<MediaTrack> visibleAudioTracks;
  final List<MediaTrack> hiddenAudioTracks;
  final Map<String, MediaTrack> trackById;
  final Map<String, List<MediaTrack>> visibleTracksByFolder;
  final Map<String, int> folderCounts;
  final List<String> folders;

  List<MediaTrack> tracksInFolder(String folder) =>
      visibleTracksByFolder[normalizeFolderIdentity(folder)] ??
      const <MediaTrack>[];
}

/// Owns indexed local-library data and memoizes the current view query.
///
/// Device I/O stays in [MediaLibraryService]. This class is deliberately
/// synchronous: scans replace a snapshot atomically, while scrolling and
/// search only read immutable in-memory data.
class LibraryDataEngine {
  LibraryDataEngine({
    LibrarySearchService searchService = const LibrarySearchService(),
  }) : _searchService = searchService;

  final LibrarySearchService _searchService;
  int _revision = 0;
  LibraryIndexSnapshot _snapshot = LibraryIndexSnapshot.build(
    revision: 0,
    tracks: const <MediaTrack>[],
    hiddenTrackIds: const <String>[],
  );

  List<MediaTrack>? _queryCache;
  List<MediaTrack>? _querySource;
  List<MediaTrack>? _orderedCache;
  List<MediaTrack>? _orderedSource;
  LibrarySort? _orderedSort;
  Set<LibraryFilter>? _orderedFilters;
  int _orderedDynamicRevision = -1;
  LibrarySort? _querySort;
  Set<LibraryFilter>? _queryFilters;
  String? _queryText;
  int _queryDynamicRevision = -1;
  final Expando<_TrackSortKeys> _sortKeys = Expando<_TrackSortKeys>(
    'YAZEN library sort keys',
  );

  LibraryIndexSnapshot get snapshot => _snapshot;

  /// Atomically publishes a new immutable snapshot and drops stale results.
  LibraryIndexSnapshot rebuild({
    required Iterable<MediaTrack> tracks,
    required Iterable<String> hiddenTrackIds,
  }) {
    final span = DiagnosticsService.instance.startSpan('library_index_snapshot_build', data: <String, Object?>{
      'revision': _revision + 1,
      'inputTrackCount': tracks is List ? tracks.length : null,
    });
    try {
      _snapshot = LibraryIndexSnapshot.build(
        revision: ++_revision,
        tracks: tracks,
        hiddenTrackIds: hiddenTrackIds,
      );
      invalidateQueries();
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
        'trackCount': _snapshot.allTracks.length,
        'visibleTrackCount': _snapshot.visibleAudioTracks.length,
        'hiddenTrackCount': _snapshot.hiddenAudioTracks.length,
        'folderCount': _snapshot.folders.length,
      });
      return _snapshot;
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{'error': error.toString()});
      rethrow;
    }
  }

  /// Invalidates queries whose result depends on mutable playlist metadata.
  void invalidateQueries() {
    _queryCache = null;
    _querySource = null;
    _querySort = null;
    _queryFilters = null;
    _queryText = null;
    _queryDynamicRevision = -1;
    _orderedCache = null;
    _orderedSource = null;
    _orderedSort = null;
    _orderedFilters = null;
    _orderedDynamicRevision = -1;
  }

  List<MediaTrack> queryTracks({
    required List<MediaTrack> source,
    required LibrarySort sort,
    required Set<LibraryFilter> filters,
    required String query,
    required bool Function(MediaTrack track) isFavorite,
    required int Function(String trackId) playCount,
    required DateTime? Function(String trackId) lastPlayed,
    int dynamicRevision = 0,
  }) {
    if (identical(_querySource, source) &&
        _querySort == sort &&
        _sameFilters(_queryFilters, filters) &&
        _queryText == query &&
        _queryDynamicRevision == dynamicRevision &&
        _queryCache != null) {
      return _queryCache!;
    }

    // Keep sorting independent from search text. Typing a new character then
    // performs only the linear text match; the potentially expensive sort is
    // reused until the source, filters, or sort mode actually changes.
    final ordered = _orderedFilteredTracks(
      source: source,
      sort: sort,
      filters: filters,
      isFavorite: isFavorite,
      playCount: playCount,
      lastPlayed: lastPlayed,
      dynamicRevision: dynamicRevision,
    );
    final searchSpan = DiagnosticsService.instance.startSpan('library_search_filter', data: <String, Object?>{
      'sourceCount': ordered.length,
      'queryLength': query.length,
      'sort': sort.name,
      'filters': filters.map((filter) => filter.name).toList(growable: false),
    });
    final result = _searchService.search(ordered, query);
    DiagnosticsService.instance.endSpan(searchSpan, 'complete', <String, Object?>{'resultCount': result.length});

    _querySource = source;
    _querySort = sort;
    _queryFilters = Set<LibraryFilter>.unmodifiable(filters);
    _queryText = query;
    _queryDynamicRevision = dynamicRevision;
    _queryCache = result;
    return result;
  }

  List<MediaTrack> _orderedFilteredTracks({
    required List<MediaTrack> source,
    required LibrarySort sort,
    required Set<LibraryFilter> filters,
    required bool Function(MediaTrack track) isFavorite,
    required int Function(String trackId) playCount,
    required DateTime? Function(String trackId) lastPlayed,
    required int dynamicRevision,
  }) {
    if (identical(_orderedSource, source) &&
        _orderedSort == sort &&
        _sameFilters(_orderedFilters, filters) &&
        _orderedDynamicRevision == dynamicRevision &&
        _orderedCache != null) {
      return _orderedCache!;
    }

    final transformSpan = DiagnosticsService.instance.startSpan('library_sort_filter', data: <String, Object?>{
      'sourceCount': source.length,
      'sort': sort.name,
      'filters': filters.map((filter) => filter.name).toList(growable: false),
    });
    final filtered = source.where((track) {
      if (filters.contains(LibraryFilter.favorites) && !isFavorite(track)) {
        return false;
      }
      if (filters.contains(LibraryFilter.importedFiles) &&
          !track.id.startsWith('local-file:')) {
        return false;
      }
      if (filters.contains(LibraryFilter.missingAlbum) &&
          track.album.trim().isNotEmpty &&
          track.album.toLowerCase() != 'unknown album') {
        return false;
      }
      return true;
    });
    final candidates = List<MediaTrack>.of(filtered);
    // Dynamic playlist statistics are stable for this query generation. Read
    // them once per track instead of repeatedly invoking provider callbacks
    // from the O(n log n) comparator.
    final playCounts =
        sort == LibrarySort.mostPlayed
            ? <String, int>{
                for (final track in candidates) track.id: playCount(track.id),
              }
            : const <String, int>{};
    final playedAt =
        sort == LibrarySort.recentlyPlayedFirst
            ? <String, DateTime?>{
                for (final track in candidates) track.id: lastPlayed(track.id),
              }
            : const <String, DateTime?>{};
    candidates.sort(
      (a, b) => _compareTracks(
        a,
        b,
        sort,
        playCounts: playCounts,
        playedAt: playedAt,
      ),
    );
    final sorted = candidates;
    final result = List<MediaTrack>.unmodifiable(sorted);
    _orderedSource = source;
    _orderedSort = sort;
    _orderedFilters = Set<LibraryFilter>.unmodifiable(filters);
    _orderedDynamicRevision = dynamicRevision;
    _orderedCache = result;
    DiagnosticsService.instance.endSpan(transformSpan, 'complete', <String, Object?>{'resultCount': result.length});
    return result;
  }

  List<MediaTrack> sortTracks(
    Iterable<MediaTrack> tracks,
    LibrarySort sort, {
    required int Function(String trackId) playCount,
    required DateTime? Function(String trackId) lastPlayed,
  }) {
    final sorted = List<MediaTrack>.of(tracks);
    final playCounts =
        sort == LibrarySort.mostPlayed
            ? <String, int>{
                for (final track in sorted) track.id: playCount(track.id),
              }
            : const <String, int>{};
    final playedAt =
        sort == LibrarySort.recentlyPlayedFirst
            ? <String, DateTime?>{
                for (final track in sorted) track.id: lastPlayed(track.id),
              }
            : const <String, DateTime?>{};
    sorted.sort(
      (a, b) => _compareTracks(
        a,
        b,
        sort,
        playCounts: playCounts,
        playedAt: playedAt,
      ),
    );
    // Keep the controller's existing mutable-list contract for entity screens.
    return sorted;
  }

  int _compareTracks(
    MediaTrack a,
    MediaTrack b,
    LibrarySort sort, {
    required Map<String, int> playCounts,
    required Map<String, DateTime?> playedAt,
  }) {
    final aKeys = _sortKeys[a] ??= _TrackSortKeys(a);
    final bKeys = _sortKeys[b] ??= _TrackSortKeys(b);
    final int primary;
    switch (sort) {
      case LibrarySort.newestFirst:
        primary = _modifiedAt(b).compareTo(_modifiedAt(a));
      case LibrarySort.oldestFirst:
        primary = _modifiedAt(a).compareTo(_modifiedAt(b));
      case LibrarySort.sizeLowToHigh:
        primary = (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
      case LibrarySort.sizeHighToLow:
        primary = (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
      case LibrarySort.durationShortToLong:
        primary = (a.duration ?? Duration.zero).compareTo(
          b.duration ?? Duration.zero,
        );
      case LibrarySort.durationLongToShort:
        primary = (b.duration ?? Duration.zero).compareTo(
          a.duration ?? Duration.zero,
        );
      case LibrarySort.nameAZ:
        primary = aKeys.title.compareTo(bKeys.title);
      case LibrarySort.nameZA:
        primary = bKeys.title.compareTo(aKeys.title);
      case LibrarySort.artistAZ:
        primary = aKeys.artist.compareTo(bKeys.artist);
      case LibrarySort.mostPlayed:
        primary = (playCounts[b.id] ?? 0).compareTo(playCounts[a.id] ?? 0);
      case LibrarySort.recentlyPlayedFirst:
        primary = _dateOrEpoch(
          playedAt[b.id],
        ).compareTo(_dateOrEpoch(playedAt[a.id]));
    }
    if (primary != 0) return primary;
    final title = aKeys.title.compareTo(bKeys.title);
    if (title != 0) return title;
    return a.id.compareTo(b.id);
  }

  static DateTime _modifiedAt(MediaTrack track) =>
      track.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime _dateOrEpoch(DateTime? value) =>
      value ?? DateTime.fromMillisecondsSinceEpoch(0);

  static bool _sameFilters(Set<LibraryFilter>? a, Set<LibraryFilter> b) =>
      a != null && a.length == b.length && a.containsAll(b);
}

class _TrackSortKeys {
  _TrackSortKeys(MediaTrack track)
    : title = track.title.toLowerCase(),
      artist = track.artist.toLowerCase();

  final String title;
  final String artist;
}
