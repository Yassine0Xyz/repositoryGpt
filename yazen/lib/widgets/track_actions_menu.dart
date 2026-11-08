import 'package:flutter/material.dart';

/// Compact, shared action surface for list and grid song tiles.
/// Playback remains the primary tile tap action; this menu exposes secondary
/// actions without reserving multiple icon buttons in every mounted row.
class TrackActionsMenu extends StatelessWidget {
  const TrackActionsMenu({
    required this.isFavorite,
    required this.onFavorite,
    required this.onAddToPlaylist,
    required this.accentColor,
    required this.secondaryColor,
    super.key,
  });

  final bool isFavorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;
  final Color accentColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TrackRowAction>(
      tooltip: 'Song actions',
      padding: EdgeInsets.zero,
      iconSize: 20,
      icon: Icon(Icons.more_vert_rounded, color: secondaryColor),
      onSelected: (action) {
        switch (action) {
          case _TrackRowAction.favorite:
            onFavorite?.call();
            break;
          case _TrackRowAction.addToPlaylist:
            onAddToPlaylist?.call();
            break;
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<_TrackRowAction>>[
        if (onFavorite != null)
          PopupMenuItem<_TrackRowAction>(
            value: _TrackRowAction.favorite,
            child: Row(
              children: <Widget>[
                Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: isFavorite ? accentColor : secondaryColor,
                ),
                const SizedBox(width: 12),
                Text(isFavorite ? 'Remove from favorites' : 'Add to favorites'),
              ],
            ),
          ),
        if (onAddToPlaylist != null)
          const PopupMenuItem<_TrackRowAction>(
            value: _TrackRowAction.addToPlaylist,
            child: Row(
              children: <Widget>[
                Icon(Icons.playlist_add_rounded, size: 20),
                SizedBox(width: 12),
                Text('Add to playlist'),
              ],
            ),
          ),
      ],
    );
  }
}

enum _TrackRowAction { favorite, addToPlaylist }
