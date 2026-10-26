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
# head: big chunky plates (few, large), glowing seams, open glowing mouth, crown of horns
# ---------------------------------------------------------------------------------------------

def plate_ring(z, w, top, bot):
    """8-corner cross-section: flat top plate, upper + lower side plates, flat bottom"""
    h = top - bot
    right = [(0.45 * w, top), (1.0 * w, top - 0.28 * h), (0.92 * w, bot + 0.3 * h), (0.5 * w, bot)]
    return [V(x, y, z) for x, y in right] + [V(-x, y, z) for x, y in reversed(right)]


UPPER = [  # z, half width, top, bottom
    (0.6, 0.72, 0.9, -0.5),
    (-0.4, 1.02, 1.22, -0.62),
    (-1.6, 0.96, 1.1, -0.56),
    (-2.8, 0.8, 0.88, -0.5),
    (-3.9, 0.68, 0.76, -0.46),
    (-4.6, 0.6, 0.68, -0.44),
]
UPPER_TIP = V(0, 0.12, -4.85)
UPPER_BACK = V(0, 0.2, 0.95)
JAW = [
    (0.3, 0.86, -0.52, -1.05),
    (-1.5, 0.76, -0.5, -0.96),
    (-3.0, 0.62, -0.48, -0.84),
    (-4.2, 0.5, -0.46, -0.72),
]
JAW_TIP = V(0, -0.58, -4.55)
JAW_BACK = V(0, -0.78, 0.6)
JAW_HINGE = V(0, -0.55, 0.1)


def build_head():
    """(faces, bright): bright = seams, eyes, teeth, the glowing mouth"""
    m, hot = Mesh(), Mesh()
    loft(m, [plate_ring(*k) for k in UPPER], cap_start=UPPER_BACK, cap_end=UPPER_TIP, line_r=0.06)
    for s in (1, -1):
        S = lambda x, y, z: V(s * x, y, z)
        # crown: two big horns swept back, two smaller below them
        spike(m, S(0.5, 1.15, -0.1), S(1.0, 1.75, 1.0), S(1.3, 2.4, 2.6), 0.36, 0.04, rings=6, line_r=0.05)
        spike(m, S(0.9, 0.55, 0.2), S(1.5, 0.75, 1.0), S(1.9, 0.8, 2.1), 0.24, 0.03, rings=5, line_r=0.045)
        # cheek spike and brow blade over the eye
        spike(m, S(0.92, -0.2, -0.5), S(1.45, -0.4, 0.4), S(1.7, -0.75, 1.35), 0.2, 0.03, rings=5, line_r=0.045)
        spike(m, S(0.72, 1.12, -2.0), S(1.1, 1.3, -1.1), S(1.25, 1.5, -0.1), 0.16, 0.03, rings=5, flat=1.8, line_r=0.045)
        # eye: a glowing slit under the brow
        c = V(s * 0.98, 0.55, -1.75)
        fwd = V(0, -0.1, -1.0); fwd = fwd / np.linalg.norm(fwd)
        pts = []
        for k in range(10):
            a = k / 10 * 2 * math.pi
            pts.append(c + fwd * (-math.cos(a) * 0.48) + V(0, 1, 0) * (math.sin(a) * 0.14 + 0.07 * math.cos(a)) + V(s, 0, 0) * 0.05)
        ctr = c + V(s, 0, 0) * 0.08
        for k in range(10):
            p, q = pts[k], pts[(k + 1) % 10]
            hot.tri(ctr, q, p) if s > 0 else hot.tri(ctr, p, q)
        # fangs
        for i, (z, ln) in enumerate([(-4.3, 0.55), (-3.6, 0.32), (-2.8, 0.42), (-2.0, 0.28)]):
            top = S(0.5 - 0.03 * i, -0.44, z)
            spike(hot, top, top + V(0, -ln * 0.5, 0.03), top + V(0, -ln, 0.08), 0.11, 0.01, rings=3, seams=())
    # crest spikes down the middle of the skull
    for z0, y0, ln in [(-1.4, 1.1, 0.8), (-0.6, 1.22, 1.0), (0.25, 1.05, 0.95), (0.9, 0.8, 0.7)]:
        fin(m, V(0, y0 - 0.02, z0 - 0.35), V(0, y0 - 0.06, z0 + 0.35), V(0, y0 + ln, z0 + ln * 0.9), line_r=0.045)
    # the mouth glows: a bright plate along the roof of the mouth
    mouth = [V(0.5, -0.45, 0.2), V(0.45, -0.45, -4.3), V(-0.45, -0.45, -4.3), V(-0.5, -0.45, 0.2)]
    hot.tri(mouth[0], mouth[1], mouth[2]); hot.tri(mouth[0], mouth[2], mouth[3])
    return m, hot


def build_jaw():
    m, hot = Mesh(), Mesh()
    loft(m, [plate_ring(*k) for k in JAW], cap_start=JAW_BACK, cap_end=JAW_TIP, line_r=0.055, shade=0.9)
    for s in (1, -1):
        S = lambda x, y, z: V(s * x, y, z)
        for z, ln in [(-4.0, 0.42), (-3.2, 0.3), (-2.3, 0.34)]:
            bot = S(0.38, -0.52, z)
            spike(hot, bot, bot + V(0, ln * 0.5, -0.02), bot + V(0, ln, -0.06), 0.1, 0.01, rings=3, seams=())
        spike(m, S(0.6, -0.95, -0.1), S(0.95, -1.2, 0.55), S(1.05, -1.6, 1.15), 0.14, 0.02, rings=4, line_r=0.04)
    # glowing floor of the mouth
    mouth = [V(0.42, -0.53, 0.0), V(0.36, -0.53, -4.1), V(-0.36, -0.53, -4.1), V(-0.42, -0.53, 0.0)]
    hot.tri(mouth[0], mouth[2], mouth[1]); hot.tri(mouth[0], mouth[3], mouth[2])
    return m, hot


# ---------------------------------------------------------------------------------------------
# neck: chunky stacked plates from the chest up to the head; chest: plates behind your back
# ---------------------------------------------------------------------------------------------

def build_neck():
    """one neck plate: -Z toward the head (narrower end), +Y away from the body; fin points back"""
    m = Mesh()
    rings = [plate_ring(0.55, 0.95, 0.75, -0.7), plate_ring(-0.55, 0.85, 0.68, -0.62)]
    loft(m, rings, cap_start=V(0, 0.03, 0.55), cap_end=V(0, 0.03, -0.55), line_r=0.055)
    fin(m, V(0, 0.72, -0.35), V(0, 0.68, 0.3), V(0, 1.35, 0.6), line_r=0.045)
    return m


def build_chest():
    """the dragon's chest behind your back: three rows of plates (root space, +Z = behind you)"""
    m = Mesh()
    rows = [(1.5, 0.9, 1.25), (0.55, -0.1, 1.45), (-0.45, -1.15, 1.2)]  # top y, bottom y, half width
    for top, bot, w in rows:
        z0, z1 = 0.55, 1.35
        front = [V(-w, top, z0), V(w, top, z0), V(w, bot, z0), V(-w, bot, z0)]
        bulge = [V(-w * 0.85, top - 0.05, z1), V(w * 0.85, top - 0.05, z1), V(w * 0.8, bot + 0.05, z1), V(-w * 0.8, bot + 0.05, z1)]
        loft(m, [front, bulge], cap_start=None, cap_end=(bulge[0] + bulge[2]) / 2 + V(0, 0, 0.15), line_r=0.055)
    return m


# ---------------------------------------------------------------------------------------------
# wings: laid out spread (flying). Hovering, the whole wing is raised and the hand folds down
# about the wrist (in the wing's plane), so it reads as the tall kite shape.
# ---------------------------------------------------------------------------------------------

WING = dict(
    S=V(0.0, 0.0, 0),     # shoulder (hinge)
    W=V(4.6, 0.9, 0),     # wrist
    C=V(5.5, 2.3, 0),     # wrist spike tip
    T=V(9.4, -0.6, 0),    # wing tip
    X=V(11.8, -1.9, 0),   # tip spike
    n1=V(7.7, -1.4, 0), P1=V(7.1, -2.8, 0),
    n2=V(5.6, -2.0, 0), P2=V(4.6, -3.5, 0),
    n3=V(3.1, -2.4, 0), P3=V(1.9, -3.4, 0),
    B=V(0.3, -2.1, 0),    # where the membrane meets the body
)
WING_SCALE = 1.2
WING = {k: v * WING_SCALE for k, v in WING.items()}


def build_wing():
    """(inner membrane, inner bright, outer membrane, outer bright). The outer part (the hand:
    W, T, n1, P1) turns about the wrist in the wing's plane; it overlaps the inner part when folded."""
    P = WING
    inner, outer = Mesh(), Mesh()
    inner_b, outer_b = Mesh(), Mesh()

    def fan(m, centre, poly, shades, cs=1.0):
        for i in range(len(poly) - 1):
            p, q = poly[i], poly[i + 1]
            m.tri(centre, p, q, (cs, shades[i], shades[i + 1]))
            m.tri(centre, q, p, (cs, shades[i + 1], shades[i]))

    W = P["W"]
    # hand: wrist -> tip -> notch -> point P1 (back to the wrist)
    fan(outer, W, [P["T"], P["n1"], P["P1"]], [0.95, 0.55, 0.85])
    # arm: wrist over P1 -> notches/points -> body -> shoulder
    fan(inner, W, [P["P1"], P["n2"], P["P2"], P["n3"], P["P3"], P["B"], P["S"]], [0.85, 0.55, 0.85, 0.55, 0.8, 0.7, 1.0])
    # bones (thick leading edge) + spikes + outline
    inner_b.line([P["S"], W], 0.17)
    inner_b.line([W, P["P2"]], 0.08)
    inner_b.line([P["P1"], P["n2"], P["P2"], P["n3"], P["P3"], P["B"]], 0.07)
    inner_b.line([P["B"], P["S"]], 0.08)
    outer_b.line([W, P["T"]], 0.14)
    outer_b.line([W, P["P1"]], 0.09)
    outer_b.line([P["T"], P["n1"], P["P1"]], 0.07)
    spike(outer_b, W, (W + P["C"]) / 2 + V(-0.1, 0, 0), P["C"], 0.13, 0.02, rings=4, seams=())
    spike(outer_b, P["T"], (P["T"] + P["X"]) / 2 + V(0, 0.1, 0), P["X"], 0.11, 0.015, rings=4, seams=())
    return inner, inner_b, outer, outer_b


def wing_outline():
    P = WING
    return {"trail": [P["T"], P["n1"], P["P1"], P["n2"], P["P2"], P["n3"], P["P3"], P["B"]]}


# ---------------------------------------------------------------------------------------------
# placement (shared with the game: SpinjitzuDragon uses the same numbers via DragonModel)
# ---------------------------------------------------------------------------------------------

HINGE = V(0.95, 1.25, 0.95)        # right wing's shoulder hinge in root space (left = mirrored)
HINGE_YAW = 0.18                  # wings swept back a little
WING_RAISE_HOVER = 1.02           # hovering: the whole wing raised (radians) ...
HAND_FOLD_HOVER = -1.25           # ... and the hand turned down about the wrist
WING_RAISE_FLY = 0.12             # flying: spread out, a shallow V
HAND_FOLD_FLY = -0.1
NECK_BASE = V(0, 1.4, 1.0)        # where the neck leaves the chest
NECK_N = 5
HEAD_SCALE = 1.25
HEAD_POS_HOVER = V(0, 4.6, 1.3)   # neck joint of the head in root space, hovering / flying
HEAD_POS_FLY = V(0, 4.4, 0.9)
HEAD_PITCH_HOVER = 0.75           # snout raised (radians): hovering it rears up
HEAD_PITCH_FLY = 1.5
FLY_DIHEDRAL = 0.0
