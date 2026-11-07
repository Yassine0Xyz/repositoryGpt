import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/dynamic_color_settings.dart';
import 'package:yazen/services/ambient_color_flow_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dynamic colors default on and persist opt-out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = DynamicColorSettings.instance;
    settings.resetForTesting();
    await settings.load();
    expect(settings.enabled, isTrue);
    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(DynamicColorSettings.preferenceKey), isFalse);
  });

  test('ambient color flow defaults on and persists opt-out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AmbientColorFlowSettings.instance;
    settings.resetForTesting();
    var notifications = 0;
    void listener() => notifications++;
    settings.addListener(listener);
    await settings.load();
    expect(settings.enabled, isTrue);
    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);
    expect(notifications, greaterThanOrEqualTo(2));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(AmbientColorFlowSettings.preferenceKey),
      isFalse,
    );
    settings.removeListener(listener);
  });

  test('ambient flow migrates the previous smoke opt-out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'yazen.settings.smoke_effect_enabled': false,
    });
    final settings = AmbientColorFlowSettings.instance;
    settings.resetForTesting();
    await settings.load();
    expect(settings.loaded, isTrue);
    expect(settings.enabled, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(AmbientColorFlowSettings.preferenceKey),
      isFalse,
    );
  });

  test('ambient flow setting change wins a concurrent settings load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AmbientColorFlowSettings.preferenceKey: true,
    });
    final settings = AmbientColorFlowSettings.instance;
    settings.resetForTesting();
    final loading = settings.load();
    final changing = settings.setEnabled(false);
    await Future.wait<void>(<Future<void>>[loading, changing]);
    expect(settings.enabled, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(AmbientColorFlowSettings.preferenceKey),
      isFalse,
    );
  });

  test(
    'ambient settings load failure keeps safe defaults and completes',
    () async {
      final settings = AmbientColorFlowSettings.instance;
      settings.resetForTesting();
      settings.setPreferencesLoaderForTesting(() async {
        throw StateError('simulated preferences failure');
      });

      await settings.load();

      expect(settings.loaded, isTrue);
      expect(settings.enabled, isTrue);
    },
  );
}
