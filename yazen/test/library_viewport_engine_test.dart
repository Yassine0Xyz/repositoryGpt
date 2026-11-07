import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/library_viewport_engine.dart';

void main() {
  testWidgets('coalesces rapid thumb updates to the latest frame position', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 2400),
          ),
        ),
      ),
    );

    expect(controller.position.maxScrollExtent, greaterThan(0));
    final viewport = LibraryViewportEngine(scrollController: controller);
    viewport.queueThumbPosition(top: 10, travel: 100);
    viewport.queueThumbPosition(top: 75, travel: 100);
    viewport.queueThumbPosition(top: 82, travel: 100);
    await tester.pump();

    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent * 0.82, 1),
    );

    viewport.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('flush applies the latest pending position immediately', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 1800),
          ),
        ),
      ),
    );

    final viewport = LibraryViewportEngine(scrollController: controller);
    viewport.queueThumbPosition(top: 40, travel: 100);
    viewport.flushPendingJump();
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent * 0.4, 1),
    );

    viewport.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
