import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/hybrid_music_controller.dart';
import '../core/theme/motion_tokens.dart';
import '../services/scroll_performance_mode.dart';

class NowPlayingScope extends StatefulWidget {
  const NowPlayingScope({required this.child, super.key});

  final Widget child;

  @override
  State<NowPlayingScope> createState() => _NowPlayingScopeState();
}

class _NowPlayingScopeState extends State<NowPlayingScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: MotionTokens.hero,
  );
  bool _pulseScheduled = false;
  bool _isPlaying = false;
  bool _reduceMotion = false;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _isScrolling = ScrollPerformanceMode.isScrolling.value;
    ScrollPerformanceMode.isScrolling.addListener(_onScrollModeChanged);
  }

  void _onScrollModeChanged() {
    _isScrolling = ScrollPerformanceMode.isScrolling.value;
    _syncPulse(_isPlaying, _reduceMotion);
  }

  void _syncPulse(bool playing, bool reduceMotion) {
    _isPlaying = playing;
    _reduceMotion = reduceMotion;
    final shouldAnimate = _isPlaying && !_reduceMotion && !_isScrolling;
    if (shouldAnimate == _pulse.isAnimating || _pulseScheduled) return;

    _pulseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pulseScheduled = false;
      if (!mounted) return;
      final animate = _isPlaying && !_reduceMotion && !_isScrolling;
      if (animate) {
        if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      } else if (_pulse.isAnimating) {
        _pulse.stop(canceled: false);
      }
    });
    // Scroll-end can occur after the last frame. Ensure the post-frame callback
    // is delivered so the indicator resumes without waiting for another event.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final handler = context.read<HybridMusicController>().audioHandler;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _reduceMotion = reducedMotion;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      initialData: handler.activeTrack?.toMediaItem(),
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        final trackId = item?.extras?['trackId']?.toString() ?? item?.id;
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, playbackSnapshot) {
            final playing =
                playbackSnapshot.data?.playing ?? handler.player.playing;
            _isPlaying = playing;
            _syncPulse(playing, reducedMotion);
            return _NowPlayingModel(
              trackId: trackId,
              isPlaying: playing,
              pulse: _pulse,
              child: widget.child,
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    ScrollPerformanceMode.isScrolling.removeListener(_onScrollModeChanged);
    _pulse.dispose();
    super.dispose();
  }
}

class NowPlayingRowState {
  const NowPlayingRowState({
    required this.isCurrent,
    required this.isPlaying,
    required this.pulse,
  });

  final bool isCurrent;
  final bool isPlaying;
  final Animation<double> pulse;
}

NowPlayingRowState? nowPlayingRowStateOf(BuildContext context, String trackId) {
  final model = InheritedModel.inheritFrom<_NowPlayingModel>(
    context,
    aspect: trackId,
  );
  if (model == null) return null;
  return NowPlayingRowState(
    isCurrent: model.trackId == trackId,
    isPlaying: model.isPlaying,
    pulse: model.pulse,
  );
}

class NowPlayingIndicator extends StatelessWidget {
  const NowPlayingIndicator({
    required this.isCurrent,
    required this.isPlaying,
    required this.pulse,
    required this.color,
    super.key,
  });

  final bool isCurrent;
  final bool isPlaying;
  final Animation<double> pulse;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!isCurrent) return const SizedBox.shrink();
    return Semantics(
      label: isPlaying ? 'Now playing' : 'Current track, paused',
      child: CustomPaint(
        size: const Size(20, 20),
        painter: _NowPlayingBarsPainter(
          pulse: pulse,
          playing: isPlaying,
          color: color,
        ),
      ),
    );
  }
}

class _NowPlayingModel extends InheritedModel<String> {
  const _NowPlayingModel({
    required this.trackId,
    required this.isPlaying,
    required this.pulse,
    required super.child,
  });

  final String? trackId;
  final bool isPlaying;
  final Animation<double> pulse;

  @override
  bool updateShouldNotify(_NowPlayingModel oldWidget) =>
      oldWidget.trackId != trackId || oldWidget.isPlaying != isPlaying;

  @override
  bool updateShouldNotifyDependent(
    _NowPlayingModel oldWidget,
    Set<String> dependencies,
  ) {
    for (final id in dependencies) {
      if ((oldWidget.trackId == id || trackId == id) &&
          (oldWidget.trackId != trackId ||
              (trackId == id && oldWidget.isPlaying != isPlaying))) {
        return true;
      }
    }
    return false;
  }
}

class _NowPlayingBarsPainter extends CustomPainter {
  _NowPlayingBarsPainter({
    required this.pulse,
    required this.playing,
    required this.color,
  }) : _paint =
           Paint()
             ..color = color
             ..strokeWidth = 2.6
             ..strokeCap = StrokeCap.round,
       _points = Float32List(16),
       super(repaint: pulse);

  final Animation<double> pulse;
  final bool playing;
  final Color color;
  final Paint _paint;
  final Float32List _points;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 4;
    final centerY = size.height / 2;
    final gap = size.width / (bars + 1);
    final phase = pulse.value * math.pi * 2;
    for (var index = 0; index < bars; index++) {
      final amplitude =
          playing
              ? 0.22 + 0.68 * (0.5 + 0.5 * math.sin(phase + index * 1.28))
              : 0.34 + index % 2 * 0.04;
      final halfHeight = size.height * amplitude / 2;
      final x = gap * (index + 1);
      final offset = index * 4;
      _points[offset] = x;
      _points[offset + 1] = centerY - halfHeight;
      _points[offset + 2] = x;
      _points[offset + 3] = centerY + halfHeight;
    }
    _paint.color = color;
    canvas.drawRawPoints(PointMode.lines, _points, _paint);
  }

  @override
  bool shouldRepaint(covariant _NowPlayingBarsPainter oldDelegate) =>
      oldDelegate.playing != playing || oldDelegate.color != color;
}
