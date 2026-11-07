import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/theme_provider.dart';

class YazenVideoPlayer extends StatefulWidget {
  const YazenVideoPlayer({
    required this.controller,
    required this.title,
    this.onPrevious,
    this.onNext,
    this.onClose,
    this.onExpand,
    this.compact = false,
    super.key,
  });

  final VideoPlayerController controller;
  final String title;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;
  final bool compact;

  @override
  State<YazenVideoPlayer> createState() => _YazenVideoPlayerState();
}

class _YazenVideoPlayerState extends State<YazenVideoPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _platform = MethodChannel('yazen/player_controls');

  late final AnimationController _hudAnimation;
  Timer? _hideTimer;
  Timer? _lockRevealTimer;
  bool _hudVisible = true;
  bool _lockRevealVisible = false;
  bool _locked = false;
  bool _isFullscreen = false;
  int _aspectMode = 0;
  double _brightness = 0.65;
  double _volume = 0.75;
  String? _gestureLabel;
  Timer? _gestureTimer;
  bool _appVisible = true;
  bool _resumeAfterBackground = false;
  bool? _lastKeepScreenOn;

  @override
  void initState() {
    super.initState();
    _hudAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onVideoChanged);
    _syncKeepScreenOn();
    _scheduleHudHide();
  }

  @override
  void didUpdateWidget(covariant YazenVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onVideoChanged);
      widget.controller.addListener(_onVideoChanged);
    }
    _syncKeepScreenOn();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android reports inactive while entering picture-in-picture. Keep video
    // playing in that visible mode; pause only when the app actually moves to
    // the background, then resume only if it was playing before the transition.
    _appVisible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (widget.controller.value.isPlaying) {
        _resumeAfterBackground = true;
        unawaited(widget.controller.pause());
      }
    } else if (state == AppLifecycleState.resumed && _resumeAfterBackground) {
      _resumeAfterBackground = false;
      unawaited(widget.controller.play());
    }
    _syncKeepScreenOn();
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      unawaited(
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]).catchError((_) {}),
      );
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        ).catchError((_) {}),
      );
    }
    _syncKeepScreenOn(force: false);
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _lockRevealTimer?.cancel();
    _gestureTimer?.cancel();
    widget.controller.removeListener(_onVideoChanged);
    _hudAnimation.dispose();
    super.dispose();
  }

  void _onVideoChanged() {
    _syncKeepScreenOn();
    if (mounted) setState(() {});
  }

  void _syncKeepScreenOn({bool? force}) {
    if (!Platform.isAndroid) return;
    final value = widget.controller.value;
    final keepScreenOn =
        force ?? (_appVisible && value.isInitialized && value.isPlaying);
    if (_lastKeepScreenOn == keepScreenOn) return;
    _lastKeepScreenOn = keepScreenOn;
    unawaited(
      _platform
          .invokeMethod<void>('setKeepScreenOn', <String, bool>{
            'enabled': keepScreenOn,
          })
          .catchError((_) {}),
    );
  }

  void _scheduleHudHide() {
    _hideTimer?.cancel();
    if (_locked) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _locked) return;
      _setHudVisible(false);
    });
  }

  void _setHudVisible(bool visible) {
    _hideTimer?.cancel();
    setState(() => _hudVisible = visible);
    if (visible) {
      _hudAnimation.forward();
      _scheduleHudHide();
    } else {
      _hudAnimation.reverse();
    }
  }

  void _toggleHud() {
    if (_locked) return;
    _setHudVisible(!_hudVisible);
  }

  Future<void> _seekBy(Duration delta) async {
    final value = widget.controller.value;
    if (!value.isInitialized) return;
    final target = value.position + delta;
    final duration = value.duration;
    await widget.controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > duration
          ? duration
          : target,
    );
    _showGesture(delta.isNegative ? '-10s' : '+10s');
    _scheduleHudHide();
  }

  void _showGesture(String label) {
    setState(() => _gestureLabel = label);
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _gestureLabel = null);
    });
  }

  Future<void> _adjustVertical({
    required bool right,
    required double delta,
  }) async {
    if (_locked) return;
    if (right) {
      _volume = (_volume - delta / 420).clamp(0.0, 1.0).toDouble();
      try {
        await _platform.invokeMethod<void>('setVolume', <String, dynamic>{
          'value': _volume,
        });
      } on MissingPluginException catch (_) {
        _showGesture('Volume control unavailable');
        return;
      } on PlatformException catch (_) {
        _showGesture('Volume control unavailable');
        return;
      }
      _showGesture('Volume ${(100 * _volume).round()}%');
    } else {
      _brightness = (_brightness - delta / 420).clamp(0.05, 1.0).toDouble();
      try {
        await _platform.invokeMethod<void>('setBrightness', <String, dynamic>{
          'value': _brightness,
        });
      } on MissingPluginException catch (_) {
        _showGesture('Brightness control unavailable');
        return;
      } on PlatformException catch (_) {
        _showGesture('Brightness control unavailable');
        return;
      }
      _showGesture('Brightness ${(100 * _brightness).round()}%');
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (mounted) setState(() => _isFullscreen = !_isFullscreen);
    _scheduleHudHide();
  }

  Future<void> _enterPip() async {
    try {
      await _platform.invokeMethod<void>('enterPictureInPicture');
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Picture-in-picture is not available on this device.'),
        ),
      );
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Picture-in-picture is not available on this device.'),
        ),
      );
    }
  }

  void _revealUnlockButton() {
    if (!_locked) return;
    _lockRevealTimer?.cancel();
    setState(() => _lockRevealVisible = true);
    _lockRevealTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _locked) setState(() => _lockRevealVisible = false);
    });
  }

  void _toggleLock() {
    if (_locked) {
      _lockRevealTimer?.cancel();
      setState(() {
        _locked = false;
        _lockRevealVisible = false;
        _hudVisible = true;
      });
      _hudAnimation.forward();
      _scheduleHudHide();
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _hudVisible = false;
      _lockRevealVisible = false;
    });
    _hudAnimation.reverse();
  }

  BoxFit get _fit => switch (_aspectMode) {
    0 => BoxFit.contain,
    1 => BoxFit.cover,
    _ => BoxFit.fill,
  };

  String get _aspectLabel => switch (_aspectMode) {
    0 => 'Fit',
    1 => 'Cover',
    _ => 'Stretch',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final value = widget.controller.value;
    if (!value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }
    if (widget.compact) return _buildCompact(context, tokens, value);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const _AmbientBackdrop(),
            Center(
              child: AspectRatio(
                aspectRatio:
                    value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_isFullscreen ? 0 : 18),
                  child: FittedBox(
                    fit: _fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: value.size.width,
                      height: value.size.height,
                      child: VideoPlayer(widget.controller),
                    ),
                  ),
                ),
              ),
            ),
            if (!_locked)
              Row(
                children: <Widget>[
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: () => _seekBy(const Duration(seconds: -10)),
                      onVerticalDragUpdate:
                          (details) => _adjustVertical(
                            right: false,
                            delta: details.delta.dy,
                          ),
                      onTap: _toggleHud,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: () => _seekBy(const Duration(seconds: 10)),
                      onVerticalDragUpdate:
                          (details) => _adjustVertical(
                            right: true,
                            delta: details.delta.dy,
                          ),
                      onTap: _toggleHud,
                    ),
                  ),
                ],
              ),
            if (_locked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _revealUnlockButton,
                ),
              ),
            if (_gestureLabel != null)
              Center(
                child: IgnorePointer(
                  child: AnimatedScale(
                    scale: _gestureLabel == null ? 0.7 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.64),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          _gestureLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!_locked)
              FadeTransition(
                opacity: _hudAnimation,
                child: IgnorePointer(
                  ignoring: !_hudVisible && !_locked,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: _GlassBar(
                          child: Row(
                            children: <Widget>[
                              IconButton(
                                tooltip: 'Back',
                                onPressed:
                                    widget.onClose ??
                                    () => Navigator.maybePop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Aspect ratio: $_aspectLabel',
                                onPressed:
                                    () => setState(
                                      () => _aspectMode = (_aspectMode + 1) % 3,
                                    ),
                                icon: Text(
                                  _aspectLabel,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Speed',
                                onPressed: () => _showSpeedPicker(context),
                                icon: const Icon(Icons.speed_rounded),
                              ),
                              IconButton(
                                tooltip: 'Picture in picture',
                                onPressed: _enterPip,
                                icon: const Icon(
                                  Icons.picture_in_picture_alt_rounded,
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    _locked
                                        ? 'Unlock controls'
                                        : 'Lock controls',
                                onPressed: _toggleLock,
                                icon: Icon(
                                  _locked
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_locked)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: bottomInset + 8,
                          child: _GlassBar(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                VideoProgressIndicator(
                                  widget.controller,
                                  allowScrubbing: true,
                                  colors: VideoProgressColors(
                                    playedColor: tokens.accent,
                                    bufferedColor: Colors.white38,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: <Widget>[
                                    Text(
                                      _format(value.position),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Back 10 seconds',
                                      onPressed:
                                          () => _seekBy(
                                            const Duration(seconds: -10),
                                          ),
                                      icon: const Icon(Icons.replay_10_rounded),
                                    ),
                                    IconButton(
                                      tooltip: 'Previous',
                                      onPressed: widget.onPrevious,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                    ),
                                    IconButton.filled(
                                      tooltip:
                                          value.isPlaying ? 'Pause' : 'Play',
                                      onPressed:
                                          () =>
                                              value.isPlaying
                                                  ? widget.controller.pause()
                                                  : widget.controller.play(),
                                      icon: Icon(
                                        value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Next',
                                      onPressed: widget.onNext,
                                      icon: const Icon(Icons.skip_next_rounded),
                                    ),
                                    IconButton(
                                      tooltip: 'Forward 10 seconds',
                                      onPressed:
                                          () => _seekBy(
                                            const Duration(seconds: 10),
                                          ),
                                      icon: const Icon(
                                        Icons.forward_10_rounded,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _format(value.duration),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Fullscreen',
                                      onPressed: _toggleFullscreen,
                                      icon: Icon(
                                        _isFullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (!_locked && !_hudVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: bottomInset + 2,
                child: IgnorePointer(
                  child: VideoProgressIndicator(
                    widget.controller,
                    allowScrubbing: false,
                    colors: VideoProgressColors(
                      playedColor: tokens.accent,
                      bufferedColor: Colors.white54,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ),
            if (_locked && _lockRevealVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Center(
                  child: IconButton.filledTonal(
                    tooltip: 'Unlock controls',
                    onPressed: _toggleLock,
                    icon: const Icon(Icons.lock_rounded),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCompact(
    BuildContext context,
    ThemeTokens tokens,
    VideoPlayerValue value,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: Colors.black,
            child: VideoPlayer(widget.controller),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Color(0xDD000000)],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black87, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More video controls',
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onSelected: (value) {
                        switch (value) {
                          case 'fit':
                            setState(() => _aspectMode = (_aspectMode + 1) % 3);
                          case 'speed':
                            _showSpeedPicker(context);
                          case 'pip':
                            _enterPip();
                          case 'lock':
                            _toggleLock();
                        }
                      },
                      itemBuilder:
                          (_) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'fit',
                              child: Text('Fit: $_aspectLabel'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'speed',
                              child: Text('Playback speed'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'pip',
                              child: Text('Picture in picture'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'lock',
                              child: Text('Lock controls'),
                            ),
                          ],
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Expand player',
                      onPressed: widget.onExpand,
                      icon: const Icon(Icons.open_in_full_rounded, size: 18),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    _CompactVideoAction(
                      tooltip: 'Back 10 seconds',
                      icon: Icons.replay_10_rounded,
                      onPressed: () => _seekBy(const Duration(seconds: -10)),
                    ),
                    _CompactVideoAction(
                      tooltip: 'Previous',
                      icon: Icons.skip_previous_rounded,
                      onPressed: widget.onPrevious,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      onPressed:
                          () =>
                              value.isPlaying
                                  ? widget.controller.pause()
                                  : widget.controller.play(),
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                      ),
                    ),
                    _CompactVideoAction(
                      tooltip: 'Next',
                      icon: Icons.skip_next_rounded,
                      onPressed: widget.onNext,
                    ),
                    _CompactVideoAction(
                      tooltip: 'Forward 10 seconds',
                      icon: Icons.forward_10_rounded,
                      onPressed: () => _seekBy(const Duration(seconds: 10)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSpeedPicker(BuildContext context) async {
    final speed = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) =>
              _SpeedSheet(current: widget.controller.value.playbackSpeed),
    );
    if (speed != null) await widget.controller.setPlaybackSpeed(speed);
  }

  String _format(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _CompactVideoAction extends StatelessWidget {
  const _CompactVideoAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Controls intentionally sit directly over the video. The edge gradient
    // behind the player provides legibility without large glass panels.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    );
  }
}

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.current});

  final double current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              <double>[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
                  .map(
                    (speed) => ChoiceChip(
                      label: Text('${speed}x'),
                      selected: current == speed,
                      onSelected: (_) => Navigator.pop(context, speed),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}
