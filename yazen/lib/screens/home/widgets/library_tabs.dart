import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/motion_tokens.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../widgets/echo_motion.dart';
import '../../../models/media_track.dart';

class LibraryTabs extends StatefulWidget {
  const LibraryTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LibraryTab selected;
  final ValueChanged<LibraryTab> onSelected;

  @override
  State<LibraryTabs> createState() => _LibraryTabsState();
}

class _LibraryTabsState extends State<LibraryTabs> {
  late final ScrollController _scrollController;
  late final List<GlobalKey> _tabKeys;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _tabKeys = List<GlobalKey>.generate(
      LibraryTab.values.length,
      (_) => GlobalKey(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(covariant LibraryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _revealSelected() {
    if (!mounted) return;
    final index = LibraryTab.values.indexOf(widget.selected);
    final tabContext = _tabKeys[index].currentContext;
    if (tabContext == null) return;
    Scrollable.ensureVisible(
      tabContext,
      alignment: 0.45,
      duration: Motion.of(context).fast,
      curve: MotionTokens.standard,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: ThemeSpacing.x5),
        scrollDirection: Axis.horizontal,
        itemCount: LibraryTab.values.length,
        separatorBuilder:
            (context, index) => const SizedBox(width: ThemeSpacing.x2),
        itemBuilder: (context, index) {
          final tab = LibraryTab.values[index];
          final isSelected = widget.selected == tab;
          final selectedForeground =
              tokens.isLight ? Colors.white : Colors.black;
          return EchoPressable(
            key: _tabKeys[index],
            onTap: () => widget.onSelected(tab),
            borderRadius: BorderRadius.circular(ThemeRadii.large),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: tab.label,
              child: AnimatedContainer(
                duration: MotionTokens.fast,
                curve: MotionTokens.standard,
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeSpacing.x3,
                  vertical: ThemeSpacing.x2,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? tokens.accent : tokens.surface,
                  borderRadius: BorderRadius.circular(ThemeRadii.large),
                  border: Border.all(
                    color:
                        isSelected
                            ? tokens.accent.withValues(alpha: 0.86)
                            : tokens.divider.withValues(alpha: 0.8),
                  ),
                  boxShadow:
                      isSelected
                          ? <BoxShadow>[
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : const <BoxShadow>[],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _iconFor(tab),
                      size: 16,
                      color:
                          isSelected
                              ? selectedForeground
                              : tokens.textSecondary,
                    ),
                    const SizedBox(width: ThemeSpacing.x2),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color:
                            isSelected
                                ? selectedForeground
                                : tokens.textSecondary,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(LibraryTab tab) {
    return switch (tab) {
      LibraryTab.videos => Icons.ondemand_video_rounded,
      LibraryTab.songs => Icons.music_note_rounded,
      LibraryTab.playlists => Icons.queue_music_rounded,
      LibraryTab.folders => Icons.folder_rounded,
      LibraryTab.artists => Icons.person_rounded,
      LibraryTab.albums => Icons.album_rounded,
      LibraryTab.hidden => Icons.visibility_off_rounded,
    };
  }
}
