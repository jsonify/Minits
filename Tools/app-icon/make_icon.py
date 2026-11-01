#!/usr/bin/env python3
"""Draws the Minits app icon (the cassette) as SVG, in SK-1's light and dark palettes.

    python3 Tools/app-icon/make_icon.py      # writes Tools/app-icon/build/*.svg
    node Tools/app-icon/render.js            # renders them into Minits/Assets.xcassets/AppIcon.appiconset

Colours are SK1Kit's tokens (chassis, glow, orange key) and the cassette deck's own (UI/CassetteDeck.swift).
"""
import math
import os

LIGHT = dict(chassis="#EBE8E1", glow=0.55, shadow=0.22, rim=0.0)
DARK = dict(chassis="#2B2A27", glow=0.06, shadow=0.70, rim=0.10)


def defs(p):
    return f'''<defs>
 <radialGradient id="glow" cx="0.5" cy="0" r="0.9"><stop offset="0" stop-color="#fff" stop-opacity="{p['glow']}"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
 <linearGradient id="shell" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4A4843"/><stop offset="1" stop-color="#2A2826"/></linearGradient>
 <linearGradient id="orange" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF8045"/><stop offset="1" stop-color="#F2520F"/></linearGradient>
 <linearGradient id="tape" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4a3221"/><stop offset="0.5" stop-color="#6b4a32"/><stop offset="1" stop-color="#5a3c28"/></linearGradient>
 <clipPath id="window"><rect x="282" y="408" width="460" height="140" rx="70"/></clipPath>
 <filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="16" stdDeviation="16" flood-color="#000" flood-opacity="{p['shadow']}"/></filter>
</defs>'''


def reel(cx, cy, tape_r):
    s = [f'<circle cx="{cx}" cy="{cy}" r="{tape_r}" fill="url(#tape)"/>',
         f'<circle cx="{cx}" cy="{cy}" r="36" fill="#f3f0ea"/>',
         f'<circle cx="{cx}" cy="{cy}" r="20" fill="#1d1b19"/>']
    for k in range(6):
        s.append(f'<rect x="{cx - 5}" y="{cy - 22}" width="10" height="9" fill="#f3f0ea" transform="rotate({k * 60} {cx} {cy})"/>')
    return "".join(s)


def cassette(p):
    s = [f'<rect width="1024" height="1024" fill="{p["chassis"]}"/>', '<rect width="1024" height="1024" fill="url(#glow)"/>',
         '<g filter="url(#drop)"><rect x="112" y="252" width="800" height="520" rx="44" fill="url(#shell)"/></g>']
    if p["rim"]:
        s.append(f'<rect x="113.5" y="253.5" width="797" height="517" rx="43" fill="none" stroke="#fff" stroke-opacity="{p["rim"]}" stroke-width="3"/>')
    for sx, sy in [(150, 290), (874, 290), (150, 734), (874, 734)]:  # screws
        s.append(f'<circle cx="{sx}" cy="{sy}" r="13" fill="#8c8880"/><rect x="{sx - 9}" y="{sy - 2}" width="18" height="4" fill="#3a3833"/>')
    # Index label: handwritten title, SIDE A, orange band.
    s.append('<rect x="178" y="300" width="668" height="330" rx="18" fill="#f4efe2"/>')
    s.append('<path d="M178 560 H846 V612 a18 18 0 0 1 -18 18 H196 a18 18 0 0 1 -18 -18 Z" fill="url(#orange)"/>')
    s.append('<path d="M214 350 q14 -22 28 0 t28 0 t28 0 q10 -16 22 4 t24 -2 t30 0 q12 -18 26 0 t26 2" '
             'fill="none" stroke="#1f3a6b" stroke-width="7" stroke-linecap="round"/>')
    s.append('<path d="M590 352 q12 -16 24 0 t24 0 t24 0" fill="none" stroke="#1f3a6b" stroke-width="6" stroke-linecap="round" opacity="0.8"/>')
    s.append('<path d="M772 366 L797 320 L822 366 M781 350 H813" fill="none" stroke="#2b2a27" '
             'stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>')  # "A", drawn so no font is needed
    # Smoky window with the tape wound mostly onto the left reel.
    s.append('<rect x="282" y="408" width="460" height="140" rx="70" fill="#1d1b19"/>')
    s.append('<g clip-path="url(#window)">'
             '<rect x="380" y="440" width="270" height="76" fill="url(#tape)" opacity="0.85"/>'
             + reel(372, 478, 84) + reel(652, 478, 52) + '</g>')
    s.append('<rect x="282" y="408" width="460" height="40" rx="20" fill="#fff" opacity="0.06"/>')
    # Bottom ridge with its holes.
    s.append('<path d="M262 772 L312 676 L712 676 L762 772 Z" fill="#34322f"/>')
    for fx in (360, 664):
        s.append(f'<circle cx="{fx}" cy="726" r="18" fill="#151413"/>')
    for fx in (470, 554):
        s.append(f'<rect x="{fx - 12}" y="714" width="24" height="24" fill="#151413"/>')
    return "".join(s)


def ios_svg(p):
    """Full-bleed 1024 square: iOS rounds the corners itself."""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{defs(p)}{cassette(p)}</svg>'


def mac_svg(p):
    """macOS icon grid: an 824 rounded square centred on a 1024 canvas, with a soft shadow under it."""
    k = 824 / 1024
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{defs(p)}'
            '<defs><clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'
            '<filter id="macShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/></filter></defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{p["chassis"]}" filter="url(#macShadow)"/>'
            f'<g clip-path="url(#squircle)"><g transform="translate(100 100) scale({k})">{cassette(p)}</g></g></svg>')


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build")
    os.makedirs(out, exist_ok=True)
    for name, svg in (("ios-light", ios_svg(LIGHT)), ("ios-dark", ios_svg(DARK)), ("mac", mac_svg(LIGHT))):
        with open(os.path.join(out, f"{name}.svg"), "w") as f:
            f.write(svg)
    print("wrote", out)
