import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../models/media_track.dart';
import '../../core/theme/motion_tokens.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/theme/theme_provider.dart';
import '../../screens/effects/equalizer_screen.dart';
import '../../screens/library/local_media_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/queue/queue_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../services/library_display_settings.dart';
import '../../widgets/echo_motion.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../player/full_player_screen.dart';
import 'widgets/library_tabs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _libraryPageController;
  final ValueNotifier<bool> _showLibraryHeader = ValueNotifier<bool>(true);
  double _headerScrollAccumulator = 0;

  @override
  void initState() {
    super.initState();
    unawaited(LibraryDisplaySettings.instance.load());
    final initialTab = context.read<HybridMusicController>().selectedTab;
    _libraryPageController = PageController(
      initialPage: LibraryTab.values.indexOf(initialTab),
    );
  }

  @override
  void dispose() {
    _libraryPageController.dispose();
    _showLibraryHeader.dispose();
    super.dispose();
  }

  void _handleLibraryScrollDelta(double delta) {
    if (delta.abs() < 0.5) return;
    final isVisible = _showLibraryHeader.value;
    if ((isVisible && delta > 0) || (!isVisible && delta < 0)) {
      _headerScrollAccumulator += delta;
    } else {
      _headerScrollAccumulator = delta;
    }

    // Avoid rebuilding the home page for tiny direction changes caused by
    // touch jitter or scroll physics. Hide/show only after deliberate movement.
    if (isVisible && _headerScrollAccumulator >= 18) {
      _showLibraryHeader.value = false;
      _headerScrollAccumulator = 0;
    } else if (!isVisible && _headerScrollAccumulator <= -28) {
      _showLibraryHeader.value = true;
      _headerScrollAccumulator = 0;
    }
  }

  void _selectLibraryTab(LibraryTab tab) {
    final controller = context.read<HybridMusicController>();
    controller.selectTab(tab);
    if (!_libraryPageController.hasClients) return;
    final target = LibraryTab.values.indexOf(tab);
    if ((_libraryPageController.page ?? target) == target) return;
    _libraryPageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildLibraryPage(
    BuildContext context,
    LibraryTab selectedTab,
  ) => Column(
    children: <Widget>[
      ValueListenableBuilder<bool>(
        valueListenable: _showLibraryHeader,
        builder: (context, showHeader, _) {
          if (!showHeader) return const SizedBox.shrink();
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _buildHeader(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Your library',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                    ),
                    Text(
                      '${context.read<HybridMusicController>().visibleTracks.length} items',
                      style: TextStyle(
                        color:
                            context.read<ThemeProvider>().tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      LibraryTabs(selected: selectedTab, onSelected: _selectLibraryTab),
      const SizedBox(height: 4),
      Expanded(
        child: PageView.builder(
          controller: _libraryPageController,
          itemCount: LibraryTab.values.length,
          physics: const BouncingScrollPhysics(),
          onPageChanged:
              (index) => context.read<HybridMusicController>().selectTab(
                LibraryTab.values[index],
              ),
          itemBuilder: (context, index) {
            final tab = LibraryTab.values[index];
            // PageView already supplies the tab transition. Avoid rebuilding
            // full library pages every animation frame for an extra fade/drift.
            return LocalMediaScreen(
              selectedTab: tab,
              onTabSelected: _selectLibraryTab,
              showTabs: false,
              onScrollDelta: _handleLibraryScrollDelta,
            );
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final selectedTab = context.select<HybridMusicController, LibraryTab>(
      (controller) => controller.selectedTab,
    );
    return Scaffold(
      backgroundColor: context.watch<ThemeProvider>().tokens.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            _buildLibraryPage(context, selectedTab),
            const Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _MiniPlayerHost(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final stackedActions = constraints.maxWidth < 320;
        final logoSize = compact ? 40.0 : 48.0;
        final actions = <Widget>[
          _HeaderAction(
            icon: Icons.search_rounded,
            tooltip: 'Search local audio and video',
            onPressed: () => Navigator.of(context).push(SearchScreen.route()),
          ),
          _HeaderAction(
            icon: Icons.tune_rounded,
            tooltip: 'Filter and sort library',
            onPressed: () => _showLibrarySort(context),
          ),
          _HeaderAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh library',
            onPressed: controller.refreshLibrary,
          ),
          _HeaderAction(
            icon: Icons.palette_outlined,
            tooltip: 'Appearance',
            color: tokens.accent,
            onPressed: () => showThemePicker(context),
          ),
          _HeaderAction(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More options',
            onPressed: () => _showMoreOptions(context),
          ),
        ];
        final actionRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: actions,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/yazen_app_icon_master.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => Container(
                          width: logoSize,
                          height: logoSize,
                          color: tokens.accent,
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: tokens.isLight ? Colors.white : Colors.black,
                            size: compact ? 22 : 26,
                          ),
                        ),
                  ),
                ),
                SizedBox(width: compact ? ThemeSpacing.x2 : ThemeSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'YAZEN',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'LOCAL MEDIA',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.textSecondary.withValues(alpha: 0.72),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!stackedActions) actionRow,
              ],
            ),
            if (stackedActions) ...<Widget>[
              const SizedBox(height: ThemeSpacing.x1),
              Align(alignment: Alignment.centerRight, child: actionRow),
            ],
            const SizedBox(height: ThemeSpacing.x1),
          ],
        );
      },
    );
  }

  Future<void> _showMoreOptions(BuildContext context) async {
    final action = await showModalBottomSheet<_HeaderMoreAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final tokens = context.read<ThemeProvider>().tokens;
        return Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _MoreOption(
                    icon: Icons.equalizer_rounded,
                    title: 'Equalizer',
                    subtitle: 'Shape your listening experience',
                    onTap:
                        () => Navigator.pop(
                          sheetContext,
                          _HeaderMoreAction.equalizer,
                        ),
                  ),
                  _MoreOption(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Playback, library and appearance',
                    onTap:
                        () => Navigator.pop(
                          sheetContext,
                          _HeaderMoreAction.settings,
                        ),
                  ),
                  if (Platform.isLinux)
                    _MoreOption(
                      icon: Icons.folder_open_rounded,
                      title: 'Add local files',
                      subtitle: 'Import audio or video from this computer',
                      onTap:
                          () => Navigator.pop(
                            sheetContext,
                            _HeaderMoreAction.addFiles,
                          ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    final controller = context.read<HybridMusicController>();
    switch (action) {
      case _HeaderMoreAction.equalizer:
        await Navigator.of(context).push(EqualizerScreen.route());
      case _HeaderMoreAction.settings:
        await Navigator.of(context).push(SettingsScreen.route());
      case _HeaderMoreAction.addFiles:
        await controller.pickLocalFiles();
        if (!context.mounted || controller.errorMessage == null) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(controller.errorMessage!)));
    }
  }

  Future<void> _showLibrarySort(BuildContext context) async {
    final controller = context.read<HybridMusicController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final tokens = context.read<ThemeProvider>().tokens;
        final isVideos = controller.selectedTab == LibraryTab.videos;
        final availableSorts =
            isVideos
                ? <LibrarySort>[
                  LibrarySort.newestFirst,
                  LibrarySort.oldestFirst,
                  LibrarySort.sizeLowToHigh,
                  LibrarySort.sizeHighToLow,
                  LibrarySort.durationShortToLong,
                  LibrarySort.durationLongToShort,
                  LibrarySort.nameAZ,
                  LibrarySort.nameZA,
                ]
                : LibrarySort.values;
        final availableFilters =
            isVideos
                ? const <LibraryFilter>[LibraryFilter.all]
                : LibraryFilter.values;
        var selectedSort = controller.librarySort;
        final selectedFilters = Set<LibraryFilter>.of(
          controller.libraryFilters,
        );
        return StatefulBuilder(
          builder:
              (context, setModalState) => Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.86,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Expanded(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                          children: <Widget>[
                            Text(
                              'Sort and filter',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'SORT BY',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RadioGroup<LibrarySort>(
                              groupValue: selectedSort,
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(() => selectedSort = value);
                                }
                              },
                              child: Column(
                                children: availableSorts
                                    .map(
                                      (sort) => Material(
                                        color: Colors.transparent,
                                        child: RadioListTile<LibrarySort>(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          value: sort,
                                          title: Text(_sortLabel(sort)),
                                          activeColor: tokens.accent,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'FILTER',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: <Widget>[
                                for (final filter in availableFilters)
                                  FilterChip(
                                    label: Text(_filterLabel(filter)),
                                    selected:
                                        filter == LibraryFilter.all
                                            ? selectedFilters.isEmpty
                                            : selectedFilters.contains(filter),
                                    onSelected: (selected) {
                                      setModalState(() {
                                        if (filter == LibraryFilter.all) {
                                          selectedFilters.clear();
                                        } else if (selected) {
                                          selectedFilters.add(filter);
                                        } else {
                                          selectedFilters.remove(filter);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              controller
                                ..setLibrarySort(selectedSort)
                                ..setLibraryFilters(selectedFilters);
                              Navigator.of(context).pop();
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        );
      },
    );
  }

  String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.newestFirst => 'Newest first',
    LibrarySort.oldestFirst => 'Oldest first',
    LibrarySort.sizeLowToHigh => 'Size: low to high',
    LibrarySort.sizeHighToLow => 'Size: high to low',
    LibrarySort.durationShortToLong => 'Duration: shortest first',
    LibrarySort.durationLongToShort => 'Duration: longest first',
    LibrarySort.nameAZ => 'Name: A–Z',
    LibrarySort.nameZA => 'Name: Z–A',
    LibrarySort.artistAZ => 'Artist: A–Z',
    LibrarySort.mostPlayed => 'Most played',
    LibrarySort.recentlyPlayedFirst => 'Recently played',
  };

  String _filterLabel(LibraryFilter filter) => switch (filter) {
    LibraryFilter.all => 'All',
    LibraryFilter.favorites => 'Favorites',
    LibraryFilter.importedFiles => 'Imported files',
    LibraryFilter.missingAlbum => 'No album',
  };
}

enum _HeaderMoreAction { equalizer, settings, addFiles }

class _MoreOption extends StatelessWidget {
  const _MoreOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tokens.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: tokens.accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return EchoIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      color: color ?? tokens.textSecondary,
      selected: color != null,
      selectedColor: color ?? tokens.accent,
      backgroundColor: tokens.surface.withValues(alpha: 0.42),
      selectedBackgroundColor: (color ?? tokens.accent).withValues(alpha: 0.12),
      size: 40,
    );
  }
}

class _MiniPlayerHost extends StatefulWidget {
  const _MiniPlayerHost();

  @override
  State<_MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<_MiniPlayerHost> {
  @override
  Widget build(BuildContext context) {
    final controller = context.read<HybridMusicController>();
    final handler = controller.audioHandler;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        return AnimatedSwitcher(
          duration: MotionTokens.base,
          switchInCurve: MotionTokens.standard,
          switchOutCurve: MotionTokens.exit,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child:
              item == null
                  ? const SizedBox.shrink(key: ValueKey('mini-player-hidden'))
                  : StreamBuilder<PlaybackState>(
                    key: ValueKey<String>('mini-player-${item.id}'),
                    stream: handler.playbackState,
                    builder: (context, playbackSnapshot) {
                      return MiniPlayer(
                        item: item,
                        isPlaying: playbackSnapshot.data?.playing ?? false,
                        duration: item.duration,
                        positionStream: handler.player.positionStream,
                        onPlayPause: controller.togglePlayback,
                        onPrevious: handler.skipToPrevious,
                        onNext: handler.skipToNext,
                        onDismiss: () => unawaited(handler.stop()),
                        onRepeat: controller.toggleRepeat,
                        onQueue:
                            () =>
                                Navigator.of(context).push(QueueScreen.route()),
                        repeatMode:
                            playbackSnapshot.data?.repeatMode ??
                            controller.repeatMode,
                        onStop: handler.stop,
                        onTap:
                            () => Navigator.of(
                              context,
                            ).push(FullPlayerScreen.route()),
                      );
                    },
                  ),
        );
      },
    );
  }
}
