import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_track.dart';
import '../services/local_playlist_manager.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, MediaTrack track) =>
    showAddTracksToPlaylistSheet(context, <MediaTrack>[track]);

Future<void> showAddTracksToPlaylistSheet(
  BuildContext context,
  Iterable<MediaTrack> selectedTracks,
) async {
  final manager = context.read<LocalPlaylistManager>();
  if (!manager.isReady) return;
  final tracks = selectedTracks.toList(growable: false);
  if (tracks.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final playlists = manager.playlists;
      if (playlists.isEmpty) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Text(
              'Create a custom playlist first from Library → Playlists.',
            ),
          ),
        );
      }
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: <Widget>[
            Text(
              'Add to playlist',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              tracks.length == 1
                  ? tracks.first.title
                  : '${tracks.length} selected songs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...playlists.map(
              (playlist) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(
                  playlist.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: Text('${playlist.tracks.length}'),
                onTap: () async {
                  await manager.addTracksToPlaylist(playlist.id, tracks);
                  if (context.mounted) Navigator.pop(context);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Added ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} to ${playlist.name}',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
