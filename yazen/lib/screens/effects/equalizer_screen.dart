import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../controllers/hybrid_music_controller.dart';
import '../../core/theme/theme_provider.dart';
import '../../services/hybrid_audio_handler.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const EqualizerScreen());
  }

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  static const _presets = <String, List<double>>{
    'Flat': <double>[0, 0, 0, 0, 0, 0, 0, 0],
    'Bass Boost': <double>[7, 6, 4, 2, 0, -1, -2, -2],
    'Pop': <double>[-1, 2, 4, 5, 3, 1, -1, -2],
    'Rock': <double>[5, 3, -1, -2, 2, 4, 5, 5],
    'Heavy Metal': <double>[5, 4, 2, -2, -2, 3, 5, 6],
    'Vocal': <double>[-3, -1, 2, 5, 6, 4, 1, -2],
  };

  String _selectedPreset = 'Flat';
  bool _enabled = false;
  bool _surroundEnabled = false;
  bool _settingsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    final handler = context.read<HybridMusicController>().audioHandler;
    unawaited(
      handler.equalizerSettingsReady.then((_) {
        if (!mounted) return;
        setState(() {
          _enabled = handler.equalizerEnabled;
          _surroundEnabled = handler.threeDSurroundEnabled;
          _selectedPreset = handler.equalizerPreset;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = context.read<HybridMusicController>().audioHandler;
    final tokens = context.watch<ThemeProvider>().tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Equalizer',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child:
            !handler.equalizerAvailable
                ? const _EffectUnavailable()
                : FutureBuilder<AndroidEqualizerParameters>(
                  future: handler.equalizer.parameters,
                  builder: (context, snapshot) {
                    final parameters = snapshot.data;
                    if (snapshot.hasError) {
                      return const _EffectUnavailable();
                    }
                    if (parameters == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return StreamBuilder<bool>(
                      stream: handler.equalizerEnabledStream,
                      initialData: handler.equalizerEnabled,
                      builder:
                          (context, enabledSnapshot) => ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            children: <Widget>[
                              _HeroHeader(
                                enabled: enabledSnapshot.data ?? _enabled,
                                onToggle: (value) async {
                                  setState(() => _enabled = value);
                                  final applied = await handler
                                      .setEqualizerEnabled(value);
                                  if (!applied && mounted) {
                                    _showEffectsSoftError();
                                  }
                                },
                              ),
                              const SizedBox(height: 18),
                              _PresetPicker(
                                value: _selectedPreset,
                                presets: _presets.keys.toList(growable: false),
                                onChanged: (value) async {
                                  if (value == null) return;
                                  setState(() => _selectedPreset = value);
                                  await handler.setEqualizerPreset(value);
                                  await _applyPreset(
                                    handler,
                                    parameters,
                                    _presets[value]!,
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              _EqualizerBands(
                                parameters: parameters,
                                enabled: enabledSnapshot.data ?? _enabled,
                                onGainChanged:
                                    (index, gain) => handler
                                        .setEqualizerBandGain(index, gain),
                              ),
                              const SizedBox(height: 18),
                              StreamBuilder<bool>(
                                stream: handler.threeDSurroundEnabledStream,
                                initialData: handler.threeDSurroundEnabled,
                                builder:
                                    (
                                      context,
                                      surroundSnapshot,
                                    ) => _SurroundCard(
                                      enabled:
                                          surroundSnapshot.data ??
                                          _surroundEnabled,
                                      onToggle: (value) async {
                                        setState(
                                          () => _surroundEnabled = value,
                                        );
                                        await handler.setThreeDSurroundEnabled(
                                          value,
                                        );
                                        if (handler.equalizerError != null &&
                                            mounted) {
                                          _showEffectsSoftError();
                                        }
                                      },
                                    ),
                              ),
                            ],
                          ),
                    );
                  },
                ),
      ),
    );
  }

  Future<void> _applyPreset(
    HybridAudioHandler handler,
    AndroidEqualizerParameters parameters,
    List<double> gains,
  ) async {
    for (var index = 0; index < parameters.bands.length; index++) {
      final gain = gains[index.clamp(0, gains.length - 1).toInt()].clamp(
        parameters.minDecibels,
        parameters.maxDecibels,
      );
      await handler.setEqualizerBandGain(index, gain.toDouble());
    }
  }

  void _showEffectsSoftError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Playback will continue without audio effects.'),
      ),
    );
  }
}

class _EffectUnavailable extends StatelessWidget {
  const _EffectUnavailable();

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.tune_rounded, size: 52, color: tokens.textSecondary),
            const SizedBox(height: 14),
            const Text(
              'Equalizer unavailable on this device',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Playback will continue without audio effects.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.enabled, required this.onToggle});

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.equalizer_rounded,
              color: tokens.accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Shape your sound',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  'Fine-tune every layer of your listening experience.',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onToggle,
            activeThumbColor: tokens.accent,
          ),
        ],
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.value,
    required this.presets,
    required this.onChanged,
  });

  final String value;
  final List<String> presets;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: tokens.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: context.read<ThemeProvider>().tokens.surfaceElevated,
          icon: const Icon(Icons.expand_more_rounded),
          onChanged: onChanged,
          items:
              presets
                  .map(
                    (preset) => DropdownMenuItem(
                      value: preset,
                      child: Text(
                        preset,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _EqualizerBands extends StatelessWidget {
  const _EqualizerBands({
    required this.parameters,
    required this.enabled,
    required this.onGainChanged,
  });

  final AndroidEqualizerParameters parameters;
  final bool enabled;
  final Future<bool> Function(int index, double gain) onGainChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      height: 320,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:
            parameters.bands.map((band) {
              return Expanded(
                child: _BandControl(
                  band: band,
                  parameters: parameters,
                  enabled: enabled,
                  onChanged:
                      (gain) =>
                          onGainChanged(parameters.bands.indexOf(band), gain),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _BandControl extends StatelessWidget {
  const _BandControl({
    required this.band,
    required this.parameters,
    required this.enabled,
    required this.onChanged,
  });

  final AndroidEqualizerBand band;
  final AndroidEqualizerParameters parameters;
  final bool enabled;
  final Future<bool> Function(double gain) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: context.read<ThemeProvider>().tokens.accent,
                inactiveTrackColor:
                    context.read<ThemeProvider>().tokens.surfaceMuted,
                thumbColor: context.read<ThemeProvider>().tokens.textPrimary,
              ),
              child: StreamBuilder<double>(
                stream: band.gainStream,
                initialData: band.gain,
                builder:
                    (context, snapshot) => Slider(
                      min: parameters.minDecibels,
                      max: parameters.maxDecibels,
                      value:
                          (snapshot.data ?? band.gain)
                              .clamp(
                                parameters.minDecibels,
                                parameters.maxDecibels,
                              )
                              .toDouble(),
                      onChanged: enabled ? (value) => onChanged(value) : null,
                    ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _formatFrequency(band.centerFrequency),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.read<ThemeProvider>().tokens.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _formatFrequency(double frequency) {
    if (frequency >= 1000) return '${(frequency / 1000).round()}k';
    return '${frequency.round()}';
  }
}

class _SurroundCard extends StatelessWidget {
  const _SurroundCard({required this.enabled, required this.onToggle});

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color:
              enabled ? tokens.accent.withValues(alpha: 0.45) : tokens.divider,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.spatial_audio_rounded, color: tokens.accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '3D Surround Audio',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wider, more immersive stereo field',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onToggle,
            activeThumbColor: tokens.accent,
          ),
        ],
      ),
    );
  }
}
