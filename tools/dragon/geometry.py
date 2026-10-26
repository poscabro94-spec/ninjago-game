# Dragon geometry for the Rising Dragon technique (head, jaw, eyes, wings).
# Shared by build.py (writes src/ReplicatedStorage/DragonModel.luau) and preview.py (renders PNGs).
# Units are studs at DragonScale 1. Head space: origin at the neck joint, -Z = snout, +Y = up.
# Wing space (right wing): origin at the shoulder hinge, +X = out from the body, +Y = up, the wing
# lies in the X-Y plane (the left wing is the mirror).
import math
import numpy as np

V = lambda x, y, z: np.array([x, y, z], float)


class Mesh:
    """flat-shaded triangles (each with a shade 0..1 baked as vertex colour) + glowing seam lines"""
    def __init__(self):
        self.tris = []   # (p, q, r, shade)
        self.lines = []  # polylines (list of points), drawn as glowing strips
        self.radius = []  # line thickness per polyline

    def tri(self, p, q, r, shade=1.0):
        """shade: one value for the face, or (sp, sq, sr) per corner (blended across it)"""
        if not isinstance(shade, (tuple, list)):
            shade = (shade, shade, shade)
        self.tris.append((np.array(p, float), np.array(q, float), np.array(r, float), tuple(float(s) for s in shade)))

    def line(self, pts, radius):
        self.lines.append([np.array(p, float) for p in pts])
        self.radius.append(radius)


def facing_shade(p, q, r, base=1.0):  # noqa
    """plates facing up / forward are brighter, sides + underneath darker (stepped, so plates read)"""
    n = np.cross(q - p, r - p)
    l = np.linalg.norm(n)
    n = n / l if l > 1e-9 else np.array([0, 1, 0.0])
    t = 0.62 + 0.38 * n[1] - 0.12 * n[2] - 0.1 * abs(n[0])
    t = round(min(max(t, 0.25), 1.0) * 8) / 8
    return t * base


def loft(m, rings, cap_start=None, cap_end=None, outline_every=1, line_r=0.045, shade=1.0, lines=True, closed=True):
    n = len(rings[0])
    count = n if closed else n - 1
    for i in range(len(rings) - 1):
        for k in range(count):
            k2 = (k + 1) % n
            p, q, r, s = rings[i][k], rings[i][k2], rings[i + 1][k], rings[i + 1][k2]
            m.tri(p, r, q, facing_shade(p, r, q, shade))
            m.tri(q, r, s, facing_shade(q, r, s, shade))
    if cap_start is not None:
        for k in range(count):
            p, q = rings[0][k], rings[0][(k + 1) % n]
            m.tri(cap_start, p, q, facing_shade(cap_start, p, q, shade))
    if cap_end is not None:
        L = rings[-1]
        for k in range(count):
            p, q = L[(k + 1) % n], L[k]
            m.tri(cap_end, p, q, facing_shade(cap_end, p, q, shade))
    if lines:
        for k in range(n):
            pts = [r[k] for r in rings]
            m.line(pts, line_r)
        idx = list(range(0, len(rings), outline_every))
        if idx[-1] != len(rings) - 1:
            idx.append(len(rings) - 1)
        for i in idx:
            m.line(list(rings[i]) + ([rings[i][0]] if closed else []), line_r)


def bezier(p0, p1, p2, t):
    return p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t


def spike(m, p0, p1, p2, r0, r1, rings=5, flat=1.0, line_r=0.035, shade=1.0, seams=(0, 2)):
    """tapered 4-sided spike along a bezier (flat < 1 squashes it into a blade)"""
    p0, p1, p2 = map(np.array, (p0, p1, p2))
    rs = []
    for i in range(rings):
        t = i / (rings - 1) * 0.9
        pos = bezier(p0, p1, p2, t)
        tan = (p1 - p0) * 2 * (1 - t) + (p2 - p1) * 2 * t
        tan /= np.linalg.norm(tan)
        side = np.cross(tan, [0, 1, 0])
        if np.linalg.norm(side) < 1e-3:
            side = np.array([1.0, 0, 0])
        side /= np.linalg.norm(side)
        up = np.cross(side, tan)
        r = r0 + (r1 - r0) * t / 0.9
        rs.append([pos + side * r * flat, pos + up * r, pos - side * r * flat, pos - up * r])
    loft(m, rs, cap_start=p0 - (p1 - p0) / np.linalg.norm(p1 - p0) * 0.02, cap_end=p2, lines=False, shade=shade)
    for k in seams:
        m.line([r[k] for r in rs] + [p2], line_r)


def fin(m, base0, base1, tip, thick=0.07, line_r=0.035, shade=1.0):
    """a thin flat blade (crest plate): triangle base0-base1-tip with a little thickness"""
    base0, base1, tip = map(np.array, (base0, base1, tip))
    n = np.cross(base1 - base0, tip - base0)
    n = n / np.linalg.norm(n) * thick / 2
    a = [base0 + n, base1 + n, tip + n]
    b = [base0 - n, base1 - n, tip - n]
    m.tri(a[0], a[1], a[2], facing_shade(a[0], a[1], a[2], shade))
    m.tri(b[0], b[2], b[1], facing_shade(b[0], b[2], b[1], shade))
    for i in range(3):
        j = (i + 1) % 3
        m.tri(a[i], b[i], a[j], shade * 0.8)
        m.tri(a[j], b[i], b[j], shade * 0.8)
    m.line([base0, tip, base1], line_r)


# ---------------------------------------------------------------------------------------------
# head
# ---------------------------------------------------------------------------------------------

def head_ring(z, w, top, bot, brow=0.0):
    """10-corner plated cross-section: flat top plate, brow corner, widest point, cheek, flat bottom"""
    h = top - bot
    mid = bot + h * 0.48
    right = [
        (0.42 * w, top),
        (0.86 * w, top - 0.2 * h + brow),
        (1.0 * w, mid),
        (0.84 * w, bot + 0.18 * h),
        (0.4 * w, bot),
    ]
    pts = [V(x, y, z) for x, y in right] + [V(-x, y, z) for x, y in reversed(right)]
    return pts


# upper head: z, half width, top, bottom, brow lift
UPPER = [
    (0.55, 0.66, 0.92, -0.48, 0.0),
    (0.1, 1.0, 1.26, -0.72, 0.0),
    (-0.6, 1.08, 1.36, -0.74, 0.14),
    (-1.3, 0.96, 1.22, -0.64, 0.2),
    (-2.0, 0.8, 1.0, -0.56, 0.04),
    (-2.75, 0.72, 0.88, -0.53, 0.0),
    (-3.45, 0.72, 0.86, -0.5, 0.0),   # nostril flare
    (-3.95, 0.56, 0.7, -0.45, 0.0),
]
UPPER_TIP = V(0, 0.14, -4.12)
UPPER_BACK = V(0, 0.2, 0.88)

# lower jaw (closed position; it swings open around JAW_HINGE)
JAW = [
    (0.3, 0.86, -0.5, -1.12),
    (-0.6, 0.82, -0.5, -1.06),
    (-1.7, 0.66, -0.5, -0.9),
    (-2.8, 0.56, -0.48, -0.78),
    (-3.6, 0.46, -0.47, -0.7),
    (-3.95, 0.34, -0.47, -0.64),
]
JAW_TIP = V(0, -0.56, -4.08)
JAW_BACK = V(0, -0.72, 0.62)
JAW_HINGE = V(0, -0.6, 0.2)


def jaw_ring(z, w, top, bot):
    h = top - bot
    right = [(0.5 * w, top), (0.95 * w, top - 0.15 * h), (0.9 * w, bot + 0.3 * h), (0.45 * w, bot)]
    return [V(x, y, z) for x, y in right] + [V(-x, y, z) for x, y in reversed(right)]


def build_head():
    """(faces, bright): bright = seams + teeth + eyes (the glowing part)"""
    m = Mesh()
    hot = Mesh()
    rings = [head_ring(*k) for k in UPPER]
    loft(m, rings, cap_start=UPPER_BACK, cap_end=UPPER_TIP, line_r=0.032, outline_every=1)
    for s in (1, -1):
        S = lambda x, y, z: V(s * x, y, z)
        # big horns, swept back + up
        spike(m, S(0.52, 1.15, 0.0), S(1.0, 1.8, 1.1), S(1.25, 2.45, 2.7), 0.32, 0.03, rings=7)
        # cheek spikes, swept back + down
        spike(m, S(0.95, -0.2, -0.25), S(1.45, -0.35, 0.55), S(1.7, -0.75, 1.45), 0.18, 0.02, rings=5)
        # brow ridge blade over the eye, pointing back
        spike(m, S(0.66, 1.24, -1.75), S(1.08, 1.36, -0.85), S(1.28, 1.55, 0.25), 0.14, 0.03, rings=5, flat=1.8)
        # nostril bumps
        spike(m, S(0.4, 0.82, -3.75), S(0.5, 1.0, -3.5), S(0.52, 1.08, -3.2), 0.12, 0.02, rings=4)
        # teeth on the upper jaw (fangs at the front)
        for i, z in enumerate([-3.75, -3.3, -2.85, -2.4, -1.95, -1.5]):
            ln = 0.42 if i == 0 else (0.28 if i % 2 else 0.2)
            top = S(0.5 - 0.015 * i, -0.46, z)
            spike(hot, top, top + V(0, -ln * 0.5, 0.03), top + V(0, -ln, 0.08), 0.075, 0.01, rings=3, seams=())
    # crest fins down the back of the skull
    for z0, y0, ln in [(-0.95, 1.36, 0.7), (-0.3, 1.3, 0.95), (0.35, 1.08, 0.9), (0.8, 0.8, 0.65)]:
        fin(m, V(0, y0 - 0.02, z0 - 0.3), V(0, y0 - 0.06, z0 + 0.3), V(0, y0 + ln, z0 + ln * 0.9))
    eyes(hot)
    return m, hot


def build_jaw():
    m = Mesh()
    hot = Mesh()
    rings = [jaw_ring(*k) for k in JAW]
    loft(m, rings, cap_start=JAW_BACK, cap_end=JAW_TIP, line_r=0.03, shade=0.9)
    for s in (1, -1):
        S = lambda x, y, z: V(s * x, y, z)
        for i, z in enumerate([-3.7, -3.2, -2.7, -2.2, -1.7]):
            ln = 0.36 if i == 0 else (0.24 if i % 2 else 0.18)
            bot = S(0.38 - 0.01 * i, -0.5, z)
            spike(hot, bot, bot + V(0, ln * 0.5, -0.02), bot + V(0, ln, -0.06), 0.065, 0.01, rings=3, seams=())
        # chin spike
        spike(m, S(0.55, -0.95, 0.05), S(0.85, -1.2, 0.65), S(0.95, -1.55, 1.2), 0.12, 0.02, rings=4)
    return m, hot


def eyes(m):
    """slanted almond eyes under the brow, slightly proud of the head surface"""
    for s in (1, -1):
        c = V(s * 0.95, 0.68, -1.35)
        fwd = V(0, -0.12, -1.0)
        fwd = fwd / np.linalg.norm(fwd)
        up = V(0, 1, 0.0)
        out = V(s, 0, 0.0)
        L, H = 0.42, 0.13
        pts = []
        for k in range(10):
            a = k / 10 * 2 * math.pi
            x = math.cos(a) * L
            y = math.sin(a) * H * (1 - 0.35 * math.cos(a))
            y += 0.06 * math.cos(a)  # back corner higher (angry slant)
            pts.append(c + fwd * (-x) + up * y + out * 0.04)
        ctr = c + out * 0.07
        for k in range(10):
            p, q = pts[k], pts[(k + 1) % 10]
            if s > 0:
                m.tri(ctr, q, p, 1.0)
            else:
                m.tri(ctr, p, q, 1.0)


# ---------------------------------------------------------------------------------------------
# wings
# ---------------------------------------------------------------------------------------------

WING_SCALE = 0.85
WING = dict(
    S=V(0.0, 0.0, 0),     # shoulder (hinge)
    H=V(0.15, -2.6, 0),   # where the membrane meets the body, low on the back
    W=V(3.3, 2.9, 0),     # wrist: top of the arm bone
    C=V(3.0, 3.9, 0),     # thumb claw tip
    F1=V(8.4, 4.3, 0),    # finger tips, from the leading edge round to the back
    F2=V(9.0, 1.0, 0),
    F3=V(7.4, -1.9, 0),
    F4=V(4.5, -3.4, 0),
)
WING = {k: v * WING_SCALE for k, v in WING.items()}
FINGERS = ["F1", "F2", "F3", "F4"]


def scallop(a, b, w, depth=0.3, n=6):
    """trailing edge between two tips, bowing in toward the wrist"""
    mid = (a + b) / 2
    ctrl = mid + (w - mid) * depth
    return [bezier(a, ctrl, b, i / n) for i in range(n + 1)]


def wing_outline():
    P = WING
    edges = {}
    edges["F1F2"] = scallop(P["F1"], P["F2"], P["W"], 0.28)
    edges["F2F3"] = scallop(P["F2"], P["F3"], P["W"], 0.3)
    edges["F3F4"] = scallop(P["F3"], P["F4"], P["W"], 0.32)
    edges["F4H"] = scallop(P["F4"], P["H"], P["W"] * 0.4 + P["S"] * 0.6, 0.3, n=7)
    return edges


def build_wing():
    """returns (inner membrane, inner bones, outer membrane, outer bones); outer folds about W-F4"""
    P = WING
    E = wing_outline()
    inner, outer = Mesh(), Mesh()
    inner_b, outer_b = Mesh(), Mesh()

    def membrane(m, fan, poly, shades, fan_shade=1.0):
        """fan from `fan` over the outline; bright along the bones, darker out in the middle of
        each panel by the trailing edge. Double-sided (both windings)."""
        for i in range(len(poly) - 1):
            p, q = poly[i], poly[i + 1]
            m.tri(fan, p, q, (fan_shade, shades[i], shades[i + 1]))
            m.tri(fan, q, p, (fan_shade, shades[i + 1], shades[i]))

    def edge_shades(n):
        # tips (ends) bright, the middle of a scallop dark
        return [0.5 + 0.48 * abs(1 - 2 * i / n) ** 1.6 for i in range(n + 1)]

    W = P["W"]
    # outer: fan from the wrist over F4 -> F3 -> F2 -> F1 (trailing edge scallops)
    poly, shades = [], []
    for name in ["F3F4", "F2F3", "F1F2"]:
        pts = list(reversed(E[name]))
        sh = edge_shades(len(pts) - 1)
        if poly:
            pts, sh = pts[1:], sh[1:]
        poly += pts
        shades += sh
    membrane(outer, W, poly, shades)
    # inner: fan from the wrist over the F4 -> body trailing edge, then up the body to the shoulder
    pts = list(E["F4H"])
    membrane(inner, W, pts + [P["S"]], edge_shades(len(pts) - 1) + [0.95])

    # bones: arm (shoulder -> wrist), fingers (wrist -> tips), thumb claw
    inner_b.line([P["S"], W], 0.2)
    inner_b.line([W, P["C"]], 0.12)
    for f in FINGERS:
        (inner_b if f == "F4" else outer_b).line([W, P[f]], 0.13 if f == "F1" else 0.09)
    # glowing trailing edge
    for name in ["F1F2", "F2F3", "F3F4"]:
        outer_b.line(E[name], 0.05)
    inner_b.line(E["F4H"], 0.05)
    inner_b.line([P["H"], P["S"]], 0.07)
    return inner, inner_b, outer, outer_b


# ---------------------------------------------------------------------------------------------
# neck: one plated collar, repeated along a curve from the back to the head (the game places them)
# ---------------------------------------------------------------------------------------------

NECK_LEN = 0.95  # length of one collar (they overlap a little)


def build_neck():
    """-Z toward the head (narrower end), +Y away from the body; fin points back"""
    m = Mesh()
    rings = [head_ring(0.5, 0.7, 0.8, -0.62), head_ring(-0.5, 0.62, 0.7, -0.55)]
    loft(m, rings, cap_start=V(0, 0.08, 0.5), cap_end=V(0, 0.1, -0.5), line_r=0.03)
    # a crest fin on top, pointing back
    fin(m, V(0, 0.72, -0.35), V(0, 0.68, 0.25), V(0, 1.25, 0.55))
    return m


# ---------------------------------------------------------------------------------------------
# placement (shared with the game: SpinjitzuDragon uses the same numbers)
# ---------------------------------------------------------------------------------------------

HINGE = V(0.55, 0.95, 0.65)       # right wing hinge in root space (left = mirrored)
HINGE_YAW = 0.28                  # wings swept back a little
NECK_BASE = V(0, 0.7, 0.75)       # where the neck leaves the back
NECK_N = 6
HEAD_SCALE = 1.3                  # the head mesh is built at 1, shown at this size
HEAD_POS_HOVER = V(0, 4.1, 1.0)   # neck joint of the head in root space, hovering / flying
HEAD_POS_FLY = V(0, 3.8, 0.6)
HEAD_PITCH_HOVER = 0.55           # snout raised this much (radians) hovering / flying
HEAD_PITCH_FLY = 1.5
FLY_DIHEDRAL = 0.22               # wings raised into a shallow V when flying
