# The Rising Dragon (v4): one tall column behind you, all flat glowing facets with thick outlines.
#   head  - faceted, pointing up the column (head space: origin at the neck joint, -Z = snout)
#   body  - neck + body + tail as chevron "roof" plates down your back (root space, +Z = behind you)
#   wing  - flat bat wing with a zigzag top edge and a scalloped bottom (right wing; left = mirror)
# Each piece: tris (filled, see-through), edges (a, b, thickness: glowing outlines + bones),
# glow blocks (white: eyes, the glow inside the head).
# python facet.py out  renders it on a stand-in character (back / side / top, like the references)
import math, os, sys
import numpy as np

V = lambda x, y, z: np.array([x, y, z], float)


class Piece:
    def __init__(self):
        self.tris, self.edges, self.glow = [], [], []

    def tri(self, a, b, c):
        self.tris.append((a, b, c))

    def edge(self, a, b, th):
        self.edges.append((a, b, th))


def mirrored(pts):
    return {k: v for k, v in pts.items()} | {k + "_": v * [-1, 1, 1] for k, v in pts.items() if abs(v[0]) > 1e-6}


# ---------------------------------------------------------------------------------------------
# head: chunky, tiled with rows of plates (each outlined), pointed snout, ridge down the middle,
# a big white glow inside. Head space: origin at the neck joint, -Z = snout, +Y = up (the game
# turns it to point up the column).
# ---------------------------------------------------------------------------------------------
HEAD_RINGS = [  # z, half width, top, bottom  (back -> snout). The back is the widest: it sits on
    (0.35, 1.35, 0.95, -0.85),           # the neck like a cap with a flat ledge
    (-0.6, 1.3, 1.05, -0.8),
    (-1.7, 1.15, 0.95, -0.65),
    (-2.7, 0.85, 0.75, -0.45),
    (-3.4, 0.5, 0.5, -0.3),
]
HEAD_TIP = V(0, 0.15, -3.85)
JAW_RINGS = [(0.0, 1.05, -0.75, -1.15), (-1.6, 0.85, -0.6, -0.95), (-2.9, 0.45, -0.4, -0.65)]
JAW_TIP = V(0, -0.5, -3.3)
JAW_OPEN = 0.3      # how far the jaw hangs open (radians), hinged at the back


def head_ring(z, w, top, bot, chevron=0.3):
    """ridge vertex set back (so the seams on top make V's down the back of the head)"""
    right = [(0.55 * w, top, 0.12), (w, 0.35 * top, 0.0), (0.9 * w, 0.4 * bot, 0.0), (0.5 * w, bot, 0.0)]
    pts = [V(0, top + 0.12, z + chevron)] + [V(x, y, z + dz) for x, y, dz in right]
    pts += [V(0, bot - 0.04, z)] + [V(-x, y, z + dz) for x, y, dz in reversed(right)]
    return pts


def loft_piece(p, rings, tip, back=None, th=0.05):
    n = len(rings[0])
    seen = set()
    def edge(a, b):
        key = tuple(sorted((tuple(np.round(a, 4)), tuple(np.round(b, 4)))))
        if key not in seen:
            seen.add(key)
            p.edge(a, b, th)
    for i in range(len(rings) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]
            p.tri(a, b, c); p.tri(a, c, d)
            edge(a, b); edge(b, c); edge(c, d); edge(d, a)
    for k in range(n):
        k2 = (k + 1) % n
        a, b = rings[-1][k], rings[-1][k2]
        p.tri(a, b, tip); edge(a, tip)
        if back is not None:
            a, b = rings[0][k], rings[0][k2]
            p.tri(b, a, back)


def build_head():
    p = Piece()
    loft_piece(p, [head_ring(*r) for r in HEAD_RINGS], HEAD_TIP, back=V(0, 0.05, 0.45))
    # lower jaw, hanging open (hinge at the back of the head)
    hinge = V(0, -0.75, 0.2)
    c, s = math.cos(-JAW_OPEN), math.sin(-JAW_OPEN)
    R = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    turn = lambda v: hinge + R @ (v - hinge)
    jaw = [[turn(q) for q in head_ring(z, w, top, bot, chevron=0.0)] for z, w, top, bot in JAW_RINGS]
    loft_piece(p, jaw, turn(JAW_TIP), back=turn(V(0, -0.95, 0.1)))
    # brow plates over the eyes, sticking out a little at the sides
    for sx in (1, -1):
        a, b, tip = V(sx * 1.05, 0.75, -0.3), V(sx * 1.0, 0.7, -1.6), V(sx * 1.55, 0.95, -0.45)
        p.tri(a, b, tip); p.edge(a, tip, 0.05); p.edge(b, tip, 0.05); p.edge(a, b, 0.05)
    # white light inside the mouth + eyes
    p.glow.append((V(0, -0.55, -1.7), V(1.1, 0.35, 2.4), V(-0.15, 0, 0), 0))
    for sx in (1, -1):
        p.glow.append((V(sx * 1.18, 0.4, -1.0), V(0.1, 0.15, 0.6), V(0, sx * 0.3, sx * 0.15), 0))
    return p


# ---------------------------------------------------------------------------------------------
# body: chevron roof plates down the column (root space; the column runs along Y at z = Z0)
# ---------------------------------------------------------------------------------------------
Z0 = 0.95
SEGMENTS = [  # centre y, half width, half height  (from the head down to the tail; small gaps
    (3.85, 1.0, 0.36), (3.05, 1.05, 0.36), (2.25, 1.1, 0.36),          # between them so nothing
    (1.45, 1.4, 0.38), (0.6, 1.45, 0.38), (-0.25, 1.35, 0.38), (-1.1, 1.2, 0.38),  # overlaps)
    (-1.95, 1.0, 0.38), (-2.8, 0.8, 0.38), (-3.6, 0.62, 0.36), (-4.35, 0.45, 0.33),
]
TAIL_TIP = V(0, -5.9, Z0 + 0.1)
NECK_TOP = V(0, 4.9, Z0)  # where the head sits (head space origin goes here)


def build_body():
    p = Piece()
    for y, w, a in SEGMENTS:
        c = 0.28 * w          # how far the chevron dips (points down the tail)
        r = 0.3 + 0.1 * w     # ridge height (away from your back)
        tl, tr = V(-w, y + a, Z0), V(w, y + a, Z0)
        bl, br = V(-w, y - a, Z0), V(w, y - a, Z0)
        rt, rb = V(0, y + a - c, Z0 + r), V(0, y - a - c, Z0 + r)
        for quad in ((tl, rt, rb, bl), (rt, tr, br, rb)):
            p.tri(quad[0], quad[1], quad[2]); p.tri(quad[0], quad[2], quad[3])
        for e in ((tl, rt), (rt, tr), (bl, rb), (rb, br), (tl, bl), (tr, br), (rt, rb)):
            p.edge(e[0], e[1], 0.05)
    # tail tip
    y, w, a = SEGMENTS[-1]
    bl, br, rb = V(-w, y - a, Z0), V(w, y - a, Z0), V(0, y - a - 0.28 * w, Z0 + 0.3 + 0.1 * w)
    p.tri(bl, rb, TAIL_TIP); p.tri(rb, br, TAIL_TIP)
    for e in ((bl, TAIL_TIP), (br, TAIL_TIP), (rb, TAIL_TIP)):
        p.edge(e[0], e[1], 0.05)
    return p


# ---------------------------------------------------------------------------------------------
# wing (right; flat in X-Y, origin at the shoulder hinge, +X out). Zigzag top edge, scalloped bottom.
# ---------------------------------------------------------------------------------------------
def _arc(a, b, bow, n=5):
    """a scallop from a to b, bowing in (up) by `bow`"""
    mid = (a + b) / 2 + V(0, bow, 0)
    return [a * (1 - u) ** 2 + mid * 2 * (1 - u) * u + b * u * u for u in (i / n for i in range(1, n))]


WP = {
    "S": V(0, 0, 0), "E": V(0.75, 0.35, 0), "N": V(1.25, -0.15, 0), "K": V(1.85, 0.42, 0), "W": V(5.9, 0.95, 0),
    "Wx": V(6.35, 1.2, 0), "Tb": V(5.65, -2.7, 0), "P": V(3.3, -2.45, 0), "B": V(0.2, -2.0, 0),
}
SCALLOP1 = _arc(WP["Tb"], WP["P"], 0.75)
SCALLOP2 = _arc(WP["P"], WP["B"], 0.6)


def ear_clip(poly):
    """triangles filling a simple polygon (2D in X-Y), any winding"""
    pts = list(poly)
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    if area < 0:
        pts.reverse()
    def cross(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    def inside(p, a, b, c): return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0
    tris = []
    while len(pts) > 3:
        for i in range(len(pts)):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
            if cross(a, b, c) <= 1e-9:
                continue
            if any(inside(q, a, b, c) for q in pts if q is not a and q is not b and q is not c):
                continue
            tris.append((a, b, c))
            pts.pop(i)
            break
        else:
            raise ValueError("can't triangulate")
    tris.append(tuple(pts))
    return tris
WING_OUTLINE = ["S", "E", "N", "K", "W", "Tb"]  # then the two scallops back to the body
HINGE = V(1.5, 1.45, Z0 + 0.02)   # right wing's hinge, root space
HINGE_YAW = 0.12


def build_wing():
    p = Piece()
    outline = [WP[k] for k in WING_OUTLINE] + SCALLOP1 + [WP["P"]] + SCALLOP2 + [WP["B"]]
    for a, b, c in ear_clip(outline):
        p.tri(a, b, c)
    # leading edge (with the little W by the body), outer edge, bone, scalloped bottom
    for a, b, th in [("S", "E", 0.12), ("E", "N", 0.1), ("N", "K", 0.1), ("K", "W", 0.14), ("W", "Tb", 0.09),
                     ("N", "P", 0.07), ("B", "S", 0.07), ("W", "Wx", 0.08)]:
        p.edge(WP[a], WP[b], th)
    for chain in ([WP["Tb"]] + SCALLOP1 + [WP["P"]], [WP["P"]] + SCALLOP2 + [WP["B"]]):
        for a, b in zip(chain[:-1], chain[1:]):
            p.edge(a, b, 0.06)
    return p


# ---------------------------------------------------------------------------------------------
# preview
# ---------------------------------------------------------------------------------------------
def to_mesh(piece, G, tube):
    m, hot, glow = G.Mesh(), G.Mesh(), G.Mesh()
    for a, b, c in piece.tris:
        m.tri(a, b, c, 1.0)
    for a, b, th in piece.edges:
        hot.line([a, b], th / 2)
    import rock
    for c, s, r, _ in piece.glow:
        P = rock.corners({"c": c, "s": s, "r": r})
        for i, j, k, l in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
            glow.tri(P[i], P[j], P[k]); glow.tri(P[i], P[k], P[l])
    return m, hot, glow


def Rx(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def mul(*cfs):
    R, t = np.eye(3), np.zeros(3)
    for R2, t2 in cfs: R, t = R @ R2, R @ t2 + t
    return R, t
def T(p): return (np.eye(3), np.array(p, float))
def ang(x, y, z): return (Rx(x) @ Ry(y) @ Rz(z), np.zeros(3))

HEAD_SCALE = 1.0
HEAD_PITCH = math.pi / 2   # snout straight up the column


def placed(flap=0.0):
    """(piece, cf in root space) exactly like SpinjitzuDragon places them"""
    out = [(build_body(), T([0, 0, 0]))]
    out.append((build_head(), mul(T(NECK_TOP), ang(HEAD_PITCH, 0, 0), (np.eye(3) * HEAD_SCALE, np.zeros(3)))))
    w = build_wing()
    for side in (1, -1):
        hinge = mul(T([side * HINGE[0], HINGE[1], HINGE[2]]), ang(0, -side * HINGE_YAW, 0), ang(0, 0, side * flap))
        flip = ang(0, math.pi, 0) if side < 0 else T([0, 0, 0])
        out.append((w, mul(hinge, flip)))
    return out


if __name__ == "__main__":
    import geometry as G
    from preview import Scene, rot, tube
    from rockscene import character
    from PIL import Image
    out = sys.argv[1]

    def render(root, views, center, span=17):
        sc = Scene()
        sc.mesh(character(), root, (70, 80, 70), (0, 0, 0))
        for piece, cf in placed(0.05):
            m, hot, glow = to_mesh(piece, G, tube)
            w = mul(root, cf)
            sc.mesh(m, w, (45, 85, 235), (0, 0, 0), alpha=0.88)
            sc.mesh(hot, w, (125, 165, 255), (125, 165, 255))
            sc.mesh(glow, w, (255, 255, 255), (0, 0, 0), glow=1.0)
        return [sc.render(v, span=span, center=center) for v in views]
    hover = (np.eye(3), np.zeros(3))
    sc = Scene()
    m, hot, glow = to_mesh(build_head(), G, tube)
    up = mul(T([0, 0, 0]), ang(HEAD_PITCH, 0, 0))
    sc.mesh(glow, up, (255, 255, 255), (0, 0, 0), glow=1.0)
    sc.mesh(m, up, (45, 85, 235), (0, 0, 0), alpha=0.88)
    sc.mesh(hot, up, (125, 165, 255), (125, 165, 255))
    close = [sc.render(v, span=6.5, center=(0, 1.8, 0)) for v in (rot(0.0, -0.12), rot(-math.pi / 2 + 0.3, -0.1), rot(math.pi * 0.8, 0.3))]
    Image.fromarray(np.concatenate(close, 1)).save(os.path.join(out, "head_close.png"))
    hover = (np.eye(3), np.zeros(3))
    a = render(hover, [rot(0.0, -0.35), rot(-math.pi / 2 + 0.35, -0.1), rot(0, -1.25)], (0, 0.3, 0), span=19)
    Image.fromarray(np.concatenate(a, 1)).save(os.path.join(out, "facet.png"))
    print("ok")
