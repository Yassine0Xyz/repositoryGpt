#!/usr/bin/env python3
"""Static guardrails for Library Architecture Evolution V1."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TILE = (ROOT / "lib/screens/home/widgets/track_list_tile.dart").read_text()
SCREEN = (ROOT / "lib/screens/library/local_media_screen.dart").read_text()
VIEWPORT = (ROOT / "lib/widgets/library_track_viewport.dart").read_text()
GRID_MENU = (ROOT / "lib/widgets/track_actions_menu.dart").read_text()

checks = {
    "shared row action menu exists": "class TrackActionsMenu" in GRID_MENU,
    "favorite action preserved": "_TrackRowAction.favorite" in GRID_MENU and "onFavorite?.call()" in GRID_MENU,
    "playlist action preserved": "_TrackRowAction.addToPlaylist" in GRID_MENU and "onAddToPlaylist?.call()" in GRID_MENU,
    "shared action menu used in list and grid": "TrackActionsMenu(" in TILE and "TrackActionsMenu(" in SCREEN,
    "grid tile has no per-item LayoutBuilder": "class _TrackGridTile" in SCREEN and "return LayoutBuilder(" not in SCREEN[SCREEN.index("class _TrackGridTile"):SCREEN.index("class _SelectionToolbar")],
    "grid cell geometry computed at viewport level": "final gridArtworkSize = gridCellWidth - 16" in SCREEN,
    "duplicate list/grid play buttons removed": "tooltip: 'Play ${track.title}'" not in TILE and "tooltip: 'Play ${track.title}'" not in SCREEN,
    "repeated source badge removed": "class _SourceBadge" not in TILE and "'LOCAL'" not in TILE,
    "artist text has no one-child row wrapper": "Row(\n                        children: <Widget>[\n                          Expanded(\n                            child: Text(\n                              track.artist" not in TILE,
    "tab cross-fade removed": "AnimatedSwitcher(\n                duration: MotionTokens.base" not in SCREEN,
    "keyed tab subtree retained": "key: ValueKey<LibraryTab>(selectedTab)" in SCREEN,
    "lazy list builder retained": "return ListView.builder(" in VIEWPORT,
    "lazy grid builder retained": "return GridView.builder(" in VIEWPORT,
    "fixed row extent support retained": "itemExtent: itemExtent" in VIEWPORT,
    "existing cache policy retained": "this.cacheExtent = 260" in VIEWPORT,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"{len(checks) - len(failed)}/{len(checks)} checks passed")
if failed:
    raise SystemExit(1)
