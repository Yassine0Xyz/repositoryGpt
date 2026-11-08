#!/usr/bin/env python3
"""Verify the Profile APK artifact and the source configuration it embeds."""
from pathlib import Path
import os
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
APK = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/app/outputs/flutter-apk/app-profile.apk"


def compact(source: str) -> str:
    return "".join(source.split())


def check(label: str, passed: bool) -> None:
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
    if not passed:
        raise SystemExit(1)


service = (ROOT / "lib/diagnostics/core/diagnostics_service.dart").read_text(encoding="utf-8")
main = (ROOT / "lib/main.dart").read_text(encoding="utf-8")
workflow = (REPO / ".github/workflows/flutter-ci.yml").read_text(encoding="utf-8")
service_flat = compact(service)

check("CI requests an APK Profile build", "flutterbuildapk--profile" in compact(workflow))
check("session metadata records Flutter debugMode", "'debugMode':kDebugMode" in service_flat)
check("session metadata records Flutter profileMode", "'profileMode':kProfileMode" in service_flat)
check("session metadata records Flutter releaseMode", "'releaseMode':kReleaseMode" in service_flat)
check(
    "build-mode summary maps Profile separately from Debug and Release",
    "StringgetbuildMode=>kDebugMode?'debug':(kProfileMode?'profile':'release');" in service_flat,
)
check("Performance Intelligence starts with the application", "DiagnosticsService.instance.start();" in compact(main))
check(
    "JSON session export is serialized and named",
    "'yazen-pi-session-$stamp.json':jsonText" in service_flat
    and "JsonEncoder.withIndent('  ').convert(metadata)" in service_flat,
)
check(
    "JSONL journal is appended and exported as a separate file",
    "openWrite(mode:FileMode.append)" in service_flat
    and "'fileName':'yazen-pi-session-$stamp.jsonl'" in service_flat
    and "jsonEncode(event)" in service_flat,
)

flutter_root = os.environ.get("FLUTTER_ROOT")
if flutter_root:
    constants_file = Path(flutter_root) / "packages/flutter/lib/src/foundation/constants.dart"
    constants = constants_file.read_text(encoding="utf-8") if constants_file.is_file() else ""
    constants_flat = compact(constants)
    check("Flutter SDK Profile constant uses dart.vm.profile", "kProfileMode=bool.fromEnvironment('dart.vm.profile')" in constants_flat)
    check("Flutter SDK Debug constant excludes Profile and Release", "kDebugMode=!kReleaseMode&&!kProfileMode" in constants_flat)
    check("Flutter SDK Release constant uses dart.vm.product", "kReleaseMode=bool.fromEnvironment('dart.vm.product')" in constants_flat)
else:
    print("WARN: FLUTTER_ROOT is unset; Flutter SDK mode constants were not inspected.")

check("Profile APK exists", APK.is_file())
check("Profile APK is a readable ZIP/APK", zipfile.is_zipfile(APK))
if zipfile.is_zipfile(APK):
    with zipfile.ZipFile(APK) as apk:
        names = set(apk.namelist())
    check("APK contains AndroidManifest.xml", "AndroidManifest.xml" in names)
    check("APK contains the arm64 Flutter AOT library", "lib/arm64-v8a/libapp.so" in names)

print("Profile artifact and source configuration checks passed.")
