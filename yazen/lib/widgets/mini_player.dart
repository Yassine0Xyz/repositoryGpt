import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/motion_tokens.dart';
import '../core/theme/theme_provider.dart';
import '../core/theme/theme_tokens.dart';
import '../models/media_track.dart';
import '../services/artwork_palette_service.dart';
import '../services/dynamic_color_settings.dart';
import '../services/playback_policies.dart';
import 'media_artwork.dart';
import 'mini_player_gesture_surface.dart';
import 'play_pause_morph.dart';
import 'echo_motion.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.item,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onStop,
    this.position,
    this.duration,
    this.positionStream,
    this.onPrevious,
    this.onNext,
    this.onDismiss,
    this.onRepeat,
    this.onQueue,
    this.onTap,
    this.repeatMode = AudioServiceRepeatMode.none,
    super.key,
  });

  final MediaItem item;
  final bool isPlaying;
  final Duration? position;
  final Duration? duration;
  final Stream<Duration>? positionStream;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onDismiss;
  final VoidCallback? onRepeat;
  final VoidCallback? onQueue;
  final VoidCallback? onTap;
  final AudioServiceRepeatMode repeatMode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeProvider>().tokens;
    final progress = positionStream == null ? _progress : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return MiniPlayerGestureSurface(
          onNext: onNext,
          onPrevious: onPrevious,
          onExpand: onTap,
          child: AnimatedBuilder(
            animation: DynamicColorSettings.instance,
            builder:
                (context, _) => ValueListenableBuilder<ArtworkPalette>(
                  valueListenable: ArtworkPaletteService.instance.current,
                  builder: (context, palette, _) {
                    final dynamicAccent =
                        DynamicColorSettings.instance.enabled
                            ? palette.safeAccent
                            : tokens.accentStrong;
                    return RepaintBoundary(
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(ThemeRadii.xLarge),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(
                            ThemeRadii.xLarge,
                          ),
                          child: AnimatedContainer(
                            duration: MotionTokens.fast,
                            curve: MotionTokens.standard,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  tokens.surfaceElevated,
                                  Color.lerp(
                                        tokens.surfaceElevated,
                                        tokens.surface,
                                        0.18,
                                      ) ??
                                      tokens.surfaceElevated,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                ThemeRadii.xLarge,
                              ),
                              border: Border.all(
                                color:
                                    isPlaying
                                        ? dynamicAccent.withValues(alpha: 0.38)
                                        : tokens.divider,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: tokens.isLight ? 0.10 : 0.28,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                                if (isPlaying)
                                  BoxShadow(
                                    color: dynamicAccent.withValues(
                                      alpha: 0.08,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: -4,
                                  ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                ThemeSpacing.x2,
                                6,
                                6,
                                5,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      RepaintBoundary(
                                        child: AnimatedSwitcher(
                                          duration: MotionTokens.fast,
                                          transitionBuilder:
                                              (child, animation) =>
                                                  FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                          0.12,
                                                          0,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(animation),
                                                      child: child,
                                                    ),
                                                  ),
                                          child: Hero(
                                            key: ValueKey(
                                              'mini-art-${item.id}',
                                            ),
                                            tag: 'track-art-${item.id}',
                                            child: _MiniArtwork(item: item),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: ThemeSpacing.x2),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            AnimatedSwitcher(
                                              duration: MotionTokens.fast,
                                              transitionBuilder:
                                                  (
                                                    child,
                                                    animation,
                                                  ) => FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                          0.08,
                                                          0,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(animation),
                                                      child: child,
                                                    ),
                                                  ),
                                              child: Hero(
                                                key: ValueKey(
                                                  'mini-title-${item.id}',
                                                ),
                                                tag: 'track-title-${item.id}',
                                                child: Material(
                                                  color: Colors.transparent,
                                                  child: Text(
                                                    item.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: tokens.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.artist ?? 'Unknown artist',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: tokens.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!compact && onQueue != null)
                                        _DockAction(
                                          tooltip: 'Queue',
                                          icon: Icons.queue_music_rounded,
                                          color: tokens.textSecondary,
                                          onPressed: onQueue!,
                                        ),
                                      if (!compact && onRepeat != null)
                                        _DockAction(
                                          tooltip:
                                              'Repeat: ${_repeatLabel(repeatMode)}',
                                          icon:
                                              repeatMode ==
                                                      AudioServiceRepeatMode.one
                                                  ? Icons.repeat_one_rounded
                                                  : Icons.repeat_rounded,
                                          color:
                                              repeatModeIsEnabled(repeatMode)
                                                  ? tokens.accent
                                                  : tokens.textSecondary,
                                          onPressed: onRepeat!,
                                        ),
                                      if (onPrevious != null)
                                        _DockAction(
                                          tooltip: 'Previous',
                                          icon: Icons.skip_previous_rounded,
                                          color: tokens.textSecondary,
                                          onPressed: onPrevious!,
                                        ),
                                      PlayPauseMorph(
                                        playing: isPlaying,
                                        onPressed: onPlayPause,
                                        tooltip: isPlaying ? 'Pause' : 'Play',
                                        minimumSize: const Size(42, 42),
                                        iconSize: 22,
                                        backgroundColor: dynamicAccent,
                                        foregroundColor:
                                            tokens.isLight
                                                ? Colors.white
                                                : Colors.black,
                                      ),
                                      if (onNext != null)
                                        _DockAction(
                                          tooltip: 'Next',
                                          icon: Icons.skip_next_rounded,
                                          color: tokens.textSecondary,
                                          onPressed: onNext!,
                                        ),
                                      _DockAction(
                                        tooltip: 'Stop and close mini player',
                                        icon: Icons.close_rounded,
                                        color: tokens.textSecondary,
                                        onPressed: onDismiss ?? onStop,
                                        size: 38,
                                      ),
                                    ],
                                  ),
                                  if (positionStream != null)
                                    _MiniProgress(
                                      positionStream: positionStream!,
                                      duration: duration,
                                    )
                                  else if (progress != null)
                                    _MiniProgressValue(value: progress),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  String _repeatLabel(AudioServiceRepeatMode mode) {
    return switch (mode) {
      AudioServiceRepeatMode.none => 'off',
      AudioServiceRepeatMode.one => 'one',
      AudioServiceRepeatMode.all => 'all',
      AudioServiceRepeatMode.group => 'group',
    };
  }

  double? get _progress {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0 || position == null) return null;
    return (position!.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.positionStream, required this.duration});

  final Stream<Duration> positionStream;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: positionStream,
        initialData: Duration.zero,
        builder: (context, snapshot) {
          final total = duration?.inMilliseconds ?? 0;
          final value =
              total <= 0 ? 0.0 : (snapshot.data?.inMilliseconds ?? 0) / total;
          return _MiniProgressValue(
            value: value.clamp(0.0, 1.0).toDouble(),
            backgroundColor: tokens.surfaceMuted,
            valueColor: tokens.accent,
          );
        },
      ),
    );
  }
}

class _MiniProgressValue extends StatelessWidget {
  const _MiniProgressValue({
    required this.value,
    this.backgroundColor,
    this.valueColor,
  });

  final double value;
  final Color? backgroundColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 2.5,
          backgroundColor: backgroundColor ?? tokens.surfaceMuted,
          valueColor: AlwaysStoppedAnimation<Color>(
            valueColor ?? tokens.accent,
          ),
        ),
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 40,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return EchoIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      color: color,
      size: size,
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final fallback = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeRadii.large),
        gradient: LinearGradient(
          colors: <Color>[tokens.accentStrong, tokens.accent],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: tokens.isLight ? Colors.white : Colors.black,
      ),
    );

    final source = item.extras?['source']?.toString();
    final id = item.extras?['trackId']?.toString();
    if (source == 'local' && id != null && id.isNotEmpty) {
      return YazenMediaArtwork(
        track: MediaTrack(
          id: id,
          title: item.title,
          artist: item.artist ?? 'Unknown artist',
          album: item.album ?? 'Unknown album',
          source: TrackSource.local,
          uri: Uri.tryParse(item.id),
          artworkUri: item.artUri,
          duration: item.duration,
        ),
        size: 46,
        borderRadius: BorderRadius.circular(ThemeRadii.large),
      );
    }

    final artUri = item.artUri;
    if (artUri == null) return fallback;
    return YazenMediaArtwork(
      size: 46,
      imageUri: artUri,
      borderRadius: BorderRadius.circular(ThemeRadii.large),
      placeholder: fallback,
    );
  }
}
