import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class EqualizerSettings {
  const EqualizerSettings({
    this.enabled = true,
    this.surroundEnabled = false,
    this.preset = 'Flat',
    this.bandGains = const <double>[],
  });

  final bool enabled;
  final bool surroundEnabled;
  final String preset;
  final List<double> bandGains;
}

/// Persists the local Android audio-effect state; no media or account data.
class EqualizerSettingsStore {
  static const enabledKey = 'yazen.settings.equalizer_enabled';
  static const surroundKey = 'yazen.settings.surround_enabled';
  static const stateKey = 'yazen.equalizer_state.v1';

  const EqualizerSettingsStore();

  Future<EqualizerSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(stateKey);
    if (raw == null || raw.isEmpty) {
      return EqualizerSettings(
        enabled: preferences.getBool(enabledKey) ?? true,
        surroundEnabled: preferences.getBool(surroundKey) ?? false,
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return EqualizerSettings(
          enabled: preferences.getBool(enabledKey) ?? true,
          surroundEnabled: preferences.getBool(surroundKey) ?? false,
        );
      }
      final rawGains = decoded['bandGains'];
      final gains =
          rawGains is List
              ? rawGains
                  .whereType<num>()
                  .map((gain) => gain.toDouble().clamp(-15.0, 15.0).toDouble())
                  .toList(growable: false)
              : const <double>[];
      return EqualizerSettings(
        enabled: decoded['enabled'] == true,
        surroundEnabled: decoded['surroundEnabled'] == true,
        preset:
            decoded['preset'] is String ? decoded['preset'] as String : 'Flat',
        bandGains: List<double>.unmodifiable(gains),
      );
    } on Object {
      return EqualizerSettings(
        enabled: preferences.getBool(enabledKey) ?? true,
        surroundEnabled: preferences.getBool(surroundKey) ?? false,
      );
    }
  }

  Future<void> save(EqualizerSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(enabledKey, settings.enabled);
    await preferences.setBool(surroundKey, settings.surroundEnabled);
    await preferences.setString(
      stateKey,
      jsonEncode(<String, Object>{
        'enabled': settings.enabled,
        'surroundEnabled': settings.surroundEnabled,
        'preset': settings.preset,
        'bandGains': settings.bandGains
            .map((gain) => gain.clamp(-15.0, 15.0).toDouble())
            .toList(growable: false),
      }),
    );
  }
}
