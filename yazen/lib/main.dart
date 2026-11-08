import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'controllers/hybrid_music_controller.dart';
import 'core/theme/theme_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/hybrid_audio_handler.dart';
import 'services/media_library_service.dart';
import 'services/local_playlist_manager.dart';
import 'services/ambient_color_flow_settings.dart';
import 'services/startup_restore.dart';
import 'services/app_route_observer.dart';
import 'services/scroll_performance_mode.dart';
import 'widgets/now_playing_scope.dart';
import 'diagnostics/core/diagnostics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DiagnosticsService.instance.start();
  late final HybridAudioHandler audioHandler;
  try {
    audioHandler = await AudioService.init<HybridAudioHandler>(
      builder: HybridAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yassine.yazen.channel.audio',
        androidNotificationChannelName: 'Music playback',
        androidNotificationIcon: 'drawable/yazen_notification_icon',
        // Keep the media notification present while playback is active. The
        // explicit Stop/X action is responsible for releasing the service.
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (_) {
    // A direct handler fallback cannot provide Android's media session or
    // foreground-service boundary, so never present it as background audio.
    if (Platform.isAndroid) rethrow;
    audioHandler = HybridAudioHandler();
  }

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await audioHandler.configureAudioSession(session);
  } catch (_) {
    // Audio session configuration is optional for showing the first frame.
    // Playback can configure itself later when the platform becomes ready.
  }

  final themeProvider = ThemeProvider();
  unawaited(AmbientColorFlowSettings.instance.load());
  final playlistManager = LocalPlaylistManager();
  runApp(
    HybridMusicApp(
      audioHandler: audioHandler,
      themeProvider: themeProvider,
      playlistManager: playlistManager,
    ),
  );
  // Preferences and local overlays are not required to paint the first frame.
  // Load them after the shell is visible; their ChangeNotifier updates will
  // refresh the relevant selectors when ready.
  unawaited(themeProvider.load().catchError((_) {}));
  unawaited(playlistManager.initialize().catchError((_) {}));
  schedulePlaybackRestoreAfterFirstFrame(audioHandler.restoreLastPlayback);
}

class HybridMusicApp extends StatelessWidget {
  const HybridMusicApp({
    required this.audioHandler,
    required this.themeProvider,
    required this.playlistManager,
    super.key,
  });

  final HybridAudioHandler audioHandler;
  final ThemeProvider themeProvider;
  final LocalPlaylistManager playlistManager;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocalPlaylistManager>.value(
          value: playlistManager,
        ),
        ChangeNotifierProvider<HybridMusicController>(
          create:
              (context) => HybridMusicController(
                library: MediaLibraryService(),
                audioHandler: audioHandler,
                playlistManager: context.read<LocalPlaylistManager>(),
              )..loadLibrary(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeState, _) {
          return MaterialApp(
            title: 'YAZEN',
            debugShowCheckedModeBanner: false,
            navigatorObservers: <NavigatorObserver>[appRouteObserver],
            theme: themeState.theme,
            builder:
                (context, child) => NowPlayingScope(
                  child: ThemeBackdrop(
                    child: Listener(
                      behavior: HitTestBehavior.deferToChild,
                      onPointerDown: DiagnosticsService.instance.pointerDown,
                      onPointerMove: DiagnosticsService.instance.pointerMove,
                      onPointerUp: DiagnosticsService.instance.pointerUp,
                      onPointerCancel: DiagnosticsService.instance.pointerCancel,
                      onPointerSignal: DiagnosticsService.instance.pointerSignal,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          final metrics = notification.metrics;
                          if (notification is ScrollStartNotification) {
                            ScrollPerformanceMode.noteScrollActivity();
                            DiagnosticsService.instance.scrollStarted(
                              axis: metrics.axis.name,
                              pixels: metrics.pixels,
                              depth: notification.depth,
                              sourceTimeStamp:
                                  notification.dragDetails?.sourceTimeStamp,
                            );
                          } else if (notification is ScrollUpdateNotification) {
                            DiagnosticsService.instance.scrollUpdated(
                              axis: metrics.axis.name,
                              depth: notification.depth,
                              delta: notification.scrollDelta,
                              pixels: metrics.pixels,
                              maxExtent: metrics.maxScrollExtent,
                              sourceTimeStamp:
                                  notification.dragDetails?.sourceTimeStamp,
                            );
                          } else if (notification is ScrollEndNotification) {
                            ScrollPerformanceMode.noteScrollEnd();
                            DiagnosticsService.instance.scrollEnded(
                              axis: metrics.axis.name,
                              depth: notification.depth,
                              pixels: metrics.pixels,
                              maxExtent: metrics.maxScrollExtent,
                            );
                          }
                          return false;
                        },
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
