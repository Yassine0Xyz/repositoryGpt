import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/media_track.dart';
import '../../services/local_playlist_manager.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../screens/home/widgets/track_list_tile.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const FavoritesScreen());

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<LocalPlaylistManager>();
    final controller = context.read<HybridMusicController>();
    final tokens = context.watch<ThemeProvider>().tokens;
    final tracks = manager.favorites;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text(
          'Favorites',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          if (tracks.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              onPressed: () => _playAll(controller, tracks),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (tracks.isNotEmpty)
            IconButton(
              tooltip: 'Clear favorites',
              onPressed: () => manager.clearFavorites(),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body:
          tracks.isEmpty
              ? const _EmptyCollection(
                icon: Icons.favorite_border_rounded,
                title: 'No favorites yet',
                subtitle: 'Tap the heart on any local track to keep it here.',
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth - 24 < 470;
                  final tileExtent = compact ? 72.0 : 78.0;
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                    // Preserve the former 2px separator after each fixed row.
                    itemExtent: tileExtent + 2,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: TrackListTile(
                          key: ValueKey<String>('favorite-${track.id}'),
                          track: track,
                          compact: compact,
                          onTap:
                              () => controller.playTrackQueue(
                                tracks,
                                initialIndex: index,
                              ),
                          isFavorite: true,
                          onFavorite: () => manager.toggleFavorite(track),
                          onAddToPlaylist:
                              () => showAddToPlaylistSheet(context, track),
                        ),
                      );
                    },
                  );
                },
              ),
    );
  }

  Future<void> _playAll(
    HybridMusicController controller,
    List<MediaTrack> tracks,
  ) => controller.playTrackQueue(tracks);
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({
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
