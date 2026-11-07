import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_tokens.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../models/media_track.dart';
import '../../../widgets/media_artwork.dart';
import '../../../widgets/now_playing_scope.dart';
import '../../../widgets/track_actions_menu.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({
    required this.track,
    required this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.onAddToPlaylist,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.artworkSize = 64,
    required this.compact,
    super.key,
  });

  final MediaTrack track;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selected;
  final double artworkSize;

  /// Computed once by the owning list so each lazy row avoids a LayoutBuilder.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Theme changes should update a row only when the palette changes.
    // Custom background changes notify ThemeProvider too, but do not affect
    // these row colors and should not rebuild every visible song.
    final preset = context.select<ThemeProvider, EchoThemePreset>(
      (provider) => provider.preset,
    );
    final tokens = ThemeTokens.fromPreset(preset);
    final nowPlaying = nowPlayingRowStateOf(context, track.id);
    return _buildRow(context, tokens, nowPlaying, compact);
  }

  Widget _buildRow(
    BuildContext context,
    ThemeTokens tokens,
    NowPlayingRowState? nowPlaying,
    bool compact,
  ) {
    final isCurrentTrack = nowPlaying?.isCurrent ?? false;
    const rowRadius = BorderRadius.all(Radius.circular(ThemeRadii.xLarge));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeSpacing.x1),
      // Material paints the row surface and ink feedback together. This
      // replaces the previous decorated Container + transparent Material pair.
      child: Material(
        color:
            isCurrentTrack
                ? tokens.accent.withValues(alpha: 0.045)
                : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: rowRadius,
          side:
              isCurrentTrack
                  ? BorderSide(color: tokens.accent.withValues(alpha: 0.12))
                  : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: rowRadius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            child: Row(
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    YazenMediaArtwork(
                      track: track,
                      size: compact && artworkSize > 58 ? 58 : artworkSize,
                    ),
                    if (isCurrentTrack)
                      Positioned(
                        right: 3,
                        bottom: 3,
                        child: Container(
                          width: 22,
                          height: 22,
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
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: tokens.isLight ? Colors.white : Colors.black,
                            size: compact ? 28 : 32,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: ThemeSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isCurrentTrack ? tokens.accent : null,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: ThemeSpacing.x1),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(track.duration),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (onFavorite != null || onAddToPlaylist != null)
                  TrackActionsMenu(
                    isFavorite: isFavorite,
                    onFavorite: onFavorite,
                    onAddToPlaylist: onAddToPlaylist,
                    accentColor: tokens.accent,
                    secondaryColor: tokens.textSecondary,
                  ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
