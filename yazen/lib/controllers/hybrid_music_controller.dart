import 'package:audio_service/audio_service.dart';

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import '../models/media_track.dart';
import '../models/library_query.dart';
import '../services/hybrid_audio_handler.dart';
import '../services/playback_policies.dart';
import '../services/lyrics_service.dart';
import '../services/media_library_service.dart';
import '../services/local_playlist_manager.dart';
import '../services/library_data_engine.dart';
import '../diagnostics/core/diagnostics_service.dart';

export '../models/library_query.dart' show LibraryFilter, LibrarySort;

class HybridMusicController extends ChangeNotifier with WidgetsBindingObserver {
  HybridMusicController({
    required MediaLibraryService library,
    required HybridAudioHandler audioHandler,
    required LocalPlaylistManager playlistManager,
    LyricsService? lyricsService,
  }) : _library = library,
       _audioHandler = audioHandler,
       _playlistManager = playlistManager,
       _lyricsService = lyricsService ?? LyricsService() {
    _playlistManager.addListener(_onPlaylistChanged);
    _lastLibraryOverlayRevision = _playlistManager.libraryOverlayRevision;
    WidgetsBinding.instance.addObserver(this);
  }

  static const Set<String> _audioFileExtensions = <String>{
    '.aac',
    '.aiff',
    '.alac',
    '.flac',
    '.m4a',
    '.mp3',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
  };
  static const Set<String> _videoFileExtensions = <String>{
    '.3gp',
    '.avi',
    '.m4v',
    '.mkv',
    '.mov',
    '.mp4',
    '.webm',
  };

  static List<MediaTrack> _mergeTracks(
    Iterable<MediaTrack> libraryTracks,
    Iterable<MediaTrack> importedTracks,
  ) {
    final tracksById = <String, MediaTrack>{
      for (final track in libraryTracks) track.id: track,
    };
    for (final track in importedTracks) {
      tracksById[track.id] = track;
    }
    return List<MediaTrack>.unmodifiable(tracksById.values);
  }

  final MediaLibraryService _library;
  final HybridAudioHandler _audioHandler;
  final LocalPlaylistManager _playlistManager;
  final LyricsService _lyricsService;
  final LibraryDataEngine _libraryDataEngine = LibraryDataEngine();
  int _dynamicLibraryRevision = 0;

  bool get _usesLinuxImportedFileMode =>
      Platform.isLinux && _library.runtimeType == MediaLibraryService;

  LibraryTab _selectedTab = LibraryTab.songs;
  List<MediaTrack> _baseLocalSongs = const <MediaTrack>[];
  List<MediaTrack> _localSongs = const <MediaTrack>[];
  List<MediaTrack> _localVideos = const <MediaTrack>[];
  final Map<String, MediaTrack> _importedAudioFiles = <String, MediaTrack>{};
  final Map<String, MediaTrack> _importedVideoFiles = <String, MediaTrack>{};
  List<ArtistModel> _artists = const <ArtistModel>[];
  List<AlbumModel> _albums = const <AlbumModel>[];
  List<PlaylistModel> _playlists = const <PlaylistModel>[];
  List<String> _folders = const <String>[];
  bool _isLoading = false;
  bool _libraryLoadInProgress = false;
  final Map<LibraryTab, LibrarySort> _librarySortByTab =
      <LibraryTab, LibrarySort>{
        LibraryTab.songs: LibrarySort.newestFirst,
        LibraryTab.videos: LibrarySort.newestFirst,
      };
  final Map<LibraryTab, Set<LibraryFilter>> _libraryFiltersByTab =
      <LibraryTab, Set<LibraryFilter>>{
        LibraryTab.songs: <LibraryFilter>{},
        LibraryTab.videos: <LibraryFilter>{},
      };
  String? _errorMessage;
  final Map<LibraryTab, String> _searchQueryByTab = <LibraryTab, String>{
    LibraryTab.songs: '',
    LibraryTab.videos: '',
  };
  bool _videosLoading = false;
  bool _videosPermissionAttempted = false;
  bool _secondaryLibraryLoading = false;
  bool _secondaryLibraryLoaded = false;
  bool _permissionRequired = false;
  int _lastLibraryOverlayRevision = 0;
  int _playbackSelectionRequest = 0;
  int _libraryLoadGeneration = 0;
  bool _refreshQueuedDuringLoad = false;
  bool _disposed = false;
  int _secondaryLibraryGeneration = 0;

  LibraryTab get selectedTab => _selectedTab;
  List<MediaTrack> get localSongs => _localSongs;
  List<MediaTrack> get hiddenTracks =>
      _libraryDataEngine.snapshot.hiddenAudioTracks;
  List<MediaTrack> get localVideos => _localVideos;
  List<ArtistModel> get artists => _artists;
  List<AlbumModel> get albums => _albums;
  List<PlaylistModel> get playlists => _playlists;
  List<String> get folders => _folders;
  Map<String, int> get folderTrackCounts =>
      _libraryDataEngine.snapshot.folderCounts;
  bool get isLoading => _isLoading;
  bool get permissionRequired => _permissionRequired;
  AudioServiceRepeatMode get repeatMode => _audioHandler.repeatMode;
  bool get repeatOne => repeatMode == AudioServiceRepeatMode.one;
  LibrarySort get librarySort =>
      _librarySortByTab[_selectedTab] ?? LibrarySort.newestFirst;
  Set<LibraryFilter> get libraryFilters => Set<LibraryFilter>.unmodifiable(
    _libraryFiltersByTab[_selectedTab] ?? const <LibraryFilter>{},
  );
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQueryByTab[_selectedTab] ?? '';
  MediaTrack? get activeTrack => _audioHandler.activeTrack;
  HybridAudioHandler get audioHandler => _audioHandler;
  LyricsService get lyricsService => _lyricsService;
  LocalPlaylistManager get playlistManager => _playlistManager;
  LibraryIndexSnapshot get librarySnapshot => _libraryDataEngine.snapshot;

  List<MediaTrack> get visibleTracks {
    final tracks = switch (_selectedTab) {
      LibraryTab.videos => _localVideos,
      LibraryTab.playlists => _localSongs,
      LibraryTab.folders => _localSongs,
      LibraryTab.artists => _localSongs,
      LibraryTab.albums => _localSongs,
      LibraryTab.songs => _localSongs,
      LibraryTab.hidden => hiddenTracks,
    };
    return _libraryDataEngine.queryTracks(
      source: tracks,
      sort: librarySort,
      filters: _libraryFiltersByTab[_selectedTab] ?? const <LibraryFilter>{},
      query: searchQuery,
      isFavorite: _playlistManager.isFavorite,
      playCount: _playlistManager.playCount,
      lastPlayed: _playlistManager.lastPlayed,
      dynamicRevision: _dynamicLibraryRevision,
    );
  }

  void setLibrarySort(LibrarySort sort) {
    if (librarySort == sort) return;
    DiagnosticsService.instance.record(
      'library_sort_changed',
      <String, Object?>{'tab': _selectedTab.name, 'sort': sort.name},
    );
    _librarySortByTab[_selectedTab] = sort;
    _libraryDataEngine.invalidateQueries();
    notifyListeners();
  }

  void setLibraryFilters(Iterable<LibraryFilter> filters) {
    final next = filters.toSet()..remove(LibraryFilter.all);
    final current = _libraryFiltersByTab[_selectedTab] ?? <LibraryFilter>{};
    if (current.length == next.length && current.containsAll(next)) return;
    DiagnosticsService.instance
        .record('library_filters_changed', <String, Object?>{
          'tab': _selectedTab.name,
          'filters': next.map((filter) => filter.name).toList(growable: false),
        });
    _libraryFiltersByTab[_selectedTab] = next;
    _libraryDataEngine.invalidateQueries();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    final normalized = query.trim();
    if (searchQuery == normalized) return;
    DiagnosticsService.instance.record(
      'library_search_changed',
      <String, Object?>{
        'tab': _selectedTab.name,
        'queryLength': normalized.length,
      },
    );
    _searchQueryByTab[_selectedTab] = normalized;
    // The engine's ordered/filter cache is independent of search text, so a
    // keystroke only invalidates the final text-match cache by query key.
    notifyListeners();
  }

  List<MediaTrack> orderedTracks(Iterable<MediaTrack> tracks) =>
      _libraryDataEngine.sortTracks(
        tracks,
        librarySort,
        playCount: _playlistManager.playCount,
        lastPlayed: _playlistManager.lastPlayed,
      );

  Future<void> loadLibrary({
    bool requestPermission = true,
    bool preserveCurrentLibrary = false,
  }) async {
    // A refresh should publish its replacement snapshot atomically while the
    // current list stays visible. Initial loading still uses the loading state.
    _libraryLoadInProgress = true;
    var shouldLoadSecondaryCatalogs = false;
    if (!preserveCurrentLibrary) _setLoading(true);
    final loadGeneration = ++_libraryLoadGeneration;
    // Any in-flight secondary catalog query belongs to the previous scan.
    // It may finish, but must never publish stale artists/albums/playlists.
    _secondaryLibraryGeneration++;
    _secondaryLibraryLoaded = false;
    _errorMessage = null;

    try {
      if (_usesLinuxImportedFileMode) {
        _permissionRequired = false;
        _baseLocalSongs = _mergeTracks(
          const <MediaTrack>[],
          _importedAudioFiles.values,
        );
        _localVideos = _mergeTracks(
          const <MediaTrack>[],
          _importedVideoFiles.values,
        );
        _rebuildLibraryDerivedLists();
        return;
      }
      if (!await _library.ensurePermission(
        requestIfDenied: requestPermission,
      )) {
        if (loadGeneration == _libraryLoadGeneration) {
          _markPermissionRequired();
        }
        return;
      }
      if (loadGeneration != _libraryLoadGeneration) return;
      _permissionRequired = false;
      // Songs are the critical path. Defer secondary catalogs until the first
      // list is visible so a large library never blocks first paint.
      final songs = await _library.querySongs();
      // A newer scan may have started while MediaStore was responding. Never
      // let an older result replace the newer library snapshot.
      if (loadGeneration != _libraryLoadGeneration) return;
      _baseLocalSongs = _mergeTracks(songs, _importedAudioFiles.values);
      _artists = const <ArtistModel>[];
      _albums = const <AlbumModel>[];
      _playlists = const <PlaylistModel>[];
      _secondaryLibraryLoaded = false;
      _rebuildLibraryDerivedLists();
      shouldLoadSecondaryCatalogs = true;
    } catch (error) {
      if (loadGeneration == _libraryLoadGeneration) {
        _errorMessage = 'Unable to read the device music library: $error';
      }
    } finally {
      _libraryLoadInProgress = false;
      var refreshQueued = false;
      if (!preserveCurrentLibrary) _setLoading(false);
      if (_refreshQueuedDuringLoad) {
        _refreshQueuedDuringLoad = false;
        refreshQueued = true;
      }
      if (refreshQueued) {
        unawaited(refreshLibrary());
      } else if (shouldLoadSecondaryCatalogs &&
          !_disposed &&
          loadGeneration == _libraryLoadGeneration &&
          !_permissionRequired) {
        // Start secondary catalogs only after the primary Songs result has
        // been published and the initial loading state has been cleared.
        unawaited(_loadSecondaryLibraryData(loadGeneration));
      }
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    if (_isLoading || _libraryLoadInProgress) {
      _refreshQueuedDuringLoad = true;
      return;
    }
    if (_usesLinuxImportedFileMode) {
      await loadLibrary(requestPermission: false, preserveCurrentLibrary: true);
      return;
    }
    if (!await _library.recheckPermission()) {
      _markPermissionRequired();
      notifyListeners();
      return;
    }
    await loadLibrary(requestPermission: false, preserveCurrentLibrary: true);
  }

  Future<void> _yieldForCatalogFrame({int fallbackMilliseconds = 100}) =>
      Future.any<void>(<Future<void>>[
        WidgetsBinding.instance.endOfFrame,
        Future<void>.delayed(Duration(milliseconds: fallbackMilliseconds)),
      ]);

  Future<void> _loadSecondaryLibraryData([int? requestedGeneration]) async {
    final generation = requestedGeneration ?? _libraryLoadGeneration;
    if (_disposed ||
        _libraryLoadInProgress ||
        _permissionRequired ||
        generation != _libraryLoadGeneration ||
        _secondaryLibraryLoaded) {
      return;
    }
    if (_secondaryLibraryLoading) return;
    _secondaryLibraryLoading = true;
    final secondaryGeneration = _secondaryLibraryGeneration;
    final catalogSpan = DiagnosticsService.instance.startSpan(
      'library_secondary_catalog_pipeline',
      data: <String, Object?>{'selectedTab': _selectedTab.name},
    );
    var completedCatalogs = 0;
    try {
      // Let the first Songs frame render before the larger secondary
      // MediaStore payloads are decoded on the platform channel.
      await _yieldForCatalogFrame(fallbackMilliseconds: 120);
      if (_disposed ||
          _libraryLoadInProgress ||
          generation != _libraryLoadGeneration ||
          secondaryGeneration != _secondaryLibraryGeneration) {
        DiagnosticsService.instance.endSpan(
          catalogSpan,
          'superseded',
          <String, Object?>{
            'reason': 'library_generation_changed_or_initial_load_active',
          },
        );
        return;
      }

      // Do not complete three large MethodChannel responses simultaneously.
      // Loading and publishing one catalog at a time lowers peak decode and
      // allocation pressure while keeping each catalog independently usable.
      final order = <LibraryTab>[
            _selectedTab,
            LibraryTab.artists,
            LibraryTab.albums,
            LibraryTab.playlists,
          ]
          .where(
            (tab) =>
                tab == LibraryTab.artists ||
                tab == LibraryTab.albums ||
                tab == LibraryTab.playlists,
          )
          .toSet()
          .toList(growable: false);

      for (final catalog in order) {
        if (_disposed ||
            generation != _libraryLoadGeneration ||
            secondaryGeneration != _secondaryLibraryGeneration) {
          DiagnosticsService.instance.endSpan(
            catalogSpan,
            'superseded',
            <String, Object?>{'completedCatalogs': completedCatalogs},
          );
          return;
        }

        final result = switch (catalog) {
          LibraryTab.artists => await _library.queryArtists(),
          LibraryTab.albums => await _library.queryAlbums(),
          LibraryTab.playlists => await _library.queryPlaylists(),
          _ => null,
        };
        // A refresh may supersede this query while the platform channel is
        // returning. Discard the stale payload before assigning or notifying.
        if (_disposed ||
            generation != _libraryLoadGeneration ||
            secondaryGeneration != _secondaryLibraryGeneration) {
          DiagnosticsService.instance.endSpan(
            catalogSpan,
            'superseded',
            <String, Object?>{'completedCatalogs': completedCatalogs},
          );
          return;
        }
        switch (catalog) {
          case LibraryTab.artists:
            _artists = result as List<ArtistModel>;
            break;
          case LibraryTab.albums:
            _albums = result as List<AlbumModel>;
            break;
          case LibraryTab.playlists:
            _playlists = result as List<PlaylistModel>;
            break;
          default:
            continue;
        }
        completedCatalogs++;
        DiagnosticsService.instance
            .record('library_catalog_published', <String, Object?>{
              'catalog': catalog.name,
              'itemCount': switch (catalog) {
                LibraryTab.artists => _artists.length,
                LibraryTab.albums => _albums.length,
                LibraryTab.playlists => _playlists.length,
                _ => 0,
              },
              'completedCatalogs': completedCatalogs,
            });
        notifyListeners();
        // Give the UI a chance to paint between catalog payloads.
        await _yieldForCatalogFrame(fallbackMilliseconds: 60);
      }
      _secondaryLibraryLoaded = true;
      DiagnosticsService.instance.endSpan(
        catalogSpan,
        'complete',
        <String, Object?>{'completedCatalogs': completedCatalogs},
      );
    } catch (error) {
      DiagnosticsService.instance
          .endSpan(catalogSpan, 'failed', <String, Object?>{
            'completedCatalogs': completedCatalogs,
            'errorType': error.runtimeType.toString(),
          });
      // Secondary catalogs are optional; the Songs tab remains usable.
    } finally {
      _secondaryLibraryLoading = false;
      // If a newer scan superseded this one while its catalog queries were in
      // flight, start one fresh catalog read for the latest library snapshot.
      if (!_disposed &&
          generation != _libraryLoadGeneration &&
          !_secondaryLibraryLoaded) {
        unawaited(_loadSecondaryLibraryData(_libraryLoadGeneration));
      }
    }
  }

  Future<void> requestMediaPermission() async {
    if (await _library.requestPermission()) {
      await loadLibrary(requestPermission: false);
      return;
    }
    _markPermissionRequired();
    notifyListeners();
  }

  Future<bool> openMediaPermissionSettings() => _library.openAppSettings();

  Future<void> pickLocalFiles() async {
    if (!Platform.isLinux) return;
    _errorMessage = null;
    try {
      final selection = await FilePicker.pickFiles(type: FileType.media);
      if (selection.isEmpty) return;

      for (final file in selection) {
        final path = file.path;
        if (path == null) {
          throw StateError('The selected file did not provide a local path.');
        }
        final extension = p.extension(path).toLowerCase();
        final title = p.basenameWithoutExtension(path);
        if (_audioFileExtensions.contains(extension)) {
          final uri = Uri.file(path);
          final track = MediaTrack(
            id: 'local-file:$uri',
            title: title,
            artist: 'Unknown artist',
            album: 'Local files',
            source: TrackSource.local,
            uri: uri,
            folder: p.dirname(path),
          );
          _importedAudioFiles[track.id] = track;
        } else if (_videoFileExtensions.contains(extension)) {
          final metadata = await File(path).stat();
          final track = MediaTrack.fromLocalVideo(
            path: path,
            title: title,
            sizeBytes: metadata.size,
            modifiedAt: metadata.modified,
          );
          _importedVideoFiles[track.id] = track;
        }
      }
      _baseLocalSongs = _mergeTracks(
        _baseLocalSongs,
        _importedAudioFiles.values,
      );
      _localVideos = _mergeTracks(_localVideos, _importedVideoFiles.values);
      _rebuildLibraryDerivedLists();
    } catch (error) {
      _errorMessage = 'Unable to open selected local media: $error';
    }
    notifyListeners();
  }

  Future<void> handleAppResumed() async {
    if (_isLoading) return;
    if (_usesLinuxImportedFileMode) {
      if (_selectedTab == LibraryTab.videos) {
        await loadVideos(requestPermission: false);
      }
      return;
    }
    final wasPermissionRequired = _permissionRequired;
    final granted = await _library.recheckPermission();
    if (!granted) {
      _markPermissionRequired();
      notifyListeners();
      return;
    }
    if (wasPermissionRequired) await loadLibrary(requestPermission: false);
    if (_selectedTab == LibraryTab.videos && !_videosLoading) {
      _videosPermissionAttempted = false;
      await loadVideos(requestPermission: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(handleAppResumed());
  }

  void _markPermissionRequired() {
    _permissionRequired = true;
    _errorMessage = null;
    _baseLocalSongs = const <MediaTrack>[];
    final snapshot = _libraryDataEngine.rebuild(
      tracks: const <MediaTrack>[],
      hiddenTrackIds: const <String>[],
    );
    _localSongs = snapshot.visibleAudioTracks;
    _artists = const <ArtistModel>[];
    _albums = const <AlbumModel>[];
    _playlists = const <PlaylistModel>[];
    _folders = const <String>[];
    _localVideos = _mergeTracks(
      const <MediaTrack>[],
      _importedVideoFiles.values,
    );
    _videosPermissionAttempted = false;
  }

  void _rebuildLibraryDerivedLists() {
    final diagnosticsSpan = DiagnosticsService.instance.startSpan(
      'library_snapshot_rebuild',
      data: <String, Object?>{'inputTrackCount': _baseLocalSongs.length},
    );
    final metadataTracks = _playlistManager.applyMetadata(_baseLocalSongs);
    final hiddenIds = <String>[];
    for (final track in metadataTracks) {
      if (_playlistManager.isHidden(track.id)) hiddenIds.add(track.id);
    }
    final snapshot = _libraryDataEngine.rebuild(
      tracks: metadataTracks,
      hiddenTrackIds: hiddenIds,
    );
    _localSongs = snapshot.visibleAudioTracks;
    _folders = snapshot.folders;
    _lastLibraryOverlayRevision = _playlistManager.libraryOverlayRevision;
    DiagnosticsService.instance
        .endSpan(diagnosticsSpan, 'complete', <String, Object?>{
          'visibleTrackCount': _localSongs.length,
          'hiddenTrackCount': hiddenIds.length,
          'folderCount': _folders.length,
        });
  }

  Future<void> addToQueue(MediaTrack track) {
    DiagnosticsService.instance.record('playback_queue_add', <String, Object?>{
      'trackId': track.id,
    });
    return _audioHandler.addToQueue(track);
  }

  Future<void> addTracksToQueue(Iterable<MediaTrack> tracks) {
    DiagnosticsService.instance.record(
      'playback_queue_add_many',
      <String, Object?>{'trackCount': tracks is List ? tracks.length : null},
    );
    return _audioHandler.addTracksToQueue(tracks);
  }

  Future<void> shareTracks(Iterable<MediaTrack> tracks) {
    DiagnosticsService.instance.record(
      'library_share_requested',
      <String, Object?>{'trackCount': tracks is List ? tracks.length : null},
    );
    return _library.shareAudioTracks(tracks);
  }

  Future<int> deleteTracks(Iterable<MediaTrack> tracks) {
    DiagnosticsService.instance.record(
      'library_delete_requested',
      <String, Object?>{'trackCount': tracks is List ? tracks.length : null},
    );
    return _library.deleteAudioTracks(tracks);
  }

  Future<List<MediaTrack>> tracksForArtist(int artistId) =>
      _library.querySongsFrom(AudiosFromType.ARTIST_ID, artistId);

  Future<List<MediaTrack>> tracksForAlbum(int albumId) =>
      _library.querySongsFrom(AudiosFromType.ALBUM_ID, albumId);

  Future<List<MediaTrack>> tracksForDevicePlaylist(int playlistId) =>
      _library.querySongsFrom(AudiosFromType.PLAYLIST, playlistId);

  Future<List<MediaTrack>> tracksForFolder(String folder) async =>
      _libraryDataEngine.snapshot.tracksInFolder(folder);

  bool isFavorite(MediaTrack track) => _playlistManager.isFavorite(track);

  Future<void> toggleFavorite(MediaTrack track) async {
    DiagnosticsService.instance.record(
      'playlist_favorite_toggled',
      <String, Object?>{
        'trackId': track.id,
        'wasFavorite': _playlistManager.isFavorite(track),
      },
    );
    await _playlistManager.toggleFavorite(track);
    notifyListeners();
  }

  Future<EchoPlaylist> createPlaylist(String name) {
    DiagnosticsService.instance.record(
      'playlist_create_requested',
      <String, Object?>{'nameLength': name.length},
    );
    return _playlistManager.createPlaylist(name);
  }

  Future<void> addToPlaylist(String playlistId, MediaTrack track) {
    DiagnosticsService.instance.record(
      'playlist_track_add_requested',
      <String, Object?>{'playlistId': playlistId, 'trackId': track.id},
    );
    return _playlistManager.addToPlaylist(playlistId, track);
  }

  Future<void> playTrack(MediaTrack track) async {
    final request = ++_playbackSelectionRequest;
    DiagnosticsService.instance.record(
      'playback_track_requested',
      <String, Object?>{'trackId': track.id, 'titleLength': track.title.length},
    );
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      await _audioHandler.playTrack(track);
      if (request != _playbackSelectionRequest) return;
      await _playlistManager.recordPlayed(track);
      if (request != _playbackSelectionRequest) return;
      DiagnosticsService.instance.record(
        'playback_track_started',
        <String, Object?>{'trackId': _audioHandler.activeTrack?.id},
      );
      notifyListeners();
    } catch (error) {
      if (request != _playbackSelectionRequest) return;
      _errorMessage = 'Playback failed: $error';
      DiagnosticsService.instance.record(
        'playback_track_failed',
        <String, Object?>{'trackId': track.id, 'error': error.toString()},
      );
      notifyListeners();
    }
  }

  Future<void> playTrackQueue(
    List<MediaTrack> tracks, {
    int initialIndex = 0,
  }) async {
    final request = ++_playbackSelectionRequest;
    DiagnosticsService.instance.record(
      'playback_queue_requested',
      <String, Object?>{
        'trackCount': tracks.length,
        'initialIndex': initialIndex,
      },
    );
    final selectedTrack =
        tracks.isEmpty
            ? null
            : tracks[initialIndex.clamp(0, tracks.length - 1)];
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      await _audioHandler.playTrackQueue(tracks, initialIndex: initialIndex);
      DiagnosticsService.instance.record(
        'playback_queue_started',
        <String, Object?>{
          'trackCount': tracks.length,
          'selectedTrackId': selectedTrack?.id,
        },
      );
      if (request != _playbackSelectionRequest) return;
      if (selectedTrack != null) {
        await _playlistManager.recordPlayed(selectedTrack);
        if (request != _playbackSelectionRequest) return;
      }
      notifyListeners();
    } catch (error) {
      if (request != _playbackSelectionRequest) return;
      _errorMessage = 'Playback failed: $error';
      notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    final wasPlaying = _audioHandler.player.playing;
    DiagnosticsService.instance.record(
      'playback_toggle_requested',
      <String, Object?>{
        'wasPlaying': wasPlaying,
        'trackId': _audioHandler.activeTrack?.id,
      },
    );
    if (_audioHandler.player.playing) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
    DiagnosticsService.instance
        .record('playback_toggle_completed', <String, Object?>{
          'isPlaying': _audioHandler.player.playing,
          'trackId': _audioHandler.activeTrack?.id,
        });
  }

  Future<void> toggleRepeat() async {
    final next = nextRepeatMode(_audioHandler.repeatMode);
    DiagnosticsService.instance.record(
      'playback_repeat_mode_changed',
      <String, Object?>{
        'previous': _audioHandler.repeatMode.name,
        'next': next.name,
      },
    );
    await _audioHandler.setRepeatMode(next);
    notifyListeners();
  }

  void selectTab(LibraryTab tab) {
    if (_selectedTab == tab) return;
    DiagnosticsService.instance.record(
      'library_tab_selected',
      <String, Object?>{'previous': _selectedTab.name, 'next': tab.name},
    );
    _selectedTab = tab;
    notifyListeners();
    if (!_libraryLoadInProgress &&
        (tab == LibraryTab.artists ||
            tab == LibraryTab.albums ||
            tab == LibraryTab.playlists)) {
      unawaited(_loadSecondaryLibraryData());
    }
    if (tab == LibraryTab.videos) {
      unawaited(loadVideos(requestPermission: true));
    }
  }

  Future<void> loadVideos({required bool requestPermission}) async {
    if (_videosLoading || (!requestPermission && _videosPermissionAttempted)) {
      return;
    }
    _videosLoading = true;
    if (requestPermission) _videosPermissionAttempted = true;
    notifyListeners();
    try {
      if (Platform.isLinux) {
        _localVideos = _mergeTracks(
          const <MediaTrack>[],
          _importedVideoFiles.values,
        );
      } else {
        _localVideos = await _library.queryVideos(
          requestPermission: requestPermission,
        );
        _localVideos = _mergeTracks(_localVideos, _importedVideoFiles.values);
      }
    } catch (error) {
      _errorMessage = 'Unable to read local videos: $error';
    } finally {
      _videosLoading = false;
      notifyListeners();
    }
  }

  void _onPlaylistChanged() {
    if (_lastLibraryOverlayRevision !=
        _playlistManager.libraryOverlayRevision) {
      _rebuildLibraryDerivedLists();
    } else if (libraryFilters.contains(LibraryFilter.favorites) ||
        librarySort == LibrarySort.mostPlayed ||
        librarySort == LibrarySort.recentlyPlayedFirst) {
      _dynamicLibraryRevision++;
      _libraryDataEngine.invalidateQueries();
    }
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _libraryLoadGeneration++;
    _secondaryLibraryGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _playlistManager.removeListener(_onPlaylistChanged);
    _audioHandler.dispose();
    _lyricsService.dispose();
    super.dispose();
  }
}
