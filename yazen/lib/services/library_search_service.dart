import '../models/media_track.dart';

class LibrarySearchFilters {
  const LibrarySearchFilters({
    this.minDuration,
    this.maxDuration,
    this.folder,
    this.kind,
  });

  final Duration? minDuration;
  final Duration? maxDuration;
  final String? folder;
  final MediaKind? kind;
}

/// Fast in-memory search over the already indexed local library.
/// It never performs I/O and is safe to call on every keystroke.
class LibrarySearchService {
  const LibrarySearchService();

  static final RegExp _arabicDiacritics = RegExp(r'[\u064B-\u065F\u0670]');
  static final Expando<String> _searchTextCache = Expando<String>(
    'YAZEN normalized media search text',
  );
  static final Expando<String> _folderCache = Expando<String>(
    'YAZEN normalized media folder',
  );

  List<MediaTrack> search(
    Iterable<MediaTrack> tracks,
    String query, {
    LibrarySearchFilters filters = const LibrarySearchFilters(),
  }) {
    final normalized = _normalize(query);
    return tracks
        .where((track) => _matches(track, normalized, filters))
        .toList(growable: false);
  }

  bool _matches(MediaTrack track, String query, LibrarySearchFilters filters) {
    if (filters.kind != null && track.kind != filters.kind) return false;
    if (filters.minDuration != null &&
        (track.duration ?? Duration.zero) < filters.minDuration!) {
      return false;
    }
    if (filters.maxDuration != null &&
        (track.duration ?? Duration.zero) > filters.maxDuration!) {
      return false;
    }
    if (filters.folder != null) {
      final normalizedFolder =
          _folderCache[track] ?? _normalize(track.folder ?? '');
      _folderCache[track] = normalizedFolder;
      if (!normalizedFolder.contains(_normalize(filters.folder!))) {
        return false;
      }
    }
    if (query.isEmpty) return true;
    final cachedText = _searchTextCache[track];
    final haystack =
        cachedText ??
        _normalize(
          '${track.title} ${track.artist} ${track.album} ${track.folder ?? ''}',
        );
    _searchTextCache[track] = haystack;
    return haystack.contains(query);
  }

  String _normalize(String value) =>
      value
          .toLowerCase()
          .replaceAll(_arabicDiacritics, '')
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ى', 'ي')
          .replaceAll('ة', 'ه')
          .trim();
}

extension MediaTrackSearch on Iterable<MediaTrack> {
  List<MediaTrack> searchLocal(
    String query, {
    LibrarySearchFilters filters = const LibrarySearchFilters(),
  }) => const LibrarySearchService().search(this, query, filters: filters);
}
