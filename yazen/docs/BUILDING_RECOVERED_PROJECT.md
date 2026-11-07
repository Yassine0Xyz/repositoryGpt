# Building the recovered project

## Prerequisites

The archived project notes record Flutter 3.47.5 stable with Dart 3.13.4. For closest reproduction, use those versions, Java 17+, Android SDK 36, the project’s Gradle 9.3.1 wrapper, Android Gradle Plugin 9.1.0, and Kotlin plugin 2.4.0. The Android project compiles Java/Kotlin bytecode to JVM 17 and sets `compileSdk` through Flutter’s configuration. Avoid upgrading Gradle/plugin versions while validating the recovery.


## Resolve and validate

From the project root:

```sh
flutter pub get
dart format lib
flutter analyze
flutter test
```


## Build a debug APK

```sh
flutter build apk --debug
```

The expected output is `build/app/outputs/flutter-apk/app-debug.apk`. Install it on an authorized Android device or emulator and check local library access and playback.

The recovery environment did not have Flutter, Dart, Kotlin compiler, or Android SDK tools, so none of these commands were run here. No APK was rebuilt as part of this recovery.
