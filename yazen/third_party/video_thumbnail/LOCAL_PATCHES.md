# Local compatibility patch

This directory vendors `video_thumbnail` version 0.5.6 from https://pub.dev/packages/video_thumbnail. The upstream license is retained in `LICENSE`.

The package is wired through the root `dependency_overrides` in `pubspec.yaml` so builds are reproducible. Local compatibility/performance patches are:

- Replace the removed `jcenter()` repository with Maven Central and compile against Android SDK 36, required by the current AndroidX AAR dependencies.
- Bound the Android thumbnail decoder executor to two threads rather than an unbounded cached pool. YAZEN also applies a Dart-side viewport gate; the native bound is a defensive ceiling for future callers.
- Always recycle the decoded thumbnail bitmap when JPEG/PNG/WebP encoding completes or fails, use try-with-resources for byte/file streams, and recycle the original frame after a scaled copy is created.
