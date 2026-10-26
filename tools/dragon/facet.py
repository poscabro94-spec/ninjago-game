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
HEAD_RINGS = [  # z, half width, top, bottom
    (0.45, 1.0, 0.85, -0.8),
    (-0.2, 1.3, 1.1, -0.95),
    (-0.9, 1.35, 1.15, -0.95),
    (-1.6, 1.25, 1.05, -0.88),
    (-2.3, 1.05, 0.88, -0.75),
    (-3.0, 0.82, 0.7, -0.6),
    (-3.55, 0.6, 0.52, -0.46),
]
HEAD_TIP = V(0, 0.05, -4.05)
HEAD_BACK = V(0, 0.05, 0.75)


def head_ring(z, w, top, bot):
    right = [(0.55 * w, top), (w, 0.45 * top), (0.95 * w, 0.45 * bot), (0.55 * w, bot)]
    return ([V(0, top + 0.14, z)] + [V(x, y, z) for x, y in right] + [V(0, bot - 0.06, z)]
            + [V(-x, y, z) for x, y in reversed(right)])


def build_head():
    p = Piece()
    rings = [head_ring(*r) for r in HEAD_RINGS]
    n = len(rings[0])
    seen = set()
    def edge(a, b, th=0.065):
        key = tuple(sorted((tuple(np.round(a, 4)), tuple(np.round(b, 4)))))
        if key not in seen:
            seen.add(key)
            p.edge(a, b, th)
    # tiles between the rings (each quad = 2 triangles), outlined on all four sides
    for i in range(len(rings) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]
            p.tri(a, b, c); p.tri(a, c, d)
            edge(a, b); edge(b, c); edge(c, d); edge(d, a)
    # pointed snout + closed back
    for k in range(n):
        k2 = (k + 1) % n
        a, b = rings[-1][k], rings[-1][k2]
        p.tri(a, b, HEAD_TIP); edge(a, HEAD_TIP)
        a, b = rings[0][k], rings[0][k2]
        p.tri(b, a, HEAD_BACK)
    # horn plates sweeping back off the top corners
    for s in (1, -1):
        base0, base1 = rings[1][1] * [s, 1, 1] if s < 0 else rings[1][1], rings[0][2] * [s, 1, 1] if s < 0 else rings[0][2]
        if s < 0:
            base0, base1 = rings[1][n - 1], rings[0][n - 2]
        tip = V(s * 1.15, 1.25, 1.55)
        p.tri(base0, base1, tip)
        p.edge(base0, tip, 0.06); p.edge(base1, tip, 0.06)
    # the big white glow inside, and the eyes
    p.glow.append((V(0, 0.1, -1.45), V(1.3, 0.9, 2.6), V(0, 0, 0), 0))
    for sx in (1, -1):
        p.glow.append((V(sx * 1.3, 0.35, -1.05), V(0.12, 0.18, 0.75), V(0, sx * 0.3, sx * 0.15), 0))
    return p


# ---------------------------------------------------------------------------------------------
# body: chevron roof plates down the column (root space; the column runs along Y at z = Z0)
# ---------------------------------------------------------------------------------------------
Z0 = 0.95
SEGMENTS = [  # centre y, half width, half height  (from the head down to the tail)
    (3.85, 0.75, 0.38), (3.1, 0.85, 0.38), (2.35, 0.95, 0.38),          # neck (behind your head)
    (1.55, 1.35, 0.42), (0.7, 1.45, 0.42), (-0.15, 1.35, 0.42), (-1.0, 1.15, 0.42), (-1.85, 0.9, 0.42),  # body
    (-2.65, 0.65, 0.38), (-3.4, 0.45, 0.36),                            # tail
]
TAIL_TIP = V(0, -4.6, Z0 + 0.15)
NECK_TOP = V(0, 4.3, Z0)  # where the head sits (head space origin goes here)


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
            p.edge(e[0], e[1], 0.08)
    # tail tip
    y, w, a = SEGMENTS[-1]
    bl, br, rb = V(-w, y - a, Z0), V(w, y - a, Z0), V(0, y - a - 0.28 * w, Z0 + 0.3 + 0.1 * w)
    p.tri(bl, rb, TAIL_TIP); p.tri(rb, br, TAIL_TIP)
    for e in ((bl, TAIL_TIP), (br, TAIL_TIP), (rb, TAIL_TIP)):
        p.edge(e[0], e[1], 0.08)
    return p


# ---------------------------------------------------------------------------------------------
# wing (right; flat in X-Y, origin at the shoulder hinge, +X out). Zigzag top edge, scalloped bottom.
# ---------------------------------------------------------------------------------------------
WP = {
    "S": V(0, 0, 0), "E": V(1.4, 0.6, 0), "N": V(2.1, -0.35, 0), "K": V(2.8, 0.55, 0), "W": V(6.3, 1.1, 0),
    "Tb": V(6.0, -2.2, 0), "s1": V(4.9, -1.5, 0), "P": V(3.7, -2.6, 0), "s2": V(2.4, -1.85, 0), "B": V(0.15, -2.2, 0),
}


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
WING_OUTLINE = ["S", "E", "N", "K", "W", "Tb", "s1", "P", "s2", "B"]
HINGE = V(1.25, 1.55, Z0 + 0.1)   # right wing's hinge, root space
HINGE_YAW = 0.12


def build_wing():
    p = Piece()
    for a, b, c in ear_clip([WP[k] for k in WING_OUTLINE]):
        p.tri(a, b, c)
    # thick leading edge + bones, outline round the rest
    for a, b, th in [("S", "E", 0.26), ("E", "N", 0.2), ("N", "K", 0.2), ("K", "W", 0.26), ("W", "Tb", 0.16),
                     ("N", "P", 0.14), ("K", "Tb", 0.12),
                     ("Tb", "s1", 0.1), ("s1", "P", 0.1), ("P", "s2", 0.1), ("s2", "B", 0.1), ("B", "S", 0.12)]:
        p.edge(WP[a], WP[b], th)
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
            sc.mesh(m, w, (60, 230, 40), (0, 0, 0), alpha=0.7)
            sc.mesh(hot, w, (170, 255, 120), (170, 255, 120), glow=1.0)
            sc.mesh(glow, w, (255, 255, 255), (0, 0, 0), glow=1.0)
        return [sc.render(v, span=span, center=center) for v in views]
    hover = (np.eye(3), np.zeros(3))
    sc = Scene()
    m, hot, glow = to_mesh(build_head(), G, tube)
    up = mul(T([0, 0, 0]), ang(HEAD_PITCH, 0, 0))
    sc.mesh(glow, up, (255, 255, 255), (0, 0, 0), glow=1.0)
    sc.mesh(m, up, (40, 90, 230), (0, 0, 0), alpha=0.75)
    sc.mesh(hot, up, (140, 190, 255), (140, 190, 255), glow=1.0)
    close = [sc.render(v, span=6.5, center=(0, 1.8, 0)) for v in (rot(0.0, -0.12), rot(-math.pi / 2 + 0.3, -0.1), rot(math.pi * 0.8, 0.3))]
    Image.fromarray(np.concatenate(close, 1)).save(os.path.join(out, "head_close.png"))
    hover = (np.eye(3), np.zeros(3))
    a = render(hover, [rot(0.0, -0.12), rot(-math.pi / 2 + 0.35, -0.1), rot(0, -1.25)], (0, 0.8, 0))
    Image.fromarray(np.concatenate(a, 1)).save(os.path.join(out, "facet.png"))
    print("ok")
