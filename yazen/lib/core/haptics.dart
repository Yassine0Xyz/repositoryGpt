import 'package:flutter/services.dart';

import '../services/haptic_settings.dart';

abstract final class Haptics {
  static Future<void> tap() => _perform(HapticFeedback.selectionClick);

  static Future<void> selection() => _perform(HapticFeedback.selectionClick);

  static Future<void> impact() => _perform(HapticFeedback.mediumImpact);

  static Future<void> success() => _perform(HapticFeedback.lightImpact);

  static Future<void> _perform(Future<void> Function() feedback) async {
    final settings = HapticSettings.instance;
    await settings.load();
    if (!settings.enabled) return;
    try {
      await feedback();
    } on MissingPluginException {
      // Haptics are optional; unsupported platforms remain fully functional.
    } on PlatformException {
      // A device may reject feedback; this must never interrupt app behavior.
    }
  }
}
