#!/usr/bin/env python3
"""Generate the light/dark README banner pair from a single template.

    python3 scripts/generate-banner.py

Writes docs/assets/banner-light.svg and docs/assets/banner-dark.svg. The README serves the
pair through <picture>, so the two must always be regenerated together.
"""
import math
import os
import random

W, H = 1200, 420

THEMES = {
    "dark": dict(
        bg0="#0B0E14", bg1="#141A24",
        grid="#FFFFFF", grid_op=0.035,
        glow="#58A6FF", glow_op=0.16,
        strip="#161B22", strip_stroke="#2B323C", strip_shadow_op=0.45,
        fg="#E6EDF3", dim="#8B949E",
        chip="#1B222C", chip_stroke="#2B323C",
        green="#3FB950", blue="#58A6FF", amber="#D29922", pink="#F778BA",
        wordmark="#FFFFFF",
    ),
    "light": dict(
        bg0="#FFFFFF", bg1="#EEF2F6",
        grid="#0B0E14", grid_op=0.05,
        glow="#0969DA", glow_op=0.10,
        strip="#FFFFFF", strip_stroke="#D6DDE4", strip_shadow_op=0.10,
        fg="#1F2328", dim="#59636E",
        chip="#F4F7FA", chip_stroke="#D6DDE4",
        green="#1A7F37", blue="#0969DA", amber="#9A6700", pink="#BF3989",
        wordmark="#0B0E14",
    ),
}


def spark(x, y, w, h, seed, points=26):
    """A deterministic sparkline polyline, baseline-anchored."""
    rnd = random.Random(seed)
    vals, v = [], rnd.uniform(0.25, 0.6)
    for i in range(points):
        v += rnd.uniform(-0.22, 0.22) + 0.12 * math.sin(i / 2.6 + seed)
        v = min(0.96, max(0.06, v))
        vals.append(v)
    step = w / (points - 1)
    return " ".join(f"{x + i * step:.1f},{y + h - v * h:.1f}" for i, v in enumerate(vals))


def area(x, y, w, h, pts):
    return f"{x:.1f},{y + h:.1f} " + pts + f" {x + w:.1f},{y + h:.1f}"


def build(name, t):
    mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"
    sans = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, Helvetica, Arial, sans-serif"

    # Menu bar strip geometry
    sx, sy, sw, sh = 40, 56, 1120, 40
    o = []
    o.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
        f'role="img" aria-label="mectrics — a lightweight, private macOS system monitor in your menu bar">'
    )

    # ---- defs
    o.append("<defs>")
    o.append(
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1">'
        f'<stop offset="0" stop-color="{t["bg0"]}"/><stop offset="1" stop-color="{t["bg1"]}"/></linearGradient>'
    )
    o.append(
        f'<radialGradient id="glow" cx="0.5" cy="0.12" r="0.75">'
        f'<stop offset="0" stop-color="{t["glow"]}" stop-opacity="{t["glow_op"]}"/>'
        f'<stop offset="1" stop-color="{t["glow"]}" stop-opacity="0"/></radialGradient>'
    )
    o.append(
        '<pattern id="grid" width="24" height="24" patternUnits="userSpaceOnUse">'
        f'<path d="M24 0H0V24" fill="none" stroke="{t["grid"]}" stroke-opacity="{t["grid_op"]}" stroke-width="1"/>'
        "</pattern>"
    )
    for key, col in (("g", t["green"]), ("b", t["blue"]), ("a", t["amber"]), ("p", t["pink"])):
        o.append(
            f'<linearGradient id="fill-{key}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{col}" stop-opacity="0.55"/>'
            f'<stop offset="1" stop-color="{col}" stop-opacity="0.04"/></linearGradient>'
        )
    o.append(
        f'<filter id="shadow" x="-20%" y="-60%" width="140%" height="260%">'
        f'<feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000000" '
        f'flood-opacity="{t["strip_shadow_op"]}"/></filter>'
    )
    o.append("</defs>")

    # ---- background
    o.append(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>')
    o.append(f'<rect width="{W}" height="{H}" fill="url(#grid)"/>')
    o.append(f'<rect width="{W}" height="{H}" fill="url(#glow)"/>')

    # ---- menu bar strip
    o.append(
        f'<g filter="url(#shadow)"><rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="11" '
        f'fill="{t["strip"]}" stroke="{t["strip_stroke"]}"/></g>'
    )
    # traffic-light-ish left affordance:  (menu bar = app menu titles)
    o.append(
        f'<text x="{sx + 22}" y="{sy + 26}" font-family="{sans}" font-size="13" font-weight="600" '
        f'fill="{t["fg"]}" opacity="0.9">Mectrics</text>'
    )
    mx = sx + 92
    for label in ("File", "View", "Window", "Help"):
        o.append(
            f'<text x="{mx:.0f}" y="{sy + 26}" font-family="{sans}" font-size="13" '
            f'fill="{t["dim"]}">{label}</text>'
        )
        mx += len(label) * 7.4 + 22

    # ---- status items (right side, like the real menu bar)
    # Only CPU, Memory, and GPU carry a sparkline in the app — keep the banner honest.
    items = [
        ("CPU", "42%", t["green"], "g", 7),
        ("MEM", "61%", t["blue"], "b", 13),
        ("GPU", "18%", t["pink"], "p", 21),
    ]
    x = sx + 430
    for label, value, col, key, seed in items:
        o.append(
            f'<text x="{x}" y="{sy + 26}" font-family="{mono}" font-size="12" font-weight="600" '
            f'fill="{t["dim"]}" letter-spacing="0.4">{label}</text>'
        )
        vx = x + 34
        o.append(
            f'<text x="{vx + 40}" y="{sy + 26}" font-family="{mono}" font-size="13" font-weight="600" '
            f'fill="{t["fg"]}" text-anchor="end">{value}</text>'
        )
        px, py, pw, ph = vx + 48, sy + 9, 54, 22
        pts = spark(px, py, pw, ph, seed)
        o.append(f'<polygon points="{area(px, py, pw, ph, pts)}" fill="url(#fill-{key})"/>')
        o.append(
            f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="1.6" '
            'stroke-linejoin="round" stroke-linecap="round"/>'
        )
        x = px + pw + 22

    # battery + clock
    bx = x
    o.append(
        f'<rect x="{bx}" y="{sy + 13}" width="24" height="12" rx="3.5" fill="none" '
        f'stroke="{t["fg"]}" stroke-opacity="0.55"/>'
        f'<rect x="{bx + 2}" y="{sy + 15}" width="17" height="8" rx="2" fill="{t["green"]}"/>'
        f'<rect x="{bx + 25.5}" y="{sy + 16.5}" width="2.5" height="5" rx="1.2" fill="{t["fg"]}" fill-opacity="0.55"/>'
    )
    o.append(
        f'<text x="{bx + 36}" y="{sy + 26}" font-family="{mono}" font-size="13" font-weight="600" '
        f'fill="{t["fg"]}">87%</text>'
    )
    o.append(
        f'<text x="{sx + sw - 22}" y="{sy + 26}" font-family="{sans}" font-size="13" '
        f'fill="{t["dim"]}" text-anchor="end">Tue 09:41</text>'
    )

    # ---- wordmark
    o.append(
        f'<text x="{W/2}" y="228" font-family="{sans}" font-size="86" font-weight="700" '
        f'letter-spacing="-3" fill="{t["wordmark"]}" text-anchor="middle">mectrics</text>'
    )
    o.append(
        f'<text x="{W/2}" y="272" font-family="{sans}" font-size="20" fill="{t["dim"]}" '
        f'text-anchor="middle">A lightweight, private system monitor that lives in your macOS menu bar.</text>'
    )

    # ---- chips
    chips = ["CPU", "Memory", "Battery", "Network", "Disk", "GPU", "Temperature", "Fans", "Bluetooth"]
    pad, gap, cy, ch = 15, 9, 314, 32
    widths = [round(len(c) * 7.6) + pad * 2 for c in chips]
    total = sum(widths) + gap * (len(chips) - 1)
    cx = (W - total) / 2
    for c, cw in zip(chips, widths):
        o.append(
            f'<rect x="{cx:.1f}" y="{cy}" width="{cw}" height="{ch}" rx="{ch/2}" '
            f'fill="{t["chip"]}" stroke="{t["chip_stroke"]}"/>'
            f'<text x="{cx + cw/2:.1f}" y="{cy + 21}" font-family="{sans}" font-size="13" '
            f'font-weight="500" fill="{t["dim"]}" text-anchor="middle">{c}</text>'
        )
        cx += cw + gap

    # ---- footer line
    o.append(
        f'<text x="{W/2}" y="384" font-family="{mono}" font-size="12.5" fill="{t["dim"]}" '
        f'text-anchor="middle" opacity="0.85">'
        f'zero telemetry &#183; adaptive sampling &#183; fixed-width items &#183; MIT</text>'
    )

    o.append("</svg>")
    return "\n".join(o)


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO_ROOT, "docs", "assets")

for name, theme in THEMES.items():
    path = os.path.join(ASSETS, f"banner-{name}.svg")
    with open(path, "w") as f:
        f.write(build(name, theme) + "\n")
    print("wrote", os.path.relpath(path, REPO_ROOT))
