import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AmbientColorFlowSettings extends ChangeNotifier {
  AmbientColorFlowSettings._();

  static final AmbientColorFlowSettings instance = AmbientColorFlowSettings._();
  static const String preferenceKey =
      'yazen.settings.ambient_color_flow_enabled';
  static const String _legacyPreferenceKey =
      'yazen.settings.smoke_effect_enabled';
  static const String title = 'Ambient Color Flow';
  static const String subtitle =
      'A soft, blurred tint from the album artwork behind the full player';

  bool _enabled = true;
  bool _loaded = false;
  Future<SharedPreferences> Function() _preferencesLoader =
      SharedPreferences.getInstance;
  int _enabledVersion = 0;
  Future<void>? _loading;
  Future<void> _writeTail = Future<void>.value();

  bool get enabled => _enabled;
  bool get loaded => _loaded;

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final versionAtStart = _enabledVersion;
    try {
      final preferences = await _preferencesLoader();
      if (versionAtStart == _enabledVersion) {
        _enabled =
            preferences.getBool(preferenceKey) ??
            preferences.getBool(_legacyPreferenceKey) ??
            true;
      }
      _loaded = true;
      notifyListeners();
      if (!preferences.containsKey(preferenceKey) &&
          preferences.containsKey(_legacyPreferenceKey)) {
        await preferences.setBool(preferenceKey, _enabled);
      }
    } catch (error, stackTrace) {
      _loaded = true;
      notifyListeners();
      debugPrint(
        'Unable to load Ambient Color Flow settings; using defaults: '
        '$error\n$stackTrace',
      );
    } finally {
      _loading = null;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value && _loaded) return;
    _enabled = value;
    _enabledVersion++;
    notifyListeners();
    final write = _writeTail.then<void>((_) async {
      final preferences = await _preferencesLoader();
      final saved = await preferences.setBool(preferenceKey, value);
      if (!saved) {
        throw StateError('Failed to persist Ambient Color Flow setting.');
      }
    });
    _writeTail = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'Unable to persist Ambient Color Flow setting: '
          '$error\n$stackTrace',
        );
      },
    );
    await write;
  }

  @visibleForTesting
  void resetForTesting() {
    _enabled = true;
    _loaded = false;
    _enabledVersion = 0;
    _loading = null;
    _writeTail = Future<void>.value();
    _preferencesLoader = SharedPreferences.getInstance;
    notifyListeners();
  }

  @visibleForTesting
  void setPreferencesLoaderForTesting(
    Future<SharedPreferences> Function() loader,
  ) {
    _preferencesLoader = loader;
  }
}
