from pathlib import Path

root = Path(__file__).resolve().parents[1]
theme = (root / "lib/core/theme/theme_provider.dart").read_text()
checks = {
    "custom background blur is driven by scroll state": "valueListenable: ScrollPerformanceMode.isScrolling" in theme,
    "blur is skipped during active scrolling": "if (scrolling) return image;" in theme,
    "idle blur is reduced from the previous sigma 18": "sigmaX: 10, sigmaY: 10" in theme,
    "background image uses low filter quality": "filterQuality: FilterQuality.low" in theme,
    "background remains isolated by repaint boundary": "child: RepaintBoundary(" in theme,
}
for label, passed in checks.items():
    print(("PASS " if passed else "FAIL ") + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f"{len(checks)}/{len(checks)} V6 UI performance guardrails passed.")
