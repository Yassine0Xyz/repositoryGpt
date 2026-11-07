import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/services/haptic_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('haptic setting defaults on and persists an opt-out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = HapticSettings.instance;

    await settings.load();
    expect(settings.enabled, isTrue);

    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(HapticSettings.preferenceKey), isFalse);
  });
}
