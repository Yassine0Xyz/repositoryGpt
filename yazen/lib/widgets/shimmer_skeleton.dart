import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';

class ShimmerSkeleton extends StatefulWidget {
  const ShimmerSkeleton({
    required this.width,
    required this.height,
    this.radius = 18,
    super.key,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final start = -1.5 + (_controller.value * 3);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(start, 0),
              end: Alignment(start + 1, 0),
              colors: <Color>[
                tokens.surface,
                tokens.surfaceMuted,
                tokens.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

class LibraryLoadingState extends StatelessWidget {
  const LibraryLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder:
          (_, _) => const Row(
            children: <Widget>[
              ShimmerSkeleton(width: 56, height: 56, radius: 16),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ShimmerSkeleton(
                      width: double.infinity,
                      height: 14,
                      radius: 8,
                    ),
                    SizedBox(height: 9),
                    ShimmerSkeleton(width: 150, height: 11, radius: 7),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}
