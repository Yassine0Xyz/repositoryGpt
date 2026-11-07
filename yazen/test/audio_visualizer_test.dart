import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yazen/widgets/audio_visualizer.dart';

void main() {
  testWidgets('source painter repaints when a real frame changes', (
    tester,
  ) async {
    final repaint = ValueNotifier<int>(0);
    final levels = List<double>.filled(16, 0.04);
    final peaks = List<double>.filled(16, 0.04);
    final painter = _CountingSpectrumPainter(
      repaint: repaint,
      color: Colors.cyan,
      barCount: 16,
      height: 60,
      profile: AudioVisualizerProfile.compact,
      levels: levels,
      peaks: peaks,
      hasSignal: true,
      progress: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CustomPaint(size: const Size(320, 60), painter: painter),
          ),
        ),
      ),
    );
    final initialPaintCount = painter.paintCount;
    expect(initialPaintCount, greaterThan(0));

    levels[0] = 1;
    peaks[0] = 1;
    repaint.value++;
    await tester.pump();
    expect(painter.paintCount, greaterThan(initialPaintCount));

    await tester.pumpWidget(const SizedBox.shrink());
    repaint.dispose();
  });

  testWidgets('live position notifier repaints the progress line', (
    tester,
  ) async {
    final repaint = ValueNotifier<int>(0);
    final progress = ValueNotifier<double?>(0.1);
    final painter = _CountingSpectrumPainter(
      repaint: Listenable.merge(<Listenable>[repaint, progress]),
      color: Colors.cyan,
      barCount: 16,
      height: 60,
      profile: AudioVisualizerProfile.full,
      levels: List<double>.filled(16, 0),
      peaks: List<double>.filled(16, 0),
      hasSignal: false,
      progress: null,
      progressListenable: progress,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CustomPaint(size: const Size(320, 60), painter: painter),
          ),
        ),
      ),
    );
    final firstPaint = painter.paintCount;
    progress.value = 0.2;
    await tester.pump();
    expect(painter.paintCount, greaterThan(firstPaint));
    await tester.pumpWidget(const SizedBox.shrink());
    repaint.dispose();
    progress.dispose();
  });

  testWidgets('unknown duration remains valid for the visualizer widget', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AudioVisualizer(playing: false, duration: null, height: 60),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Audio spectrum, waiting for real PCM signal',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _CountingSpectrumPainter extends SourceSpectrumPainter {
  _CountingSpectrumPainter({
    required super.repaint,
    required super.color,
    required super.barCount,
    required super.height,
    required super.profile,
    required super.levels,
    required super.peaks,
    required super.hasSignal,
    required super.progress,
    super.progressListenable,
  });

  int paintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paintCount++;
    super.paint(canvas, size);
  }
}
