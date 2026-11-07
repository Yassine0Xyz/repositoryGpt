import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/motion_tokens.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../services/artwork_palette_service.dart';
import '../../services/folder_identity.dart';
import '../../services/library_display_settings.dart';
import '../../services/library_viewport_engine.dart';
import '../../widgets/shimmer_skeleton.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../widgets/video_thumbnail.dart';
import '../../widgets/media_artwork.dart';
import '../../widgets/now_playing_scope.dart';
import '../../widgets/library_track_viewport.dart';
import '../../widgets/track_actions_menu.dart';
import '../home/widgets/library_tabs.dart';
import '../home/widgets/track_list_tile.dart';
import '../collections/favorites_screen.dart';
import '../collections/playlist_details_screen.dart';
import '../player/yazen_video_player_screen.dart';
import 'entity_tracks_screen.dart';

class LocalMediaScreen extends StatelessWidget {
  const LocalMediaScreen({
    required this.selectedTab,
    required this.onTabSelected,
    this.showTabs = true,
    this.onScrollDelta,
    super.key,
  });

  final LibraryTab selectedTab;
  final ValueChanged<LibraryTab> onTabSelected;
  final bool showTabs;
  final ValueChanged<double>? onScrollDelta;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    return Column(
      children: <Widget>[
        if (showTabs) ...<Widget>[
          LibraryTabs(selected: selectedTab, onSelected: onTabSelected),
          const SizedBox(height: ThemeSpacing.x3),
        ],
        Expanded(
          child: Selector<HybridMusicController, _LocalMediaSnapshot>(
            selector:
                (_, value) => _LocalMediaSnapshot.from(value, selectedTab),
            builder: (context, snapshot, _) {
              // Do not keep the previous tab's full lazy viewport alive during
              // a cross-fade. On large libraries that temporarily doubles the
              // mounted rows and can continue artwork work for an off-screen
              // collection while the next tab is already building.
              return KeyedSubtree(
                key: ValueKey<LibraryTab>(selectedTab),
                child: _buildView(context, controller, snapshot),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildView(
    BuildContext context,
    HybridMusicController controller,
    _LocalMediaSnapshot snapshot,
  ) {
    if (snapshot.isLoading) return const LibraryLoadingState();
    if (snapshot.permissionRequired && selectedTab != LibraryTab.videos) {
      return _MediaPermissionView(
        onGrant: controller.requestMediaPermission,
        onOpenSettings: () async {
          final opened = await controller.openMediaPermissionSettings();
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to open Android Settings.')),
            );
          }
        },
      );
    }

    final view = switch (selectedTab) {
      LibraryTab.songs => _SongsView(tracks: snapshot.visibleTracks),
      LibraryTab.artists => _ArtistsView(artists: snapshot.artists),
      LibraryTab.albums => _AlbumsView(albums: snapshot.albums),
      LibraryTab.folders => _FoldersView(
        folders: snapshot.folders,
        counts: snapshot.folderCounts,
      ),
      LibraryTab.videos => _VideosView(tracks: snapshot.visibleTracks),
      LibraryTab.hidden => _HiddenFilesView(tracks: snapshot.hiddenTracks),
      LibraryTab.playlists => _PlaylistsView(
        devicePlaylists: snapshot.playlists,
        customPlaylists: snapshot.customPlaylists,
        favorites: snapshot.favorites,
      ),
    };
    final reportHeaderScroll =
        onScrollDelta != null &&
        (selectedTab == LibraryTab.songs || selectedTab == LibraryTab.videos);
    if (!reportHeaderScroll) return view;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.scrollDelta != null &&
            notification.scrollDelta!.abs() >= 0.5) {
          onScrollDelta!(notification.scrollDelta!);
        }
        return false;
      },
      child: view,
    );
  }
}

class _LibraryScrollSurface extends StatefulWidget {
  const _LibraryScrollSurface({required this.child});

  final Widget child;

  @override
  State<_LibraryScrollSurface> createState() => _LibraryScrollSurfaceState();
}

class _LibraryScrollSurfaceState extends State<_LibraryScrollSurface> {
  late final ScrollController _scrollController;
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_syncBackToTop);
  }

  void _syncBackToTop() {
    final show =
        _scrollController.positions.length == 1 &&
        _scrollController.offset > 420;
    if (show == _showBackToTop || !mounted) return;
    setState(() => _showBackToTop = show);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncBackToTop)
      ..dispose();
    super.dispose();
  }

  Future<void> _scrollToTop() async {
    if (_scrollController.positions.length != 1) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _scrollController,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Scrollbar(
            controller: _scrollController,
            thumbVisibility: false,
            interactive: false,
            child: widget.child,
          ),
          _FastScrollThumb(controller: _scrollController),
          Positioned(
            right: 14,
            bottom: 14,
            child: IgnorePointer(
              ignoring: !_showBackToTop,
              child: AnimatedScale(
                scale: _showBackToTop ? 1 : 0.72,
                duration: MotionTokens.fast,
                curve: MotionTokens.standard,
                child: AnimatedOpacity(
                  opacity: _showBackToTop ? 1 : 0,
                  duration: MotionTokens.fast,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Back to top',
                    onPressed: _scrollToTop,
                    child: const Icon(Icons.vertical_align_top_rounded),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FastScrollThumb extends StatefulWidget {
  const _FastScrollThumb({required this.controller});

  final ScrollController controller;

  @override
  State<_FastScrollThumb> createState() => _FastScrollThumbState();
}

class _FastScrollThumbState extends State<_FastScrollThumb> {
  late LibraryViewportEngine _viewportEngine;
  double? _dragTop;
  double _currentThumbTop = 0;
  double _currentTravel = 1;

  @override
  void initState() {
    super.initState();
    _viewportEngine = LibraryViewportEngine(
      scrollController: widget.controller,
    );
  }

  @override
  void didUpdateWidget(covariant _FastScrollThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _viewportEngine.dispose();
      _viewportEngine = LibraryViewportEngine(
        scrollController: widget.controller,
      );
    }
  }

  void _queueJumpFromTop(double top) {
    _viewportEngine.queueThumbPosition(top: top, travel: _currentTravel);
  }

  void _flushPendingJump() => _viewportEngine.flushPendingJump();

  @override
  void dispose() {
    _viewportEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final thumb = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragTop = _currentThumbTop,
      onVerticalDragUpdate: (details) {
        final next =
            (_dragTop! + details.delta.dy)
                .clamp(0.0, _currentTravel)
                .toDouble();
        _dragTop = next;
        _queueJumpFromTop(next);
      },
      onVerticalDragEnd: (_) {
        _flushPendingJump();
        if (mounted) setState(() => _dragTop = null);
      },
      onVerticalDragCancel: () {
        _flushPendingJump();
        if (mounted) setState(() => _dragTop = null);
      },
      child: Container(
        width: 42,
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.drag_handle_rounded,
          size: 22,
          color: colorScheme.onSurface.withValues(alpha: 0.64),
        ),
      ),
    );

    return Positioned(
      top: 12,
      right: 6,
      bottom: 76,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: widget.controller,
            child: thumb,
            builder: (context, child) {
              if (widget.controller.positions.length != 1 ||
                  widget.controller.position.maxScrollExtent <= 0) {
                return const SizedBox.shrink();
              }
              final position = widget.controller.position;
              final trackHeight = constraints.maxHeight;
              final viewport = position.viewportDimension;
              final content = viewport + position.maxScrollExtent;
              final thumbHeight =
                  (trackHeight * viewport / content)
                      .clamp(58.0, 118.0)
                      .toDouble();
              final travel =
                  (trackHeight - thumbHeight)
                      .clamp(1.0, double.infinity)
                      .toDouble();
              final calculatedTop =
                  position.pixels / position.maxScrollExtent * travel;
              _currentThumbTop = calculatedTop;
              _currentTravel = travel;
              return Align(
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: Offset(0, _dragTop ?? calculatedTop),
                  child: SizedBox(
                    width: 42,
                    height: thumbHeight,
                    child: child,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LocalMediaSnapshot {
  const _LocalMediaSnapshot({
    required this.isLoading,
    required this.permissionRequired,
    required this.visibleTracks,
    required this.folderCounts,
    required this.hiddenTracks,
    required this.artists,
    required this.albums,
    required this.playlists,
    required this.folders,
    required this.customPlaylists,
    required this.favorites,
  });

  factory _LocalMediaSnapshot.from(
    HybridMusicController controller,
    LibraryTab selectedTab,
  ) {
    final needsVisibleTracks =
        selectedTab == LibraryTab.songs || selectedTab == LibraryTab.videos;
    return _LocalMediaSnapshot(
      isLoading: controller.isLoading,
      permissionRequired: controller.permissionRequired,
      visibleTracks:
          needsVisibleTracks ? controller.visibleTracks : const <MediaTrack>[],
      folderCounts:
          selectedTab == LibraryTab.folders
              ? controller.folderTrackCounts
              : const <String, int>{},
      hiddenTracks:
          selectedTab == LibraryTab.hidden
              ? controller.hiddenTracks
              : const <MediaTrack>[],
      artists:
          selectedTab == LibraryTab.artists
              ? controller.artists
              : const <ArtistModel>[],
      albums:
          selectedTab == LibraryTab.albums
              ? controller.albums
              : const <AlbumModel>[],
      playlists:
          selectedTab == LibraryTab.playlists
              ? controller.playlists
              : const <PlaylistModel>[],
      folders:
          selectedTab == LibraryTab.folders
              ? controller.folders
              : const <String>[],
      customPlaylists:
          selectedTab == LibraryTab.playlists
              ? controller.playlistManager.playlists
              : const <EchoPlaylist>[],
      favorites:
          selectedTab == LibraryTab.playlists
              ? controller.playlistManager.favorites
              : const <MediaTrack>[],
    );
  }

  final bool isLoading;
  final bool permissionRequired;
  final List<MediaTrack> visibleTracks;
  final Map<String, int> folderCounts;
  final List<MediaTrack> hiddenTracks;
  final List<ArtistModel> artists;
  final List<AlbumModel> albums;
  final List<PlaylistModel> playlists;
  final List<String> folders;
  final List<EchoPlaylist> customPlaylists;
  final List<MediaTrack> favorites;

  @override
  bool operator ==(Object other) =>
      other is _LocalMediaSnapshot &&
      other.isLoading == isLoading &&
      other.permissionRequired == permissionRequired &&
      identical(other.visibleTracks, visibleTracks) &&
      identical(other.folderCounts, folderCounts) &&
      identical(other.hiddenTracks, hiddenTracks) &&
      identical(other.artists, artists) &&
      identical(other.albums, albums) &&
      identical(other.playlists, playlists) &&
      identical(other.folders, folders) &&
      identical(other.customPlaylists, customPlaylists) &&
      identical(other.favorites, favorites);

  @override
  int get hashCode => Object.hash(
    isLoading,
    permissionRequired,
    identityHashCode(visibleTracks),
    identityHashCode(folderCounts),
    identityHashCode(hiddenTracks),
    identityHashCode(artists),
    identityHashCode(albums),
    identityHashCode(playlists),
    identityHashCode(folders),
    identityHashCode(customPlaylists),
    identityHashCode(favorites),
  );
}

class _HiddenFilesView extends StatelessWidget {
  const _HiddenFilesView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final manager = context.read<LocalPlaylistManager>();
    final controller = context.read<HybridMusicController>();
    if (tracks.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.visibility_off_outlined,
        title: 'No hidden files',
        subtitle: 'Songs hidden from YAZEN will appear here.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth - 24 < 470;
        return LibraryTrackViewport(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
          itemExtent: compact ? 72 : 78,
          itemCount: tracks.length,
          cacheExtent: 220,
          addAutomaticKeepAlives: false,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return TrackListTile(
              key: ValueKey<String>('hidden-${track.id}'),
              track: track,
              compact: compact,
              onTap: () => controller.playTrackQueue(tracks, initialIndex: index),
              trailing: IconButton(
                tooltip: 'Restore to library',
                onPressed:
                    () => manager.setHidden(<String>[track.id], hidden: false),
                icon: const Icon(Icons.visibility_rounded),
              ),
            );
          },
        );
      },
    );
  }
}

class _SongsView extends StatefulWidget {
  const _SongsView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  State<_SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends State<_SongsView> {
  final Set<String> _selectedIds = <String>{};

  bool get _selectionMode => _selectedIds.isNotEmpty;
  List<MediaTrack> get _selectedTracks => widget.tracks
      .where((track) => _selectedIds.contains(track.id))
      .toList(growable: false);

  void _toggleSelection(MediaTrack track) {
    setState(() {
      if (!_selectedIds.add(track.id)) _selectedIds.remove(track.id);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == widget.tracks.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.tracks.map((track) => track.id));
      }
    });
  }

  Future<void> _showSelectionActions() async {
    final tracks = _selectedTracks;
    if (tracks.isEmpty) return;
    final action = await showModalBottomSheet<_SelectionMoreAction>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Share selected songs'),
                  onTap:
                      () => Navigator.pop(context, _SelectionMoreAction.share),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('File information'),
                  onTap:
                      () => Navigator.pop(
                        context,
                        _SelectionMoreAction.information,
                      ),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_rounded),
                  title: const Text('Remove from YAZEN library'),
                  onTap:
                      () => Navigator.pop(context, _SelectionMoreAction.hide),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text('Delete original files'),
                  subtitle: const Text(
                    'Permanently removes the selected files from this device.',
                  ),
                  onTap:
                      () => Navigator.pop(
                        context,
                        _SelectionMoreAction.deleteFiles,
                      ),
                ),
              ],
            ),
          ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _SelectionMoreAction.share:
        await _shareSelected(tracks);
      case _SelectionMoreAction.information:
        await _showSelectedInformation(tracks);
      case _SelectionMoreAction.hide:
        await _hideSelected(tracks);
      case _SelectionMoreAction.deleteFiles:
        await _deleteSelectedFiles(tracks);
    }
  }

  Future<void> _shareSelected(List<MediaTrack> tracks) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<HybridMusicController>().shareTracks(tracks);
      if (!mounted) return;
      _clearSelection();
      messenger.showSnackBar(
        _actionSnackBar(
          'Ready to share ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to share selected songs: $error')),
      );
    }
  }

  Future<void> _showSelectedInformation(List<MediaTrack> tracks) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final tokens = context.read<ThemeProvider>().tokens;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} selected',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return ListTile(
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${track.artist}  •  ${track.album}\n'
                          '${_formatTrackDuration(track.duration)}  •  '
                          '${track.sizeBytes == null ? 'Size unavailable' : _formatBytes(track.sizeBytes!)}\n'
                          '${track.uri?.path ?? 'Path unavailable'}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _hideSelected(List<MediaTrack> tracks) async {
    final ids = tracks.map((track) => track.id).toList(growable: false);
    final manager = context.read<LocalPlaylistManager>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await manager.setHidden(ids, hidden: true);
      if (!mounted) return;
      _clearSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} from YAZEN',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await manager.setHidden(ids, hidden: false);
              } catch (error) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Unable to undo removal: $error')),
                  );
                }
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to remove songs from YAZEN: $error')),
      );
    }
  }

  Future<void> _deleteSelectedFiles(List<MediaTrack> tracks) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete original files?'),
            content: Text(
              'This permanently deletes ${tracks.length} '
              '${tracks.length == 1 ? 'audio file' : 'audio files'} from this device. '
              'YAZEN will ask Android to confirm the deletion. This cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    final controller = context.read<HybridMusicController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await controller.deleteTracks(tracks);
      if (!mounted) return;
      _clearSelection();
      await controller.refreshLibrary();
      if (!mounted) return;
      messenger.showSnackBar(
        _actionSnackBar(
          'Deleted $deleted ${deleted == 1 ? 'song' : 'songs'} from this device',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to delete selected files: $error')),
      );
    }
  }

  SnackBar _actionSnackBar(String message) => SnackBar(content: Text(message));

  String _formatTrackDuration(Duration? duration) {
    if (duration == null) return 'Duration unavailable';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void didUpdateWidget(covariant _SongsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = widget.tracks.map((track) => track.id).toSet();
    _selectedIds.removeWhere((id) => !available.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final displaySettings = LibraryDisplaySettings.instance;
    return AnimatedBuilder(
      animation: displaySettings,
      builder: (context, _) {
        final grid = displaySettings.layoutMode == LibraryLayoutMode.grid;
        final compact = displaySettings.density == LibraryDensity.compact;
        return Column(
          children: <Widget>[
            _LibraryViewToolbar(
              controller: controller,
              isVideos: false,
              settings: displaySettings,
            ),
            if (_selectionMode)
              _SelectionToolbar(
                selectedCount: _selectedIds.length,
                allSelected: _selectedIds.length == widget.tracks.length,
                onSelectAll: _selectAll,
                onClear: _clearSelection,
                onFavorites: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await controller.playlistManager.addToFavorites(
                    _selectedTracks,
                  );
                  if (!mounted) return;
                  final count = _selectedIds.length;
                  _clearSelection();
                  messenger.showSnackBar(
                    SnackBar(content: Text('Added $count to favorites')),
                  );
                },
                onPlaylist: () async {
                  final sheetContext = context;
                  final tracks = _selectedTracks;
                  await showAddTracksToPlaylistSheet(sheetContext, tracks);
                  if (mounted) _clearSelection();
                },
                onQueue: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final tracks = _selectedTracks;
                  await controller.addTracksToQueue(tracks);
                  if (!mounted) return;
                  _clearSelection();
                  messenger.showSnackBar(
                    _actionSnackBar(
                      'Added ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} to queue',
                    ),
                  );
                },
                onMore: _showSelectionActions,
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewportConstraints) {
                  // The song list has 12px horizontal padding on each side.
                  // Resolve the compact breakpoint once rather than creating
                  // one LayoutBuilder for every visible TrackListTile.
                  final compactRows =
                      viewportConstraints.maxWidth - (ThemeSpacing.x3 * 2) <
                      470;
                  // Resolve grid cell geometry once for the whole viewport.
                  // Individual song cards no longer need their own LayoutBuilder.
                  final gridCrossAxisExtent =
                      (viewportConstraints.maxWidth - (ThemeSpacing.x3 * 2))
                          .clamp(1.0, double.infinity)
                          .toDouble();
                  final gridColumnCount = (gridCrossAxisExtent / 230).ceil();
                  final gridCellWidth =
                      (gridCrossAxisExtent - ((gridColumnCount - 1) * 10)) /
                      gridColumnCount;
                  final gridArtworkSize = gridCellWidth - 16;
                  final gridExtent =
                      gridArtworkSize + (compact ? 98 : 106);
                  return widget.tracks.isEmpty
                      ? const _CategoryEmptyState(
                        icon: Icons.library_music_outlined,
                        title: 'No matching songs',
                        subtitle:
                            'Try clearing the search or changing filters.',
                      )
                      : _LibraryScrollSurface(
                        child:
                            grid
                                ? LibraryTrackViewport(
                                  padding: EdgeInsets.fromLTRB(
                                    ThemeSpacing.x3,
                                    0,
                                    ThemeSpacing.x3,
                                    MediaQuery.paddingOf(context).bottom + 112,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 220,
                                        mainAxisExtent: gridExtent,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 8,
                                      ),
                                  itemCount: widget.tracks.length,
                                  addAutomaticKeepAlives: false,
                                  itemBuilder:
                                      (_, index) => _buildGridTrack(
                                        context,
                                        controller,
                                        widget.tracks[index],
                                        index,
                                        displaySettings.density,
                                        gridArtworkSize,
                                      ),
                                )
                                : LibraryTrackViewport(
                                  padding: EdgeInsets.fromLTRB(
                                    ThemeSpacing.x3,
                                    0,
                                    ThemeSpacing.x3,
                                    MediaQuery.paddingOf(context).bottom + 100,
                                  ),
                                  addAutomaticKeepAlives: false,
                                  itemExtent:
                                      displaySettings.density ==
                                              LibraryDensity.compact
                                          ? 70
                                          : compactRows
                                          ? 76
                                          : 82,
                                  itemCount: widget.tracks.length,
                                  itemBuilder:
                                      (_, index) => _buildListTrack(
                                        context,
                                        controller,
                                        widget.tracks[index],
                                        index,
                                        displaySettings.density,
                                        compactRows,
                                      ),
                                ),
                      );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListTrack(
    BuildContext context,
    HybridMusicController controller,
    MediaTrack track,
    int index,
    LibraryDensity density,
    bool compact,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TrackListTile(
        compact: compact,
        key: ValueKey<String>('song-${track.id}'),
        track: track,
        selected: _selectedIds.contains(track.id),
        artworkSize: density == LibraryDensity.compact ? 52 : 64,
        onLongPress: () => _toggleSelection(track),
        onTap: () {
          if (_selectionMode) {
            _toggleSelection(track);
          } else {
            controller.playTrackQueue(widget.tracks, initialIndex: index);
          }
        },
        isFavorite: controller.isFavorite(track),
        onFavorite:
            _selectionMode ? null : () => controller.toggleFavorite(track),
        onAddToPlaylist:
            _selectionMode
                ? null
                : () => showAddToPlaylistSheet(context, track),
      ),
    );
  }

  Widget _buildGridTrack(
    BuildContext context,
    HybridMusicController controller,
    MediaTrack track,
    int index,
    LibraryDensity density,
    double artworkSize,
  ) {
    return _TrackGridTile(
      key: ValueKey<String>('song-grid-${track.id}'),
      track: track,
      selected: _selectedIds.contains(track.id),
      isFavorite: controller.isFavorite(track),
      density: density,
      artworkSize: artworkSize,
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(track);
        } else {
          controller.playTrackQueue(widget.tracks, initialIndex: index);
        }
      },
      onLongPress: () => _toggleSelection(track),
      onFavorite:
          _selectionMode ? null : () => controller.toggleFavorite(track),
      onAddToPlaylist:
          _selectionMode ? null : () => showAddToPlaylistSheet(context, track),
    );
  }
}

enum _SelectionMoreAction { share, information, hide, deleteFiles }

class _TrackGridTile extends StatelessWidget {
  const _TrackGridTile({
    super.key,
    required this.track,
    required this.selected,
    required this.isFavorite,
    required this.density,
    required this.artworkSize,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
    required this.onAddToPlaylist,
  });

  final MediaTrack track;
  final bool selected;
  final bool isFavorite;
  final LibraryDensity density;
  final double artworkSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    final preset = context.select<ThemeProvider, EchoThemePreset>(
      (provider) => provider.preset,
    );
    final tokens = ThemeTokens.fromPreset(preset);
    final nowPlaying = nowPlayingRowStateOf(context, track.id);
    final isCurrentTrack = nowPlaying?.isCurrent ?? false;
    final radius = BorderRadius.circular(ThemeRadii.large);

    return Material(
      color: tokens.surface.withValues(alpha: 0.38),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  YazenMediaArtwork(
                    track: track,
                    size: artworkSize,
                    borderRadius: BorderRadius.circular(ThemeRadii.medium),
                  ),
                  if (isCurrentTrack)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(ThemeRadii.small),
                          border: Border.all(
                            color: tokens.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: RepaintBoundary(
                          child: NowPlayingIndicator(
                            isCurrent: true,
                            isPlaying: nowPlaying!.isPlaying,
                            pulse: nowPlaying.pulse,
                            color: tokens.accentStrong,
                          ),
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(ThemeRadii.medium),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: tokens.isLight ? Colors.white : Colors.black,
                          size: 34,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isCurrentTrack ? tokens.accent : null,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: density == LibraryDensity.compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (onFavorite != null || onAddToPlaylist != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TrackActionsMenu(
                    isFavorite: isFavorite,
                    onFavorite: onFavorite,
                    onAddToPlaylist: onAddToPlaylist,
                    accentColor: tokens.accent,
                    secondaryColor: tokens.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClear,
    required this.onFavorites,
    required this.onPlaylist,
    required this.onQueue,
    required this.onMore,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onFavorites;
  final VoidCallback onPlaylist;
  final VoidCallback onQueue;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(ThemeRadii.medium),
          border: Border.all(color: tokens.accent.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Exit selection',
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  '$selectedCount ${selectedCount == 1 ? 'song' : 'songs'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: allSelected ? 'Clear all' : 'Select all',
                visualDensity: VisualDensity.compact,
                onPressed: onSelectAll,
                icon: Icon(
                  allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Add to playlist',
                visualDensity: VisualDensity.compact,
                onPressed: onPlaylist,
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Add to queue',
                visualDensity: VisualDensity.compact,
                onPressed: onQueue,
                icon: const Icon(Icons.queue_music_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Add to favorites',
                visualDensity: VisualDensity.compact,
                onPressed: onFavorites,
                icon: const Icon(Icons.favorite_border_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'More selection actions',
                visualDensity: VisualDensity.compact,
                onPressed: onMore,
                icon: const Icon(Icons.more_vert_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistsView extends StatelessWidget {
  const _ArtistsView({required this.artists});

  final List<ArtistModel> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.person_outline_rounded,
        title: 'No artists yet',
        subtitle:
            'Artists are created automatically from your local music metadata.',
      );
    }
    return LibraryTrackViewport(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 178,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: artists.length,
      cacheExtent: 220,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final controller = context.read<HybridMusicController>();
        return _ArtistCard(
          key: ValueKey<int>(artist.id),
          artist: artist,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title:
                      artist.artist.trim().isEmpty
                          ? 'Unknown artist'
                          : artist.artist,
                  subtitle: 'Tracks by this artist will appear here.',
                  loadTracks: () => controller.tracksForArtist(artist.id),
                ),
              ),
        );
      },
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({super.key, required this.artist, required this.onTap});

  final ArtistModel artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Hero(
              tag: 'artist-art-${artist.id}',
              child: ClipOval(
                child: QueryArtworkWidget(
                  id: artist.id,
                  type: ArtworkType.ARTIST,
                  artworkWidth: 82,
                  artworkHeight: 82,
                  size: 240,
                  nullArtworkWidget: const _EntityArtwork(
                    icon: Icons.person_rounded,
                    circular: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              artist.artist.trim().isEmpty ? 'Unknown artist' : artist.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${artist.numberOfTracks ?? 0} songs',
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView({required this.albums});

  final List<AlbumModel> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.album_outlined,
        title: 'No albums yet',
        subtitle: 'Albums will appear once local audio metadata is available.',
      );
    }
    return LibraryTrackViewport(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 248,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: albums.length,
      cacheExtent: 220,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final album = albums[index];
        final controller = context.read<HybridMusicController>();
        return _AlbumCard(
          key: ValueKey<int>(album.id),
          album: album,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title:
                      album.album.trim().isEmpty
                          ? 'Unknown album'
                          : album.album,
                  subtitle: 'Tracks from this album will appear here.',
                  loadTracks: () => controller.tracksForAlbum(album.id),
                ),
              ),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({super.key, required this.album, required this.onTap});

  final AlbumModel album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Hero(
            tag: 'album-art-${album.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: QueryArtworkWidget(
                id: album.id,
                type: ArtworkType.ALBUM,
                artworkWidth: double.infinity,
                artworkHeight: 180,
                size: 600,
                nullArtworkWidget: const _EntityArtwork(
                  icon: Icons.album_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.album.trim().isEmpty ? 'Unknown album' : album.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${album.artist ?? 'Unknown artist'}  •  ${album.numOfSongs} songs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.read<ThemeProvider>().tokens.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoldersView extends StatelessWidget {
  const _FoldersView({required this.folders, required this.counts});

  final List<String> folders;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _CategoryEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No audio folders found',
        subtitle: 'Folders containing local audio will appear here.',
      );
    }
    return LibraryTrackViewport(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: folders.length,
      cacheExtent: 220,
      addAutomaticKeepAlives: false,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final folder = folders[index];
        return _FolderRow(
          key: ValueKey<String>(folder),
          folder: folder,
          count: counts[folder] ?? 0,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title: folderDisplayName(folder),
                  subtitle: 'Audio files in this folder will appear here.',
                  loadTracks:
                      () => context
                          .read<HybridMusicController>()
                          .tracksForFolder(folder),
                ),
              ),
        );
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.folder,
    required this.count,
    required this.onTap,
  });

  final String folder;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: context.read<ThemeProvider>().tokens.accent.withValues(
                  alpha: 0.12,
                ),
              ),
              child: Icon(
                Icons.folder_rounded,
                color: context.read<ThemeProvider>().tokens.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    folderDisplayName(folder),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$count audio ${count == 1 ? 'file' : 'files'}',
                    style: TextStyle(
                      color: context.read<ThemeProvider>().tokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.read<ThemeProvider>().tokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _VideosView extends StatelessWidget {
  const _VideosView({required this.tracks});

  final List<MediaTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final settings = LibraryDisplaySettings.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final grid = settings.videosLayoutMode == LibraryLayoutMode.grid;
        final compact = settings.videosDensity == LibraryDensity.compact;
        final availableWidth = (MediaQuery.sizeOf(context).width - 40).clamp(
          1.0,
          double.infinity,
        );
        final columnCount = (availableWidth / 290).ceil().clamp(1, 6).toInt();
        final cellWidth =
            (availableWidth - ((columnCount - 1) * 10)) / columnCount;
        final videoAspectRatio = compact ? 2.25 : 1.9;
        final labelHeight = compact ? 48.0 : 68.0;
        final gridExtent = cellWidth / videoAspectRatio + labelHeight;
        return Column(
          children: <Widget>[
            _LibraryViewToolbar(
              controller: controller,
              isVideos: true,
              settings: settings,
            ),
            Expanded(
              child:
                  tracks.isEmpty
                      ? const _CategoryEmptyState(
                        icon: Icons.ondemand_video_rounded,
                        title: 'No matching videos',
                        subtitle:
                            'Try clearing the search or changing the video library.',
                      )
                      : _LibraryScrollSurface(
                        child:
                            grid
                                ? LibraryTrackViewport(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    30,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 280,
                                        mainAxisExtent: gridExtent,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 12,
                                      ),
                                  itemCount: tracks.length,
                                  addAutomaticKeepAlives: false,
                                  cacheExtent: 220,
                                  itemBuilder:
                                      (context, index) => _videoCard(
                                        context,
                                        tracks[index],
                                        compact,
                                      ),
                                )
                                : LibraryTrackViewport(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    30,
                                  ),
                                  itemCount: tracks.length,
                                  addAutomaticKeepAlives: false,
                                  cacheExtent: 220,
                                  separatorBuilder:
                                      (_, _) =>
                                          SizedBox(height: compact ? 12 : 24),
                                  itemBuilder:
                                      (context, index) => _videoCard(
                                        context,
                                        tracks[index],
                                        compact,
                                      ),
                                ),
                      ),
            ),
          ],
        );
      },
    );
  }

  Widget _videoCard(BuildContext context, MediaTrack track, bool compact) =>
      _VideoPreviewCard(
        key: ValueKey<String>(track.id),
        track: track,
        compact: compact,
        onPlay:
            () =>
                Navigator.of(context).push(YazenVideoPlayerScreen.route(track)),
      );
}

class _LibraryViewToolbar extends StatefulWidget {
  const _LibraryViewToolbar({
    required this.controller,
    required this.isVideos,
    required this.settings,
  });

  final HybridMusicController controller;
  final bool isVideos;
  final LibraryDisplaySettings settings;

  @override
  State<_LibraryViewToolbar> createState() => _LibraryViewToolbarState();
}

class _LibraryViewToolbarState extends State<_LibraryViewToolbar> {
  bool _showDisplayControls = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final layout =
        widget.isVideos
            ? widget.settings.videosLayoutMode
            : widget.settings.layoutMode;
    final density =
        widget.isVideos
            ? widget.settings.videosDensity
            : widget.settings.density;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Display settings',
                onPressed:
                    () => setState(
                      () => _showDisplayControls = !_showDisplayControls,
                    ),
                icon: Icon(
                  _showDisplayControls
                      ? Icons.tune_rounded
                      : Icons.tune_outlined,
                ),
              ),
              const Spacer(),
              if (!_showDisplayControls)
                Text(
                  widget.isVideos ? 'Video display' : 'Song display',
                  style: TextStyle(color: tokens.textSecondary),
                ),
            ],
          ),
          if (_showDisplayControls) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                SegmentedButton<LibraryLayoutMode>(
                  segments: const <ButtonSegment<LibraryLayoutMode>>[
                    ButtonSegment(
                      value: LibraryLayoutMode.list,
                      icon: Icon(Icons.view_list_rounded),
                    ),
                    ButtonSegment(
                      value: LibraryLayoutMode.grid,
                      icon: Icon(Icons.grid_view_rounded),
                    ),
                  ],
                  selected: <LibraryLayoutMode>{layout},
                  onSelectionChanged: (value) {
                    final next = value.first;
                    if (widget.isVideos) {
                      widget.settings.setVideosLayoutMode(next);
                    } else {
                      widget.settings.setLayoutMode(next);
                    }
                  },
                ),
                const Spacer(),
                DropdownButton<LibraryDensity>(
                  value: density,
                  underline: const SizedBox.shrink(),
                  items: const <DropdownMenuItem<LibraryDensity>>[
                    DropdownMenuItem(
                      value: LibraryDensity.comfortable,
                      child: Text('Comfortable'),
                    ),
                    DropdownMenuItem(
                      value: LibraryDensity.compact,
                      child: Text('Compact'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (widget.isVideos) {
                      widget.settings.setVideosDensity(value);
                    } else {
                      widget.settings.setDensity(value);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({
    super.key,
    required this.track,
    required this.onPlay,
    this.compact = false,
  });

  final MediaTrack track;
  final VoidCallback onPlay;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: compact ? 2.25 : 1.9,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Hero(
                  tag: 'track-art-${track.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child:
                        track.isVideo
                            ? VideoThumbnailWidget(track: track, size: 340)
                            : YazenMediaArtwork(
                              track: track,
                              size: 340,
                              cropContentBounds: false,
                            ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.66),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      child: Text(
                        'LOCAL',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _DurationBadge(duration: track.duration),
                ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final value = duration == null ? '--:--' : _formatDuration(duration!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView({
    required this.devicePlaylists,
    required this.customPlaylists,
    required this.favorites,
  });

  final List<PlaylistModel> devicePlaylists;
  final List<EchoPlaylist> customPlaylists;
  final List<MediaTrack> favorites;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final totalItems = 1 + customPlaylists.length + devicePlaylists.length;
    return LibraryTrackViewport(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      addAutomaticKeepAlives: true,
      itemCount: totalItems + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Your collections',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _createPlaylist(context, controller),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New'),
              ),
            ],
          );
        }
        if (index == 1) {
          return _CollectionCard(
            key: const ValueKey<String>('collection:favorites'),
            icon: Icons.favorite_rounded,
            artworkTrack: favorites.isEmpty ? null : favorites.last,
            artwork:
                favorites.isEmpty
                    ? null
                    : YazenMediaArtwork(track: favorites.last, size: 82),
            title: 'Favorites',
            subtitle: 'Tracks you want to keep close',
            count: favorites.length,
            onTap: () => Navigator.of(context).push(FavoritesScreen.route()),
          );
        }
        final customIndex = index - 2;
        if (customIndex < customPlaylists.length) {
          final playlist = customPlaylists[customIndex];
          return _CollectionCard(
            key: ValueKey<String>('collection:${playlist.id}'),
            icon: Icons.queue_music_rounded,
            artworkTrack: playlist.coverTrack,
            artwork:
                playlist.coverTrack == null
                    ? null
                    : YazenMediaArtwork(track: playlist.coverTrack!, size: 82),
            title: playlist.name,
            subtitle: 'Custom playlist',
            count: playlist.tracks.length,
            onTap:
                () => Navigator.of(
                  context,
                ).push(PlaylistDetailsScreen.route(playlist.id)),
            onDelete:
                () => controller.playlistManager.deletePlaylist(playlist.id),
          );
        }
        final deviceIndex = customIndex - customPlaylists.length;
        final playlist = devicePlaylists[deviceIndex];
        return _CollectionCard(
          key: ValueKey<String>('device-playlist:${playlist.id}'),
          icon: Icons.library_music_rounded,
          title: playlist.playlist,
          subtitle: 'Device playlist',
          count: playlist.numOfSongs,
          onTap:
              () => Navigator.of(context).push(
                LocalEntityTracksScreen.route(
                  title: playlist.playlist,
                  subtitle:
                      'Tracks from this device playlist will appear here.',
                  loadTracks:
                      () => controller.tracksForDevicePlaylist(playlist.id),
                ),
              ),
        );
      },
    );
  }

  Future<void> _createPlaylist(
    BuildContext context,
    HybridMusicController controller,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreatePlaylistDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    await controller.createPlaylist(name);
  }
}

class _CollectionCard extends StatefulWidget {
  const _CollectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    this.artwork,
    this.artworkTrack,
    this.onTap,
    this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final Widget? artwork;
  final MediaTrack? artworkTrack;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  Future<ArtworkPalette>? _paletteFuture;
  String? _paletteRequestKey;
  int? _paletteAccent;
  int? _paletteSurface;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshPalette();
  }

  @override
  void didUpdateWidget(covariant _CollectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshPalette();
  }

  void _refreshPalette() {
    final track = widget.artworkTrack;
    if (track == null) {
      _paletteFuture = null;
      _paletteRequestKey = null;
      return;
    }
    final tokens = context.read<ThemeProvider>().tokens;
    final requestKey =
        '${track.id}|${track.source.name}|${track.kind.name}|'
        '${track.artworkUri?.toString() ?? ''}';
    final accent = tokens.accent.toARGB32();
    final surface = tokens.surface.toARGB32();
    if (_paletteRequestKey == requestKey &&
        _paletteAccent == accent &&
        _paletteSurface == surface &&
        _paletteFuture != null) {
      return;
    }
    _paletteRequestKey = requestKey;
    _paletteAccent = accent;
    _paletteSurface = surface;
    _paletteFuture = ArtworkPaletteService.instance.paletteForTrack(
      track,
      themeAccent: tokens.accent,
      surface: tokens.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ArtworkPalette>(
      future: _paletteFuture,
      builder: (context, snapshot) {
        final tokens = context.read<ThemeProvider>().tokens;
        final palette = snapshot.data;
        final accent = palette?.safeAccent ?? tokens.accent;
        final surface =
            palette == null
                ? tokens.surface
                : Color.lerp(tokens.surface, palette.dominant, 0.18)!;
        final foreground =
            surface.computeLuminance() > 0.46 ? Colors.black : Colors.white;
        final secondary = foreground.withValues(alpha: 0.68);
        return InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
              gradient: LinearGradient(
                colors: <Color>[surface, Color.lerp(surface, accent, 0.10)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),

            child: Row(
              children: <Widget>[
                widget.artwork ??
                    _EntityArtwork(icon: widget.icon, accent: accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${widget.count} songs',
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Delete playlist',
                    onPressed: widget.onDelete,
                    color: foreground,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EntityArtwork extends StatelessWidget {
  const _EntityArtwork({
    required this.icon,
    this.circular = false,
    this.accent,
  });

  final IconData icon;
  final bool circular;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            tokens.surfaceMuted,
            (accent ?? tokens.accentStrong).withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: accent ?? tokens.accent, size: 34),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: tokens.textSecondary),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context) {
  final tokens = context.read<ThemeProvider>().tokens;
  return BoxDecoration(
    color: tokens.surface.withValues(alpha: 0.24),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: tokens.divider.withValues(alpha: 0.55)),
  );
}

class _MediaPermissionView extends StatelessWidget {
  const _MediaPermissionView({
    required this.onGrant,
    required this.onOpenSettings,
  });

  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.library_music_rounded, size: 52, color: tokens.accent),
            const SizedBox(height: 16),
            const Text(
              'Music permission required',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow YAZEN to access audio on this device to show your local library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Grant permission'),
            ),
            TextButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open app settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _nameController.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
