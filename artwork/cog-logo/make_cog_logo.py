"""rust_wasm logo: an orange gear whose single spoke reaches into the WebAssembly tag square.

Copyright (c) 2026 AlexMitchellMus. All rights reserved.
This script and the artwork it generates belong to the rust_wasm project and are
not covered by the repository's MIT or Apache-2.0 licence. See ARTWORK.md for
the design, permitted use and attribution (the tag square follows the
WebAssembly logo by Carlos Baraza).

The mark is built as real 3D geometry and
projected to clean SVG:
- 2D outlines (gear ring with teeth and four claws; a puzzle piece with four
  claw slots), sharp corners softened,
- extruded to a slab, rotated and viewed in perspective,
- every side wall culled if it faces away, sorted back to front and lit by its
  own normal; top faces get a gradient, a sheen and a light bevel rim.

Writes, next to this script:
  logo-colour.svg            full colour, transparent background
  logo-colour-dark.svg       full colour on a dark rounded square with a glow
  logo-silhouette-black.svg  two-tone black: top faces solid, walls at 40 %
  logo-silhouette-white.svg  the same in white, for dark backgrounds

Run: python3 make_cog_logo.py
"""

import math
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ---- 2D geometry (unit gear radius) ----------------------------------------
TEETH = 10
R_TIP = 1.00
R_ROOT = 0.85
TOOTH_TIP = 0.44      # tooth width at the tip, share of the pitch
TOOTH_ROOT = 0.60     # tooth width at the root, share of the pitch
R_HOLE = 0.69
PIECE_HALF = 0.39     # half size of the wasm square
PIECE_CORNER = 0.025  # the wasm mark's corners are nearly sharp
TAG_R = 0.14          # radius of the semicircle tag cut into the square's top edge
GAP = 0.035           # clearance between the spoke and the tag
SPOKE_HALF = TAG_R - GAP   # half width of the gear's single spoke
SPOKE_DIR = -math.pi / 2   # the spoke and the tag point this way (the square's top edge)
SOFTEN = 0.02         # corner rounding for sharp corners

# ---- 3D view -----------------------------------------------------------------
DEPTH = 0.26          # slab thickness
YAW = -30.0           # degrees: turn the slab
PITCH = 30.0          # degrees: tip the top towards the viewer
ROLL = -12.0          # degrees: lean on the page
CAMERA = 4.0          # camera distance (perspective strength)
LIGHT = (-0.45, -0.75, 0.55)   # towards the light, view space (x right, y down, z to viewer)

SIZE = 512
SCALE = 180.0
CENTRE = (SIZE / 2 - 24, SIZE / 2 - 2)


# ---- 2D helpers --------------------------------------------------------------
def arc(cx, cy, r, a0, a1, steps):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / steps),
             cy + r * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]


def dedupe(pts):
    out = []
    for p in pts:
        if not out or math.dist(p, out[-1]) > 1e-6:
            out.append(p)
    while len(out) > 1 and math.dist(out[0], out[-1]) < 1e-6:
        out.pop()
    return out


def soften(pts, r=SOFTEN, sharp_deg=25.0):
    """Round each sharp corner with a short quadratic curve of reach about r."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        a = (p0[0] - p1[0], p0[1] - p1[1])
        b = (p2[0] - p1[0], p2[1] - p1[1])
        la, lb = math.hypot(*a), math.hypot(*b)
        if la < 1e-9 or lb < 1e-9:
            continue
        cosang = (a[0] * b[0] + a[1] * b[1]) / (la * lb)
        turn = 180 - math.degrees(math.acos(max(-1.0, min(1.0, cosang))))
        if turn < sharp_deg:
            out.append(p1)
            continue
        cut = min(r, la * 0.45, lb * 0.45)
        s = (p1[0] + a[0] / la * cut, p1[1] + a[1] / la * cut)
        e = (p1[0] + b[0] / lb * cut, p1[1] + b[1] / lb * cut)
        for k in range(6):
            t = k / 5
            out.append(((1 - t) ** 2 * s[0] + 2 * (1 - t) * t * p1[0] + t * t * e[0],
                        (1 - t) ** 2 * s[1] + 2 * (1 - t) * t * p1[1] + t * t * e[1]))
    return dedupe(out)


def signed_area(pts):
    return 0.5 * sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts)))


def orient(pts, ccw):
    return pts if (signed_area(pts) > 0) == ccw else pts[::-1]


# ---- shapes ------------------------------------------------------------------


def gear_outer():
    pts = []
    pitch = 2 * math.pi / TEETH
    for k in range(TEETH):
        c = k * pitch
        rh, th = TOOTH_ROOT * pitch / 2, TOOTH_TIP * pitch / 2
        pts += arc(0, 0, R_ROOT, c - pitch + rh, c - rh, 10)[1:]
        pts += arc(0, 0, R_TIP, c - th, c + th, 8)
        pts.append((R_ROOT * math.cos(c + rh), R_ROOT * math.sin(c + rh)))
    return orient(soften(dedupe(pts)), True)


def gear_inner():
    """Edge of the ring's hole, with one spoke reaching in to the wasm tag."""
    d = SPOKE_DIR
    ux, uy = math.cos(d), math.sin(d)
    nx, ny = -uy, ux
    side = math.asin(SPOKE_HALF / R_HOLE)
    root = math.sqrt(R_HOLE ** 2 - SPOKE_HALF ** 2)
    # hole arc all the way round from the spoke's +n side back to its -n side
    pts = arc(0, 0, R_HOLE, d + side, d + 2 * math.pi - side, 120)
    # down the spoke's -n side, round its tip (centred on the tag), back up +n
    tx, ty = ux * PIECE_HALF, uy * PIECE_HALF
    a0 = math.atan2(-ny, -nx)
    pts += arc(tx, ty, SPOKE_HALF, a0, a0 - math.pi, 20)
    pts.append((ux * root + nx * SPOKE_HALF, uy * root + ny * SPOKE_HALF))
    return orient(soften(dedupe(pts)), False)


def piece_outline():
    """The WebAssembly mark: a square with a semicircle tag cut into one edge."""
    h, r = PIECE_HALF, PIECE_CORNER
    ux, uy = math.cos(SPOKE_DIR), math.sin(SPOKE_DIR)
    cx, cy = ux * h, uy * h            # tag centre, on the middle of that edge
    pts = []
    for qx, qy, a in ((h - r, h - r, 0), (-h + r, h - r, 90), (-h + r, -h + r, 180), (h - r, -h + r, 270)):
        pts += arc(qx, qy, r, math.radians(a), math.radians(a + 90), 6)
    square = orient(dedupe(pts), True)
    dense = []
    for i in range(len(square)):
        p0, p1 = square[i], square[(i + 1) % len(square)]
        n = max(1, int(math.dist(p0, p1) / 0.003))
        dense += [(p0[0] + (p1[0] - p0[0]) * t / n, p0[1] + (p1[1] - p0[1]) * t / n) for t in range(n)]
    m = len(dense)
    inside = [math.hypot(q[0] - cx, q[1] - cy) < TAG_R for q in dense]
    start = inside.index(False)
    out, k = [], 0
    while k < m:
        q = dense[(start + k) % m]
        if not inside[(start + k) % m]:
            out.append(q)
            k += 1
            continue
        entry = q
        while k < m and inside[(start + k) % m]:
            k += 1
        exit_ = dense[(start + k) % m]
        # bite: the tag arc from the entry side to the exit side, through the inside
        a_in = math.atan2(entry[1] - cy, entry[0] - cx)
        a_out = math.atan2(exit_[1] - cy, exit_[0] - cx)
        a_mid = math.atan2(-uy, -ux)   # deepest point of the bite, towards the centre
        # choose the sweep that passes through a_mid
        sweep = (a_out - a_in) % (2 * math.pi)
        if not ((a_mid - a_in) % (2 * math.pi)) < sweep:
            sweep -= 2 * math.pi
        out += arc(cx, cy, TAG_R, a_in, a_in + sweep, 28)
    return orient(soften(dedupe(out), r=0.012), True)


# ---- 3D ----------------------------------------------------------------------
SPIN = 0.0   # in-plane turn of the model, solved below so the spoke points up on screen


def rot(p):
    x, y, z = p
    cs, ss = math.cos(SPIN), math.sin(SPIN)
    x, y = x * cs - y * ss, x * ss + y * cs
    cy, sy = math.cos(math.radians(YAW)), math.sin(math.radians(YAW))
    x, z = x * cy + z * sy, -x * sy + z * cy
    cp, sp = math.cos(math.radians(PITCH)), math.sin(math.radians(PITCH))
    y, z = y * cp - z * sp, y * sp + z * cp
    cr, sr = math.cos(math.radians(ROLL)), math.sin(math.radians(ROLL))
    x, y = x * cr - y * sr, x * sr + y * cr
    return (x, y, z)


def to_screen(v):
    x, y, z = v
    f = CAMERA / (CAMERA - z)
    return (CENTRE[0] + x * f * SCALE, CENTRE[1] + y * f * SCALE)


def project(p):
    return to_screen(rot(p))


def unit(v):
    l = math.sqrt(sum(t * t for t in v)) or 1.0
    return tuple(t / l for t in v)


LIGHT_U = unit(LIGHT)


def walls_of(loops, tag):
    """Visible side walls of the extruded loops: (depth, screen quad, light, tag)."""
    out = []
    for loop in loops:
        n = len(loop)
        for i in range(n):
            a2, b2 = loop[i], loop[(i + 1) % n]
            ta, tb = rot((a2[0], a2[1], 0.0)), rot((b2[0], b2[1], 0.0))
            ba, bb = rot((a2[0], a2[1], -DEPTH)), rot((b2[0], b2[1], -DEPTH))
            u = [tb[k] - ta[k] for k in range(3)]
            v = [ba[k] - ta[k] for k in range(3)]
            # outward normal: loops are CCW (outer) / CW (holes) in the top plane
            nrm = unit((v[1] * u[2] - v[2] * u[1], v[2] * u[0] - v[0] * u[2], v[0] * u[1] - v[1] * u[0]))
            mid = [(ta[k] + bb[k]) / 2 for k in range(3)]
            view = (-mid[0], -mid[1], CAMERA - mid[2])
            if sum(nrm[k] * view[k] for k in range(3)) <= 0:
                continue
            light = max(0.0, sum(nrm[k] * LIGHT_U[k] for k in range(3)))
            out.append((mid[2], [to_screen(p) for p in (ta, tb, bb, ba)], light, tag))
    return out


def poly(pts):
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"


def top_d(loops):
    return " ".join(poly([project((x, y, 0.0)) for x, y in loop]) for loop in loops)


def _spoke_screen_angle(spin):
    global SPIN
    SPIN = spin
    o = project((0.0, 0.0, 0.0))
    t = project((math.cos(SPOKE_DIR) * PIECE_HALF, math.sin(SPOKE_DIR) * PIECE_HALF, 0.0))
    return math.atan2(t[1] - o[1], t[0] - o[0])   # screen angle, y down


def _solve_spin():
    """Turn the model in its own plane until the spoke points straight up on screen."""
    target = -math.pi / 2
    best = min((abs(math.remainder(_spoke_screen_angle(a) - target, 2 * math.pi)), a)
               for a in [i * 2 * math.pi / 720 for i in range(720)])[1]
    lo, hi = best - 0.01, best + 0.01
    for _ in range(50):
        mid = (lo + hi) / 2
        if math.remainder(_spoke_screen_angle(mid) - target, 2 * math.pi) > 0:
            hi = mid
        else:
            lo = mid
    return (lo + hi) / 2


SPIN = _solve_spin()
GEAR = [gear_outer(), gear_inner()]
PIECE = [piece_outline()]


def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(a[k] + (b[k] - a[k]) * t):02x}" for k in range(3))


PAL = {
    "gear": {"dark": "#6e2702", "lit": "#f08a2a", "top0": "#ffc36e", "top1": "#f27412",
             "rim": "#ffe6c2"},
    "piece": {"dark": "#24096a", "lit": "#8a5cf6", "top0": "#bc9dff", "top1": "#6c2fec",
              "rim": "#e6dbff"},
}


def all_walls():
    walls = walls_of(GEAR, "gear") + walls_of(PIECE, "piece")
    walls.sort(key=lambda w: w[0])          # far (lower z) first
    return walls


SQUIRCLE_N = 5.0      # superellipse exponent: 2 = circle, higher = squarer, about 5 reads as an app icon


def squircle_d(n=SQUIRCLE_N, steps=360):
    """App-icon squircle |x|^n + |y|^n = 1 filling the viewBox."""
    h = SIZE / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2 / n), c)
        y = math.copysign(abs(s) ** (2 / n), s)
        pts.append((h + h * x, h + h * y))
    return poly(pts)


def fit_view(margin):
    """Scale and centre the projected mark so its bounds fill the viewBox up to `margin`."""
    global SCALE, CENTRE

    def bounds():
        pts = [project((x, y, z)) for loops in (GEAR, PIECE) for loop in loops for x, y in loop
               for z in (0.0, -DEPTH)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return min(xs), min(ys), max(xs), max(ys)

    x0, y0, x1, y1 = bounds()
    room = SIZE * (1 - 2 * margin)
    SCALE *= min(room / (x1 - x0), room / (y1 - y0))
    x0, y0, x1, y1 = bounds()
    CENTRE = (CENTRE[0] + SIZE / 2 - (x0 + x1) / 2, CENTRE[1] + SIZE / 2 - (y0 + y1) / 2)


def colour_svg(background):
    defs, body = [], []
    if background:
        defs.append(f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" '
                    f'stop-color="#1d1a24"/><stop offset="1" stop-color="{background}"/></linearGradient>')
        defs.append('<radialGradient id="glow-o" cx="0.44" cy="0.82" r="0.46"><stop offset="0" '
                    'stop-color="#ff7a1a" stop-opacity="0.5"/><stop offset="1" stop-color="#ff7a1a" '
                    'stop-opacity="0"/></radialGradient>')
        defs.append('<radialGradient id="glow-p" cx="0.62" cy="0.78" r="0.34"><stop offset="0" '
                    'stop-color="#7a3cff" stop-opacity="0.5"/><stop offset="1" stop-color="#7a3cff" '
                    'stop-opacity="0"/></radialGradient>')
        frame = squircle_d()
        for fill in ("url(#bg)", "url(#glow-o)", "url(#glow-p)"):
            body.append(f'<path d="{frame}" fill="{fill}"/>')
    for _, quad, light, tag in all_walls():
        c = mix(PAL[tag]["dark"], PAL[tag]["lit"], 0.12 + 0.88 * light ** 0.9)
        body.append(f'<path d="{poly(quad)}" fill="{c}" stroke="{c}" stroke-width="0.7" stroke-linejoin="round"/>')
    for tag, loops in (("gear", GEAR), ("piece", PIECE)):
        p = PAL[tag]
        d = top_d(loops)
        defs.append(f'<linearGradient id="{tag}-top" gradientUnits="userSpaceOnUse" x1="140" y1="80" '
                    f'x2="370" y2="430"><stop offset="0" stop-color="{p["top0"]}"/><stop offset="1" '
                    f'stop-color="{p["top1"]}"/></linearGradient>')
        defs.append(f'<clipPath id="{tag}-clip"><path d="{d}" clip-rule="evenodd"/></clipPath>')
        body.append(f'<path d="{d}" fill="url(#{tag}-top)" fill-rule="evenodd"/>')
        body.append(f'<path d="{d}" fill="none" stroke="{p["rim"]}" stroke-opacity="0.9" '
                    f'stroke-width="3" stroke-linejoin="round" clip-path="url(#{tag}-clip)"/>')
    defs.append('<radialGradient id="sheen" gradientUnits="userSpaceOnUse" cx="190" cy="140" r="300">'
                '<stop offset="0" stop-color="#ffffff" stop-opacity="0.30"/>'
                '<stop offset="0.6" stop-color="#ffffff" stop-opacity="0"/></radialGradient>')
    for loops in (GEAR, PIECE):
        body.append(f'<path d="{top_d(loops)}" fill="url(#sheen)" fill-rule="evenodd"/>')
    return wrap("".join(defs), "".join(body))


def silhouette_svg(ink):
    def walls(tag):
        return "".join(f'<path d="{poly(q)}" stroke="{ink}" stroke-width="0.7" stroke-linejoin="round"/>'
                       for _, q, _, t in all_walls() if t == tag)
    gear_top = top_d(GEAR)
    # In one ink the claws and the piece would merge, so cut a channel around
    # the gear's top face out of everything drawn after it (the piece).
    channel = (f'<mask id="channel" maskUnits="userSpaceOnUse" x="0" y="0" width="{SIZE}" height="{SIZE}">'
               f'<rect width="{SIZE}" height="{SIZE}" fill="white"/>'
               f'<path d="{gear_top}" fill="black" fill-rule="evenodd" stroke="black" stroke-width="9" '
               f'stroke-linejoin="round"/></mask>')
    tops = (f'<path d="{gear_top}" fill-rule="evenodd"/>'
            f'<path d="{top_d(PIECE)}" mask="url(#channel)"/>')
    # one ink, so wall order doesn't matter: composite all walls once at 40 %
    # (only the piece's walls get the channel), then the solid top faces
    return wrap(channel, f'<g fill="{ink}" opacity="0.4">{walls("gear")}'
                         f'<g mask="url(#channel)">{walls("piece")}</g></g>'
                         f'<g fill="{ink}">{tops}</g>')


NOTICE = ('Copyright (c) 2026 AlexMitchellMus. All rights reserved. rust_wasm logo; '
          'see artwork/cog-logo/ARTWORK.md in the rust_wasm repository for permitted use.')


def wrap(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" '
            f'height="{SIZE}"><title>rust_wasm</title><desc>{NOTICE}</desc>'
            f'<defs>{defs}</defs>{body}</svg>\n')


def main():
    outputs = {}
    fit_view(0.04)           # bare marks: nearly edge to edge
    outputs["logo-colour.svg"] = colour_svg(None)
    outputs["logo-silhouette-black.svg"] = silhouette_svg("#000000")
    outputs["logo-silhouette-white.svg"] = silhouette_svg("#ffffff")
    fit_view(0.095)          # app icon: large in the squircle, clear of its curved corners
    outputs["logo-colour-dark.svg"] = colour_svg("#0c0b10")
    for name, text in outputs.items():
        (HERE / name).write_text(text)
        print(name, len(text), "bytes")


if __name__ == "__main__":
    main()
