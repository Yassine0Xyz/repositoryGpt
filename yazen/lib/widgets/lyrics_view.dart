import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/motion_tokens.dart';
import '../core/theme/theme_provider.dart';
import '../services/lyrics_service.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({
    required this.lyricsFuture,
    required this.positionStream,
    this.height = 280,
    this.onLineTap,
    this.onRetry,
    super.key,
  });

  final Future<SyncedLyrics?> lyricsFuture;
  final Stream<Duration> positionStream;
  final double? height;
  final ValueChanged<Duration>? onLineTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return FutureBuilder<SyncedLyrics?>(
      future: lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: height,
            child: Center(
              child: CircularProgressIndicator(
                color: tokens.accent,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final lyrics = snapshot.data;
        if (lyrics == null) {
          return _LyricsMessage(
            message: 'No lyrics found for this track.',
            height: height,
            onRetry: onRetry,
          );
        }
        if (!lyrics.isSynced) {
          return _LyricsMessage(
            message:
                lyrics.plainText ?? 'Lyrics are available without timestamps.',
            height: height,
            onRetry: onRetry,
          );
        }

        return StreamBuilder<Duration>(
          stream: positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return _SyncedLyricsPanel(
              lines: lyrics.lines,
              position: position,
              height: height,
              onLineTap: onLineTap,
            );
          },
        );
      },
    );
  }
}

class LyricsPage extends StatefulWidget {
  const LyricsPage({
    required this.title,
    required this.artist,
    required this.lyricsLoader,
    required this.onRetry,
    required this.positionStream,
    required this.onLineTap,
    super.key,
  });

  final String title;
  final String artist;
  final Future<SyncedLyrics?> Function() lyricsLoader;
  final VoidCallback onRetry;
  final Stream<Duration> positionStream;
  final ValueChanged<Duration> onLineTap;

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  late Future<SyncedLyrics?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = widget.lyricsLoader();
  }

  void _retry() {
    widget.onRetry();
    setState(() => _lyricsFuture = widget.lyricsLoader());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              tokens.background,
              Color.lerp(tokens.background, tokens.accent, 0.11)!,
              tokens.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Back to player',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.lyrics_rounded, color: tokens.accent),
                    const SizedBox(width: 10),
                    Text(
                      'LYRICS',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: LyricsView(
                    lyricsFuture: _lyricsFuture,
                    positionStream: widget.positionStream,
                    height: null,
                    onLineTap: widget.onLineTap,
                    onRetry: _retry,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncedLyricsPanel extends StatefulWidget {
  const _SyncedLyricsPanel({
    required this.lines,
    required this.position,
    required this.height,
    this.onLineTap,
  });

  final List<LyricLine> lines;
  final Duration position;
  final double? height;
  final ValueChanged<Duration>? onLineTap;

  @override
  State<_SyncedLyricsPanel> createState() => _SyncedLyricsPanelState();
}

class _SyncedLyricsPanelState extends State<_SyncedLyricsPanel> {
  final _scrollController = ScrollController();
  List<GlobalKey> _lineKeys = <GlobalKey>[];
  int? _lastScrolledIndex;
  Timer? _manualFollowResumeTimer;
  bool _manualFollowPaused = false;
  bool _programmaticScroll = false;

  @override
  void initState() {
    super.initState();
    _lineKeys = _createLineKeys(widget.lines.length);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  List<GlobalKey> _createLineKeys(int count) =>
      List<GlobalKey>.generate(count, (_) => GlobalKey(), growable: false);

  int get _activeIndex {
    var low = 0;
    var high = widget.lines.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (widget.lines[middle].timestamp <= widget.position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  int _activeWordIndex(LyricLine line) {
    if (line.words.isEmpty) return -1;
    var low = 0;
    var high = line.words.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (line.words[middle].timestamp <= widget.position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  Widget _lineText(BuildContext context, LyricLine line, bool active) {
    final tokens = context.read<ThemeProvider>().tokens;
    if (line.words.length < 2) {
      return Text(line.text, textAlign: TextAlign.center);
    }
    final activeWord = _activeWordIndex(line);
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: <InlineSpan>[
          for (var index = 0; index < line.words.length; index++)
            TextSpan(
              text:
                  '${line.words[index].text}${index == line.words.length - 1 ? '' : ' '}',
              style: TextStyle(
                color:
                    index <= activeWord ? tokens.accent : tokens.textSecondary,
                fontWeight:
                    index == activeWord
                        ? FontWeight.w900
                        : (active ? FontWeight.w700 : FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _lineKeys = _createLineKeys(widget.lines.length);
      _lastScrolledIndex = null;
    }
    if (oldWidget.position != widget.position ||
        oldWidget.lines != widget.lines) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    if (!mounted || _manualFollowPaused || !_scrollController.hasClients) {
      return;
    }
    final index = _activeIndex;
    if (_lastScrolledIndex == index) return;
    _lastScrolledIndex = index;
    if (index < 0 || index >= _lineKeys.length) return;
    final lineContext = _lineKeys[index].currentContext;
    if (lineContext == null) return;
    _programmaticScroll = true;
    unawaited(
      Scrollable.ensureVisible(
        lineContext,
        alignment: 0.48,
        duration: MotionTokens.base,
        curve: MotionTokens.standard,
      ).whenComplete(() => _programmaticScroll = false),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification && !_programmaticScroll) {
      _manualFollowPaused = true;
      _manualFollowResumeTimer?.cancel();
      _manualFollowResumeTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        _manualFollowPaused = false;
        _lastScrolledIndex = null;
        _scrollToActive();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final activeIndex = _activeIndex;
    return Container(
      width: double.infinity,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: tokens.divider.withValues(alpha: 0.72)),
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: <Widget>[
              for (var index = 0; index < widget.lines.length; index++)
                _buildLyricLine(context, tokens, index, activeIndex),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyricLine(
    BuildContext context,
    ThemeTokens tokens,
    int index,
    int activeIndex,
  ) {
    final active = index == activeIndex;
    return KeyedSubtree(
      key: _lineKeys[index],
      child: AnimatedDefaultTextStyle(
        duration: MotionTokens.fast,
        style: TextStyle(
          color: active ? tokens.accent : tokens.textSecondary,
          fontSize: active ? 21 : 16,
          height: 1.5,
          fontWeight: active ? FontWeight.w900 : FontWeight.w600,
        ),
        child: AnimatedScale(
          scale: active ? 1 : 0.96,
          duration: MotionTokens.fast,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0.46,
            duration: MotionTokens.fast,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: InkWell(
                onTap:
                    widget.onLineTap == null
                        ? null
                        : () =>
                            widget.onLineTap!(widget.lines[index].timestamp),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: _lineText(context, widget.lines[index], active),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _manualFollowResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage({
    required this.message,
    required this.height,
    this.onRetry,
  });

  final String message;
  final double? height;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.divider),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary, height: 1.7),
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
