import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VisualizerResponse { smooth, balanced, fast }

class VisualizerSettings extends ChangeNotifier {
  VisualizerSettings._();

  static final VisualizerSettings instance = VisualizerSettings._();

  static const _sensitivityKey = 'yazen.visualizer.sensitivity';
  static const _responseKey = 'yazen.visualizer.response';
  static const _noiseGateKey = 'yazen.visualizer.noise_gate';

  double _sensitivity = 1.0;
  VisualizerResponse _response = VisualizerResponse.balanced;
  double _noiseGate = 0.015;
  bool _loaded = false;

  double get sensitivity => _sensitivity;
  VisualizerResponse get response => _response;
  double get noiseGate => _noiseGate;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _sensitivity = (preferences.getDouble(_sensitivityKey) ?? 1.0).clamp(
      0.6,
      1.8,
    );
    final responseIndex = preferences.getInt(_responseKey) ?? 1;
    final safeResponseIndex =
        responseIndex.clamp(0, VisualizerResponse.values.length - 1).toInt();
    _response = VisualizerResponse.values[safeResponseIndex];
    _noiseGate = (preferences.getDouble(_noiseGateKey) ?? 0.015).clamp(
      0.0,
      0.08,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSensitivity(double value) async {
    _sensitivity = value.clamp(0.6, 1.8);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_sensitivityKey, _sensitivity);
  }

  Future<void> setResponse(VisualizerResponse value) async {
    _response = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_responseKey, value.index);
  }

  Future<void> setNoiseGate(double value) async {
    _noiseGate = value.clamp(0.0, 0.08);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_noiseGateKey, _noiseGate);
  }

  Duration get riseTime {
    switch (_response) {
      case VisualizerResponse.smooth:
        return const Duration(milliseconds: 75);
      case VisualizerResponse.balanced:
        return const Duration(milliseconds: 45);
      case VisualizerResponse.fast:
        return const Duration(milliseconds: 25);
    }
  }

  Duration get fallTime {
    switch (_response) {
      case VisualizerResponse.smooth:
        return const Duration(milliseconds: 150);
      case VisualizerResponse.balanced:
        return const Duration(milliseconds: 90);
      case VisualizerResponse.fast:
        return const Duration(milliseconds: 52);
    }
  }
}
