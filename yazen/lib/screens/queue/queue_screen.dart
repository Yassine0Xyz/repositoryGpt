import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/hybrid_audio_handler.dart';
import '../../widgets/media_artwork.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const QueueScreen());

  @override
  Widget build(BuildContext context) {
    final handler = context.read<HybridMusicController>().audioHandler;
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text(
          'Queue',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          StreamBuilder<List<MediaItem>>(
            stream: handler.queue,
            initialData: handler.queue.value,
            builder:
                (context, snapshot) => IconButton(
                  tooltip: 'Clear queue',
                  onPressed:
                      snapshot.data?.isEmpty ?? true
                          ? null
                          : () => _confirmClear(context, handler),
                  icon: const Icon(Icons.clear_all_rounded),
                ),
          ),
        ],
      ),
      body: StreamBuilder<List<MediaItem>>(
        stream: handler.queue,
        initialData: handler.queue.value,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <MediaItem>[];
          if (items.isEmpty) return const _EmptyQueue();
          final tracks = handler.queueTracks;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: items.length,
            onReorderItem: (oldIndex, newIndex) async {
              final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
              await handler.moveInQueue(oldIndex, targetIndex);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              final track = index < tracks.length ? tracks[index] : null;
              final isCurrent = index == handler.currentQueueIndex;
              return Dismissible(
                key: ValueKey('queue-${item.id}-$index'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => handler.removeFromQueue(index),
                background: const _DeleteBackground(),
                child: _QueueTile(
                  item: item,
                  track: track,
                  index: index,
                  isCurrent: isCurrent,
                  onPlay: () => handler.playQueueIndex(index),
                  onPlayNext:
                      index <= handler.currentQueueIndex
                          ? null
                          : () => handler.moveInQueue(
                            index,
                            handler.currentQueueIndex + 1,
                          ),
                  onRemove: () => handler.removeFromQueue(index),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    HybridAudioHandler handler,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear queue?'),
            content: const Text(
              'Playback will stop and all queued items will be removed.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
    if (confirmed == true) await handler.clearQueue();
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.item,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.onPlay,
    required this.onPlayNext,
    required this.onRemove,
  });

  final MediaItem item;
  final MediaTrack? track;
  final int index;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback? onPlayNext;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isCurrent ? tokens.surfaceElevated : tokens.surface,
      child: ListTile(
        onTap: onPlay,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ReorderableDragStartListener(
          index: index,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              YazenMediaArtwork(
                track: track,
                imageUri: item.artUri,
                size: 54,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 8),
              Icon(Icons.drag_indicator_rounded, color: tokens.textSecondary),
            ],
          ),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isCurrent ? tokens.accent : tokens.textPrimary,
          ),
        ),
        subtitle: Text(
          [
            item.artist ?? 'Unknown artist',
            if (item.album?.trim().isNotEmpty ?? false) item.album!,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.textSecondary),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'play') onPlay();
            if (action == 'next') onPlayNext?.call();
            if (action == 'remove') onRemove();
          },
          itemBuilder:
              (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem(value: 'play', child: Text('Play now')),
                if (onPlayNext != null)
                  const PopupMenuItem(value: 'next', child: Text('Play next')),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.queue_music_rounded,
              size: 64,
              color: tokens.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your queue is empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Play a local track or add one to start building your next listening session.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
