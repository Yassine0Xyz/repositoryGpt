import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';

Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final tokens = theme.tokens;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: tokens.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.divider,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Appearance',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Set the atmosphere for your listening space.',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ...EchoThemePreset.values.map(
                  (preset) => _ThemeOption(
                    preset: preset,
                    selected: theme.preset == preset,
                    onTap: () {
                      theme.setPreset(preset);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () {
                    theme.clearCustomBackground();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(
                    Icons.image_not_supported_outlined,
                    size: 18,
                  ),
                  label: const Text('Clear custom backdrop'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final EchoThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.fromPreset(preset);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: <Color>[tokens.accentStrong, tokens.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(
          preset == EchoThemePreset.rgbRainbow
              ? Icons.auto_awesome_rounded
              : Icons.palette_outlined,
          color: tokens.isLight ? Colors.white : Colors.black,
          size: 21,
        ),
      ),
      title: Text(
        preset.label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        preset.id,
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.55),
          fontSize: 11,
        ),
      ),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child:
            selected
                ? Icon(
                  Icons.check_circle_rounded,
                  key: const ValueKey('selected'),
                  color: tokens.accent,
                )
                : const SizedBox(key: ValueKey('unselected'), width: 24),
      ),
    );
  }
}
