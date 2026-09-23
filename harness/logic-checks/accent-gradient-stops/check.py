#!/usr/bin/env python3
"""Logic check: per-scheme pill-gradient stops (v2 look, phase 1).

Extract-don't-copy from the REAL Theme.swift (it imports UIKit, so it cannot be
compiled by a macOS swiftc harness). Asserts, for every AccentScheme case:
  - a `gradientStops` (light, dark) pair exists;
  - luminance order light > base > dark (a tint running into a shade, never a
    hue shift — the palette stays untouched);
  - the near-black label (#0B0B0C) clears WCAG AA 4.5:1 on the DARK stop, the
    pill's lowest-contrast region;
  - ice's `glowOpacity` is strictly lower than every other scheme's (near-white
    accent → its glow must stay subtle);
  - `primaryGradient` runs light → dark at 135° (topLeading → bottomTrailing).
Prints PASS/FAIL lines; exits 1 on any failure.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
THEME = ROOT / "LockIn Set Tracker" / "Theme.swift"

failures = 0


def check(name, condition):
    global failures
    print(f"  {'PASS' if condition else 'FAIL'}  {name}")
    if not condition:
        failures += 1


def section(text, start, ends):
    i = text.index(start)
    j = min((text.index(e, i) for e in ends if e in text[i:]), default=len(text))
    return text[i:j]


def srgb_to_linear(v):
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


src = THEME.read_text()
COLOR = r"Color\(red: ([0-9.]+), green: ([0-9.]+), blue: ([0-9.]+)\)"

enum_block = section(src, "enum AccentScheme", ["var id"])
cases = re.findall(r"^\s+case (\w+)\s*$", enum_block, re.M)

base_block = section(src, "var color: Color", ["var gradientStops"])
base = {m[0]: tuple(map(float, m[1:])) for m in re.findall(r"case \.(\w+): return " + COLOR, base_block)}

stops_block = section(src, "var gradientStops", ["var glowOpacity"])
stops = {
    m[0]: (tuple(map(float, m[1:4])), tuple(map(float, m[4:7])))
    for m in re.findall(r"case \.(\w+): return \(" + COLOR + r", " + COLOR + r"\)", stops_block)
}

glow_block = section(src, "var glowOpacity", ["static let storageKey"])
glow = {}
for names, value in re.findall(r"case ((?:\.\w+(?:, )?)+): return ([0-9.]+)", glow_block):
    for name in re.findall(r"\.(\w+)", names):
        glow[name] = float(value)

print("Accent gradient stops (extracted from Theme.swift):")
check("AccentScheme has cases", len(cases) >= 1)
check("every scheme has a base color", set(cases) == set(base))
check("every scheme has a gradientStops pair", set(cases) == set(stops))
check("every scheme has a glowOpacity", set(cases) == set(glow))

LABEL = (0.043, 0.043, 0.047)  # AppTheme.backgroundTop, the label on accent fills
for name in cases:
    if name not in base or name not in stops:
        continue
    light, dark = stops[name]
    check(f"{name}: light > base > dark luminance",
          luminance(light) > luminance(base[name]) > luminance(dark))
    check(f"{name}: near-black label >= 4.5:1 on the dark stop",
          contrast(dark, LABEL) >= 4.5)

if "ice" in glow:
    others = [v for k, v in glow.items() if k != "ice"]
    check("ice glow is subtler than every other scheme", bool(others) and glow["ice"] < min(others))
    check("ice glow is faint (<= 0.25 alpha)", glow["ice"] <= 0.25)

gradient_block = section(src, "static var primaryGradient", ["struct Glow"])
check("primaryGradient runs light -> dark",
      re.search(r"colors: \[stops\.light, stops\.dark\]", gradient_block) is not None)
check("primaryGradient is 135° (topLeading -> bottomTrailing)",
      "startPoint: .topLeading" in gradient_block and "endPoint: .bottomTrailing" in gradient_block)

if failures:
    print(f"  FAIL  accent-gradient-stops: {failures} assertion(s) failed")
    sys.exit(1)
print("  PASS  accent-gradient-stops (all assertions)")
