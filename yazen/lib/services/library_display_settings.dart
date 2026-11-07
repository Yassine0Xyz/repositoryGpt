import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LibraryLayoutMode { list, grid }

enum LibraryDensity { comfortable, compact }

class LibraryDisplaySettings extends ChangeNotifier {
  LibraryDisplaySettings._();

  static const String _layoutKey = 'yazen.library.layout';
  static const String _densityKey = 'yazen.library.density';
  static const String _videosLayoutKey = 'yazen.library.videos.layout';
  static const String _videosDensityKey = 'yazen.library.videos.density';

  static final LibraryDisplaySettings instance = LibraryDisplaySettings._();

  LibraryLayoutMode _layoutMode = LibraryLayoutMode.list;
  LibraryDensity _density = LibraryDensity.comfortable;
  LibraryLayoutMode _videosLayoutMode = LibraryLayoutMode.list;
  LibraryDensity _videosDensity = LibraryDensity.comfortable;
  Future<void>? _loadFuture;

  LibraryLayoutMode get layoutMode => _layoutMode;
  LibraryDensity get density => _density;
  LibraryLayoutMode get videosLayoutMode => _videosLayoutMode;
  LibraryDensity get videosDensity => _videosDensity;

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final layoutName = preferences.getString(_layoutKey);
    final densityName = preferences.getString(_densityKey);
    final videosLayoutName = preferences.getString(_videosLayoutKey);
    final videosDensityName = preferences.getString(_videosDensityKey);
    final layout = LibraryLayoutMode.values.firstWhere(
      (value) => value.name == layoutName,
      orElse: () => LibraryLayoutMode.list,
    );
    final density = LibraryDensity.values.firstWhere(
      (value) => value.name == densityName,
      orElse: () => LibraryDensity.comfortable,
    );
    final videosLayout = LibraryLayoutMode.values.firstWhere(
      (value) => value.name == videosLayoutName,
      orElse: () => LibraryLayoutMode.list,
    );
    final videosDensity = LibraryDensity.values.firstWhere(
      (value) => value.name == videosDensityName,
      orElse: () => LibraryDensity.comfortable,
    );
    if (layout == _layoutMode &&
        density == _density &&
        videosLayout == _videosLayoutMode &&
        videosDensity == _videosDensity) {
      return;
    }
    _layoutMode = layout;
    _density = density;
    _videosLayoutMode = videosLayout;
    _videosDensity = videosDensity;
    notifyListeners();
  }

  Future<void> setLayoutMode(LibraryLayoutMode value) async {
    if (_layoutMode == value) return;
    _layoutMode = value;
    notifyListeners();
    await _save(_layoutKey, value.name);
  }

  Future<void> setDensity(LibraryDensity value) async {
    if (_density == value) return;
    _density = value;
    notifyListeners();
    await _save(_densityKey, value.name);
  }

  Future<void> setVideosLayoutMode(LibraryLayoutMode value) async {
    if (_videosLayoutMode == value) return;
    _videosLayoutMode = value;
    notifyListeners();
    await _save(_videosLayoutKey, value.name);
  }

  Future<void> setVideosDensity(LibraryDensity value) async {
    if (_videosDensity == value) return;
    _videosDensity = value;
    notifyListeners();
    await _save(_videosDensityKey, value.name);
  }

  Future<void> _save(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(key, value);
    if (!saved) {
      throw StateError('Unable to save library display setting: $key');
    }
  }
}
