import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Shared lazy list/grid renderer for high-volume local-library collections.
///
/// It centralizes lazy viewport construction while preserving each screen's
/// chosen child keep-alive policy, layout metrics, and visual design.
class LibraryTrackViewport extends StatelessWidget {
  const LibraryTrackViewport({
    required this.itemCount,
    required this.itemBuilder,
    required this.padding,
    this.gridDelegate,
    this.itemExtent,
    this.separatorBuilder,
    this.cacheExtent = 260,
    this.addAutomaticKeepAlives = true,
    this.semanticChildCount,
    super.key,
  }) : assert(itemCount >= 0),
       assert(gridDelegate == null || itemExtent == null),
       assert(gridDelegate == null || separatorBuilder == null);

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;
  final SliverGridDelegate? gridDelegate;
  final double? itemExtent;
  final IndexedWidgetBuilder? separatorBuilder;
  final double cacheExtent;
  final bool addAutomaticKeepAlives;
  final int? semanticChildCount;

  @override
  Widget build(BuildContext context) {
    final cache = ScrollCacheExtent.pixels(cacheExtent);
    final grid = gridDelegate;
    if (grid != null) {
      return GridView.builder(
        key: key,
        padding: padding,
        gridDelegate: grid,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        scrollCacheExtent: cache,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        addRepaintBoundaries: true,
        semanticChildCount: semanticChildCount ?? itemCount,
      );
    }

    final separator = separatorBuilder;
    if (separator != null) {
      return ListView.separated(
        key: key,
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        separatorBuilder: separator,
        scrollCacheExtent: cache,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        addRepaintBoundaries: true,
      );
    }

    return ListView.builder(
      key: key,
      padding: padding,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      itemExtent: itemExtent,
      scrollCacheExtent: cache,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: true,
      semanticChildCount: semanticChildCount ?? itemCount,
    );
  }
}
