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
    _librarySortByTab[_selectedTab] = sort;
    _libraryDataEngine.invalidateQueries();
    notifyListeners();
  }

  void setLibraryFilters(Iterable<LibraryFilter> filters) {
    final next = filters.toSet()..remove(LibraryFilter.all);
    final current = _libraryFiltersByTab[_selectedTab] ?? <LibraryFilter>{};
    if (current.length == next.length && current.containsAll(next)) return;
    _libraryFiltersByTab[_selectedTab] = next;
    _libraryDataEngine.invalidateQueries();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    final normalized = query.trim();
    if (searchQuery == normalized) return;
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
      unawaited(_loadSecondaryLibraryData(loadGeneration));
    } catch (error) {
      if (loadGeneration == _libraryLoadGeneration) {
        _errorMessage = 'Unable to read the device music library: $error';
      }
    } finally {
      if (!preserveCurrentLibrary) {
        _setLoading(false);
        if (_refreshQueuedDuringLoad) {
          _refreshQueuedDuringLoad = false;
          unawaited(refreshLibrary());
        }
      }
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    if (_isLoading) {
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

  Future<void> _loadSecondaryLibraryData([int? requestedGeneration]) async {
    final generation = requestedGeneration ?? _libraryLoadGeneration;
    if (_disposed ||
        generation != _libraryLoadGeneration ||
        _secondaryLibraryLoaded) {
      return;
    }
    if (_secondaryLibraryLoading) return;
    _secondaryLibraryLoading = true;
    final secondaryGeneration = _secondaryLibraryGeneration;
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _library.queryArtists(),
        _library.queryAlbums(),
        _library.queryPlaylists(),
      ]);
      if (_disposed ||
          generation != _libraryLoadGeneration ||
          secondaryGeneration != _secondaryLibraryGeneration) {
        return;
      }
      _artists = results[0] as List<ArtistModel>;
      _albums = results[1] as List<AlbumModel>;
      _playlists = results[2] as List<PlaylistModel>;
      _secondaryLibraryLoaded = true;
      notifyListeners();
    } catch (_) {
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
  }

  Future<void> addToQueue(MediaTrack track) => _audioHandler.addToQueue(track);

  Future<void> addTracksToQueue(Iterable<MediaTrack> tracks) =>
      _audioHandler.addTracksToQueue(tracks);

  Future<void> shareTracks(Iterable<MediaTrack> tracks) =>
      _library.shareAudioTracks(tracks);

  Future<int> deleteTracks(Iterable<MediaTrack> tracks) =>
      _library.deleteAudioTracks(tracks);

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
    await _playlistManager.toggleFavorite(track);
    notifyListeners();
  }

  Future<EchoPlaylist> createPlaylist(String name) =>
      _playlistManager.createPlaylist(name);

  Future<void> addToPlaylist(String playlistId, MediaTrack track) =>
      _playlistManager.addToPlaylist(playlistId, track);

  Future<void> playTrack(MediaTrack track) async {
    final request = ++_playbackSelectionRequest;
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
    try {
      await _audioHandler.playTrack(track);
      if (request != _playbackSelectionRequest) return;
      await _playlistManager.recordPlayed(track);
      if (request != _playbackSelectionRequest) return;
      notifyListeners();
    } catch (error) {
      if (request != _playbackSelectionRequest) return;
      _errorMessage = 'Playback failed: $error';
      notifyListeners();
    }
  }

  Future<void> playTrackQueue(
    List<MediaTrack> tracks, {
    int initialIndex = 0,
  }) async {
    final request = ++_playbackSelectionRequest;
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
    if (_audioHandler.player.playing) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> toggleRepeat() async {
    final next = nextRepeatMode(_audioHandler.repeatMode);
    await _audioHandler.setRepeatMode(next);
    notifyListeners();
  }

  void selectTab(LibraryTab tab) {
    if (_selectedTab == tab) return;
    _selectedTab = tab;
    notifyListeners();
    if (tab == LibraryTab.artists ||
        tab == LibraryTab.albums ||
        tab == LibraryTab.playlists) {
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
