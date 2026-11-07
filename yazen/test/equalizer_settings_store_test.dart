import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/equalizer_settings_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('reads legacy enabled and surround preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      EqualizerSettingsStore.enabledKey: false,
      EqualizerSettingsStore.surroundKey: true,
    });

    const store = EqualizerSettingsStore();
    final settings = await store.load();

    expect(settings.enabled, isFalse);
    expect(settings.surroundEnabled, isTrue);
    expect(settings.bandGains, isEmpty);
    expect(settings.preset, 'Flat');
  });

  test(
    'falls back to legacy toggles when the versioned value is malformed',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        EqualizerSettingsStore.enabledKey: false,
        EqualizerSettingsStore.surroundKey: true,
        EqualizerSettingsStore.stateKey: 'not-an-object',
      });

      final settings = await const EqualizerSettingsStore().load();
      expect(settings.enabled, isFalse);
      expect(settings.surroundEnabled, isTrue);
    },
  );

  test('round-trips settings and clamps band gains', () async {
    const store = EqualizerSettingsStore();
    await store.save(
      const EqualizerSettings(
        enabled: true,
        surroundEnabled: true,
        preset: 'Rock',
        bandGains: <double>[-18, -2.5, 8, 19],
      ),
    );

    final settings = await store.load();
    expect(settings.enabled, isTrue);
    expect(settings.surroundEnabled, isTrue);
    expect(settings.preset, 'Rock');
    expect(settings.bandGains, <double>[-15, -2.5, 8, 15]);
  });
}
