import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HapticSettings extends ChangeNotifier {
  HapticSettings._();

  static final HapticSettings instance = HapticSettings._();
  static const String preferenceKey = 'yazen.settings.haptic_feedback_enabled';

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

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _loaded = true;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, enabled);
  }
}
