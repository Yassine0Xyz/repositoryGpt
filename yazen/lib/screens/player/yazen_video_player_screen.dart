import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/media_track.dart';
import 'yazen_video_player.dart';

class YazenVideoPlayerScreen extends StatefulWidget {
  const YazenVideoPlayerScreen({
    required this.track,
    this.streamUri,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final MediaTrack track;
  final Uri? streamUri;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;

  static Route<void> route(
    MediaTrack track, {
    Uri? streamUri,
    Future<void> Function()? onPrevious,
    Future<void> Function()? onNext,
  }) {
    return MaterialPageRoute<void>(
      builder:
          (_) => YazenVideoPlayerScreen(
            track: track,
            streamUri: streamUri,
            onPrevious: onPrevious,
            onNext: onNext,
          ),
    );
  }

  @override
  State<YazenVideoPlayerScreen> createState() => _YazenVideoPlayerScreenState();
}

class _YazenVideoPlayerScreenState extends State<YazenVideoPlayerScreen> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final uri = widget.streamUri ?? widget.track.uri;
    if (uri == null) {
      _error = StateError('This video is missing its media URI.');
      return;
    }
    _controller =
        uri.scheme == 'content'
            ? VideoPlayerController.contentUri(uri)
            : uri.scheme == 'file'
            ? VideoPlayerController.file(File(uri.toFilePath()))
            : VideoPlayerController.networkUrl(uri);
    _initialization = _controller!
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
          return _controller!.play();
        })
        .catchError((Object error) {
          _error = error;
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child:
            error != null || controller == null || _initialization == null
                ? _ErrorState(error: error)
                : FutureBuilder<void>(
                  future: _initialization,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done ||
                        !controller.value.isInitialized) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    return YazenVideoPlayer(
                      controller: controller,
                      title: widget.track.title,
                      onPrevious: widget.onPrevious,
                      onNext: widget.onNext,
                      onClose: () => Navigator.of(context).maybePop(),
                    );
                  },
                ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              error == null
                  ? 'This video is missing its media URI.'
                  : 'Could not open this video.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
