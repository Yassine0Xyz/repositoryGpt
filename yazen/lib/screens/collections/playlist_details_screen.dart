import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../queue/queue_screen.dart';
import '../home/widgets/track_list_tile.dart';
import '../player/full_player_screen.dart';

class PlaylistDetailsScreen extends StatefulWidget {
  const PlaylistDetailsScreen({required this.playlistId, super.key});

  final String playlistId;

  static Route<void> route(String playlistId) => MaterialPageRoute<void>(
    builder: (_) => PlaylistDetailsScreen(playlistId: playlistId),
  );

  @override
  State<PlaylistDetailsScreen> createState() => _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends State<PlaylistDetailsScreen> {
  final Set<String> _selectedIds = <String>{};
  _PlaylistSort _sort = _PlaylistSort.manual;
  bool _isManaging = false;

  bool get _manageMode => _isManaging;

  EchoPlaylist? _findPlaylist(LocalPlaylistManager manager) {
    for (final playlist in manager.playlists) {
      if (playlist.id == widget.playlistId) return playlist;
    }
    return null;
  }

  List<MediaTrack> _orderedTracks(EchoPlaylist playlist) {
    final tracks = List<MediaTrack>.of(playlist.tracks);
    switch (_sort) {
      case _PlaylistSort.manual:
        return tracks;
      case _PlaylistSort.newest:
        tracks.sort(
          (a, b) => (b.modifiedAt ?? DateTime(0)).compareTo(
            a.modifiedAt ?? DateTime(0),
          ),
        );
      case _PlaylistSort.az:
        tracks.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _PlaylistSort.mostPlayed:
        tracks.sort((a, b) {
          final manager = context.read<LocalPlaylistManager>();
          final count = manager
              .playCount(b.id)
              .compareTo(manager.playCount(a.id));
          if (count != 0) return count;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
    }
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<LocalPlaylistManager>();
    final controller = context.read<HybridMusicController>();
    final tokens = context.watch<ThemeProvider>().tokens;
    final playlist = _findPlaylist(manager);
    if (playlist == null) {
      return const Scaffold(
        body: _PlaylistEmptyCollection(
          icon: Icons.queue_music_rounded,
          title: 'Playlist not found',
          subtitle: 'This playlist may have been removed.',
        ),
      );
    }

    final tracks = _orderedTracks(playlist);
    final canReorder = _sort == _PlaylistSort.manual && _manageMode;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          if (_manageMode)
            IconButton(
              tooltip: 'Exit manage mode',
              onPressed: _exitManageMode,
              icon: const Icon(Icons.close_rounded),
            )
          else ...<Widget>[
            IconButton(
              tooltip: 'Songs sort',
              onPressed: () => _showSortSheet(context),
              icon: const Icon(Icons.sort_rounded),
            ),
            PopupMenuButton<_PlaylistMenuAction>(
              tooltip: 'Playlist options',
              onSelected: (action) => _handleMenuAction(action, playlist),
              itemBuilder:
                  (context) => const <PopupMenuEntry<_PlaylistMenuAction>>[
                    PopupMenuItem(
                      value: _PlaylistMenuAction.addSong,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.library_add_rounded),
                        title: Text('Add song'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _PlaylistMenuAction.manage,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.checklist_rounded),
                        title: Text('Manage'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _PlaylistMenuAction.rename,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.drive_file_rename_outline_rounded),
                        title: Text('Rename playlist'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _PlaylistMenuAction.delete,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete playlist'),
                      ),
                    ),
                  ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: <Widget>[
          playlist.tracks.isEmpty
              ? const _PlaylistEmptyCollection(
                icon: Icons.queue_music_rounded,
                title: 'Playlist is empty',
                subtitle: 'Add tracks from the local library.',
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth - 24 < 470;
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 118),
                    itemCount: tracks.length + 1,
                    onReorderItem:
                        canReorder
                            ? (oldIndex, newIndex) async {
                              if (oldIndex == 0 || newIndex == 0) return;
                              final oldTrackIndex = oldIndex - 1;
                              await manager.moveWithinPlaylist(
                                playlist.id,
                                oldTrackIndex,
                                newIndex - 1,
                              );
                            }
                            : (_, _) {},
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          key: const ValueKey('playlist-header'),
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '${playlist.tracks.length} songs',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_manageMode)
                                Text(
                                  '${_selectedIds.length} selected',
                                  style: TextStyle(color: tokens.accent),
                                )
                              else
                                FilledButton.tonalIcon(
                                  onPressed:
                                      () => controller.playTrackQueue(
                                        playlist.tracks,
                                      ),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Play all'),
                                ),
                            ],
                          ),
                        );
                      }
                      final track = tracks[index - 1];
                      final selected = _selectedIds.contains(track.id);
                      return Dismissible(
                        key: ValueKey('${playlist.id}-${track.id}'),
                        direction:
                            _manageMode
                                ? DismissDirection.none
                                : DismissDirection.endToStart,
                        background: const _DeleteBackground(),
                        onDismissed:
                            (_) => manager.removeFromPlaylist(
                              playlist.id,
                              track.id,
                            ),
                        child: TrackListTile(
                          key: ValueKey('track-${playlist.id}-${track.id}'),
                          track: track,
                          compact: compact,
                          selected: selected,
                          trailing:
                              _manageMode
                                  ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      IconButton(
                                        tooltip: 'Edit metadata',
                                        onPressed: () => _editMetadata(track),
                                        icon: const Icon(Icons.edit_rounded),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: IconButton(
                                          tooltip: 'Drag to arrange',
                                          onPressed: () {},
                                          icon: const Icon(
                                            Icons.drag_handle_rounded,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                  : null,
                          onLongPress: () => _toggleSelection(track),
                          onTap: () {
                            if (_manageMode) {
                              _toggleSelection(track);
                            } else {
                              controller.playTrackQueue(
                                playlist.tracks,
                                initialIndex: playlist.tracks.indexOf(track),
                              );
                            }
                          },
                          isFavorite: controller.isFavorite(track),
                          onFavorite: () => controller.toggleFavorite(track),
                          onAddToPlaylist:
                              () => _showTrackActions(context, track),
                        ),
                      );
                    },
                  );
                },
              ),
          const Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _PlaylistMiniPlayerHost(),
          ),
        ],
      ),
      bottomNavigationBar:
          _manageMode
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              _selectedIds.isEmpty
                                  ? null
                                  : () => _removeSelected(context, playlist),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(
                            _selectedIds.isEmpty
                                ? 'Select songs to remove'
                                : 'Remove ${_selectedIds.length} songs',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Hide selected',
                        onPressed:
                            _selectedIds.isEmpty
                                ? null
                                : () => _hideSelected(context, playlist),
                        icon: const Icon(Icons.visibility_off_rounded),
                      ),
                    ],
                  ),
                ),
              )
              : null,
    );
  }

  void _toggleSelection(MediaTrack track) {
    setState(() {
      _isManaging = true;
      if (!_selectedIds.add(track.id)) _selectedIds.remove(track.id);
    });
  }

  void _exitManageMode() {
    if (!mounted) return;
    setState(() {
      _isManaging = false;
      _selectedIds.clear();
    });
  }

  Future<void> _showSortSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<_PlaylistSort>(
      context: context,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      builder:
          (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: <Widget>[
                const Text(
                  'Songs sort',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                RadioGroup<_PlaylistSort>(
                  groupValue: _sort,
                  onChanged: (value) => Navigator.pop(context, value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final option in _PlaylistSort.values)
                        RadioListTile<_PlaylistSort>(
                          value: option,
                          title: Text(option.label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
    if (selected != null && mounted) setState(() => _sort = selected);
  }

  Future<void> _handleMenuAction(
    _PlaylistMenuAction action,
    EchoPlaylist playlist,
  ) async {
    switch (action) {
      case _PlaylistMenuAction.addSong:
        await _showAddSongsSheet(context, playlist);
      case _PlaylistMenuAction.manage:
        setState(() {
          _isManaging = true;
          _selectedIds.clear();
          _sort = _PlaylistSort.manual;
        });
      case _PlaylistMenuAction.rename:
        await _renamePlaylist(context, playlist);
      case _PlaylistMenuAction.delete:
        await _delete(context, context.read<LocalPlaylistManager>(), playlist);
    }
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    EchoPlaylist playlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RenamePlaylistDialog(initialName: playlist.name),
      );
      if (name == null || !mounted) return;
      await this.context.read<LocalPlaylistManager>().renamePlaylist(
        playlist.id,
        name,
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to save playlist name: $error')),
      );
    }
  }

  Future<void> _showAddSongsSheet(
    BuildContext context,
    EchoPlaylist playlist,
  ) async {
    final controller = context.read<HybridMusicController>();
    final manager = context.read<LocalPlaylistManager>();
    final selected = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              final available = controller.localSongs
                  .where(
                    (track) =>
                        !playlist.tracks.any((item) => item.id == track.id),
                  )
                  .toList(growable: false);
              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.72,
                  child: Column(
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Add song',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 470;
                            return ListView.builder(
                              itemExtent: compact ? 72 : 78,
                              itemCount: available.length,
                              itemBuilder: (context, index) {
                                final track = available[index];
                                final isSelected = selected.contains(track.id);
                                return TrackListTile(
                                  key: ValueKey<String>(
                                    'playlist-add-${track.id}',
                                  ),
                                  track: track,
                                  compact: compact,
                                  selected: isSelected,
                                  onTap:
                                      () => setSheetState(() {
                                        if (!selected.add(track.id)) {
                                          selected.remove(track.id);
                                        }
                                      }),
                                  onLongPress:
                                      () => setSheetState(() {
                                        if (!selected.add(track.id)) {
                                          selected.remove(track.id);
                                        }
                                      }),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: FilledButton(
                          onPressed:
                              selected.isEmpty
                                  ? null
                                  : () async {
                                    final tracks = available
                                        .where(
                                          (track) =>
                                              selected.contains(track.id),
                                        )
                                        .toList(growable: false);
                                    await manager.addTracksToPlaylist(
                                      playlist.id,
                                      tracks,
                                    );
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                  },
                          child: Text('Confirm (${selected.length})'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _removeSelected(
    BuildContext context,
    EchoPlaylist playlist,
  ) async {
    final ids = Set<String>.of(_selectedIds);
    await context.read<LocalPlaylistManager>().removeTracksFromPlaylist(
      playlist.id,
      ids,
    );
    if (mounted) setState(_selectedIds.clear);
  }

  Future<void> _hideSelected(
    BuildContext context,
    EchoPlaylist playlist,
  ) async {
    final ids = Set<String>.of(_selectedIds);
    final manager = context.read<LocalPlaylistManager>();
    await manager.setHidden(ids, hidden: true);
    await manager.removeTracksFromPlaylist(playlist.id, ids);
    if (mounted) _exitManageMode();
  }

  Future<void> _editMetadata(MediaTrack track) async {
    final manager = context.read<LocalPlaylistManager>();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _EditMetadataDialog(track: track),
    );
    if (result == null || !mounted) return;
    await manager.updateTrackMetadata(
      track.id,
      title: result[0],
      artist: result[1],
      album: result[2],
    );
  }

  Future<void> _showTrackActions(BuildContext context, MediaTrack track) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to playlist'),
                  onTap: () async {
                    Navigator.pop(context);
                    await showAddToPlaylistSheet(this.context, track);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    LocalPlaylistManager manager,
    EchoPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete playlist?'),
            content: Text(
              'Delete ${playlist.name}? The tracks themselves will remain on your device.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await manager.deletePlaylist(playlist.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _PlaylistMiniPlayerHost extends StatelessWidget {
  const _PlaylistMiniPlayerHost();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) return const SizedBox.shrink();
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder:
              (context, playbackSnapshot) => MiniPlayer(
                item: item,
                isPlaying: playbackSnapshot.data?.playing ?? false,
                duration: item.duration,
                positionStream: handler.player.positionStream,
                onPlayPause: controller.togglePlayback,
                onPrevious: handler.skipToPrevious,
                onNext: handler.skipToNext,
                onDismiss: () => unawaited(handler.stop()),
                onRepeat: controller.toggleRepeat,
                onQueue: () => Navigator.of(context).push(QueueScreen.route()),
                repeatMode:
                    playbackSnapshot.data?.repeatMode ?? controller.repeatMode,
                onStop: handler.stop,
                onTap:
                    () => Navigator.of(context).push(FullPlayerScreen.route()),
              ),
        );
      },
    );
  }
}

class _EditMetadataDialog extends StatefulWidget {
  const _EditMetadataDialog({required this.track});

  final MediaTrack track;

  @override
  State<_EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<_EditMetadataDialog> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.track.title);
    _artist = TextEditingController(text: widget.track.artist);
    _album = TextEditingController(text: widget.track.album);
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit metadata'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _artist,
              decoration: const InputDecoration(labelText: 'Artist'),
            ),
            TextField(
              controller: _album,
              decoration: const InputDecoration(labelText: 'Album'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.pop(context, <String>[
                _title.text,
                _artist.text,
                _album.text,
              ]),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

enum _PlaylistSort { manual, newest, az, mostPlayed }

extension on _PlaylistSort {
  String get label => switch (this) {
    _PlaylistSort.manual => 'Manual arrange',
    _PlaylistSort.newest => 'Newest',
    _PlaylistSort.az => 'A to Z',
    _PlaylistSort.mostPlayed => 'Most played',
  };
}

enum _PlaylistMenuAction { addSong, manage, rename, delete }

class _RenamePlaylistDialog extends StatefulWidget {
  const _RenamePlaylistDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename playlist'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Playlist name',
          helperText: 'Other playlists may use the same name.',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            Navigator.pop(context, value);
          }
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, _nameController.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PlaylistEmptyCollection extends StatelessWidget {
  const _PlaylistEmptyCollection({
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
            Icon(icon, color: tokens.textSecondary, size: 64),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}
