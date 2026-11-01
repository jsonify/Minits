#!/usr/bin/env python3
"""Draws the Minits app icon (the recording LCD) as SVG, in SK-1's light and dark palettes.

    python3 Tools/app-icon/make_icon.py      # writes Tools/app-icon/build/*.svg
    node Tools/app-icon/render.js            # renders them into Minits/Assets.xcassets/AppIcon.appiconset

The icon is the recording screen in miniature: olive LCD glass in its bezel with a red REC lamp and the input level
as a waveform, over a row of three keys with the orange one in the middle. Colours are SK1Kit's tokens (DESIGN.md).
"""
import math
import os
import random

LIGHT = dict(chassis="#EBE8E1", glow=0.55, bezelTop="#D2CEC4", bezelBottom="#E2DED6", wellShadow=0.16, lcd=1.0,
             keyTop="#FDFCFA", keyBottom="#E8E4DC", keySkirt="#C7C2B7", keyHighlight=0.9, keyShadow=0.14)
DARK = dict(chassis="#2B2A27", glow=0.06, bezelTop="#1D1C1A", bezelBottom="#26251F", wellShadow=0.5, lcd=0.86,
            keyTop="#4A4843", keyBottom="#36342F", keySkirt="#1A1917", keyHighlight=0.12, keyShadow=0.45)
LCD_INK = "#1E2318"


def dim(hex_colour, brightness):
    """SK-1's lcdBrightness: scales the LCD glass toward black in Dark Mode."""
    h = hex_colour.lstrip("#")
    return "#" + "".join("%02X" % round(int(h[i:i + 2], 16) * brightness) for i in (0, 2, 4))


def defs(p):
    b = p["lcd"]
    return f'''<defs>
 <radialGradient id="glow" cx="0.5" cy="0" r="0.9"><stop offset="0" stop-color="#fff" stop-opacity="{p['glow']}"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
 <linearGradient id="bezel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{p['bezelTop']}"/><stop offset="1" stop-color="{p['bezelBottom']}"/></linearGradient>
 <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{dim('#D3D9BE', b)}"/><stop offset="0.5" stop-color="{dim('#C3CAAD', b)}"/><stop offset="1" stop-color="{dim('#B9C0A2', b)}"/></linearGradient>
 <linearGradient id="key" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{p['keyTop']}"/><stop offset="1" stop-color="{p['keyBottom']}"/></linearGradient>
 <linearGradient id="orange" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF8045"/><stop offset="1" stop-color="#F2520F"/></linearGradient>
 <radialGradient id="recGlow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#E0402F" stop-opacity="0.55"/><stop offset="1" stop-color="#E0402F" stop-opacity="0"/></radialGradient>
 <radialGradient id="recLamp" cx="0.4" cy="0.35" r="0.7"><stop offset="0" stop-color="#FF8A78"/><stop offset="0.55" stop-color="#E0402F"/><stop offset="1" stop-color="#B02A1C"/></radialGradient>
 <filter id="inner" x="-10%" y="-10%" width="120%" height="120%">
   <feOffset dy="10"/><feGaussianBlur stdDeviation="12" result="o"/>
   <feComposite in="SourceAlpha" in2="o" operator="out" result="inv"/>
   <feFlood flood-color="#000" flood-opacity="{p['wellShadow'] * 1.6}"/><feComposite in2="inv" operator="in"/>
   <feComposite in2="SourceAlpha" operator="in" result="sh"/>
   <feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="sh"/></feMerge></filter>
 <filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-color="#000" flood-opacity="{p['keyShadow'] * 1.6}"/></filter>
</defs>'''


def key(p, x, y, w, h, r, orange=False, skirt=16):
    """A raised SK-1 keycap on its skirt."""
    face, skirt_colour = ("url(#orange)", "#B93A07") if orange else ("url(#key)", p["keySkirt"])
    highlight, alpha = ("#FFB089", 0.8) if orange else ("#fff", p["keyHighlight"])
    return (f'<g filter="url(#drop)"><rect x="{x}" y="{y}" width="{w}" height="{h + skirt}" rx="{r}" fill="{skirt_colour}"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{face}"/>'
            f'<rect x="{x + 2}" y="{y + 2}" width="{w - 4}" height="{h - 4}" rx="{r - 2}" fill="none" stroke="{highlight}" '
            f'stroke-opacity="{alpha}" stroke-width="3"/></g>')


def lcd(p):
    s = [f'<rect width="1024" height="1024" fill="{p["chassis"]}"/>', '<rect width="1024" height="1024" fill="url(#glow)"/>',
         # Bezel (sunken) and glass.
         '<rect x="132" y="190" width="760" height="520" rx="64" fill="url(#bezel)" filter="url(#inner)"/>',
         '<rect x="166" y="224" width="692" height="452" rx="40" fill="url(#glass)"/>',
         '<rect x="166" y="224" width="692" height="120" rx="40" fill="#fff" opacity="0.10"/>',
         # REC lamp, the meeting's kind (lit) and its count (faint), as LCD bars.
         '<circle cx="250" cy="300" r="78" fill="url(#recGlow)"/>',
         '<circle cx="250" cy="300" r="30" fill="url(#recLamp)"/><circle cx="241" cy="289.5" r="8.4" fill="#fff" opacity="0.7"/>',
         f'<rect x="306" y="284" width="150" height="32" rx="6" fill="{LCD_INK}" opacity="0.85"/>',
         f'<rect x="680" y="284" width="110" height="32" rx="6" fill="{LCD_INK}" opacity="0.35"/>']
    # Input level: a waveform, lit up to "now", faint after it like unlit LCD segments.
    rng = random.Random(7)
    bars, x0, step = 26, 214, 600 / 26
    for i in range(bars):
        t = i / (bars - 1)
        envelope = 0.25 + 0.75 * abs(math.sin(t * math.pi * 2.2 + 0.4)) * (0.6 + 0.4 * math.sin(t * 9))
        h = max(18, 230 * abs(envelope) * (0.55 + 0.45 * rng.random()))
        s.append(f'<rect x="{x0 + i * step + step * 0.2:.1f}" y="{510 - h / 2:.1f}" width="{step * 0.62:.1f}" height="{h:.1f}" '
                 f'rx="6" fill="{LCD_INK}" opacity="{0.9 if i < 17 else 0.22}"/>')
    # Pause, Mark (orange) and End keys.
    s += [key(p, 132, 780, 230, 100, 30), key(p, 397, 780, 230, 100, 30, orange=True), key(p, 662, 780, 230, 100, 30)]
    return "".join(s)


def ios_svg(p):
    """Full-bleed 1024 square: iOS rounds the corners itself."""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{defs(p)}{lcd(p)}</svg>'


def mac_svg(p):
    """macOS icon grid: an 824 rounded square centred on a 1024 canvas, with a soft shadow under it."""
    k = 824 / 1024
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{defs(p)}'
            '<defs><clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'
            '<filter id="macShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/></filter></defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{p["chassis"]}" filter="url(#macShadow)"/>'
            f'<g clip-path="url(#squircle)"><g transform="translate(100 100) scale({k})">{lcd(p)}</g></g></svg>')


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build")
    os.makedirs(out, exist_ok=True)
    for name, svg in (("ios-light", ios_svg(LIGHT)), ("ios-dark", ios_svg(DARK)), ("mac", mac_svg(LIGHT))):
        with open(os.path.join(out, f"{name}.svg"), "w") as f:
            f.write(svg)
    print("wrote", out)
