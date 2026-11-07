import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DynamicColorSettings extends ChangeNotifier {
  DynamicColorSettings._();

  static final DynamicColorSettings instance = DynamicColorSettings._();
  static const String preferenceKey = 'yazen.settings.dynamic_colors_enabled';

  bool _enabled = true;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(preferenceKey) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, value);
  }

  @visibleForTesting
  void resetForTesting() {
    _enabled = true;
    _loaded = false;
    notifyListeners();
  }
}
