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
SKULL = [  # z, half width, top, bottom  (back -> snout): a wide shield, widest at the eyes
    (0.4, 1.2, 0.85, -0.35),     # sits on the neck like a cap
    (-0.6, 1.35, 1.0, -0.35),
    (-1.6, 1.3, 0.95, -0.32),
    (-2.6, 1.05, 0.8, -0.28),
    (-3.4, 0.75, 0.6, -0.24),
]
SKULL_TIP = V(0, 0.2, -3.95)
JAW = [(0.3, 1.15, -0.4, -0.95), (-1.2, 1.05, -0.4, -0.88), (-2.5, 0.85, -0.4, -0.75), (-3.3, 0.55, -0.4, -0.62)]
JAW_TIP = V(0, -0.47, -3.75)
JAW_HINGE = V(0, -0.4, 0.3)
JAW_OPEN = 0.6      # the mouth is wide open (radians)


def head_ring(z, w, top, bot, chevron=0.3):
    """ridge vertex set back (so the seams on top make V's down the back of the head)"""
    right = [(0.62 * w, top, 0.12), (w, 0.55 * top + 0.1 * bot, 0.0), (0.95 * w, bot + 0.2 * (top - bot), 0.0), (0.55 * w, bot, 0.0)]
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


def _jaw_turn():
    c, s = math.cos(-JAW_OPEN), math.sin(-JAW_OPEN)
    R = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    return lambda v: JAW_HINGE + R @ (v - JAW_HINGE)


def plate(p, c, size, tilt, th=0.045):
    """a raised block (centre, size, tilt as CFrame.Angles), filled + all 12 edges outlined"""
    import rock
    P = rock.corners({"c": c, "s": size, "r": tilt})
    for i, j, k, l in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
        p.tri(P[i], P[j], P[k]); p.tri(P[i], P[k], P[l])
    for i, j in [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]:
        p.edge(P[i], P[j], th)


def build_head():
    p = Piece()
    loft_piece(p, [head_ring(*r) for r in SKULL], SKULL_TIP, back=V(0, 0.1, 0.55))
    # lower jaw, wide open
    turn = _jaw_turn()
    jaw = [[turn(q) for q in head_ring(z, w, top, bot, chevron=0.0)] for z, w, top, bot in JAW]
    loft_piece(p, jaw, turn(JAW_TIP), back=turn(V(0, -0.7, 0.45)))
    # stubby horns at the back corners
    for sx in (1, -1):
        a, b, tip = V(sx * 1.1, 0.7, 0.35), V(sx * 1.15, 0.05, 0.3), V(sx * 1.7, 0.6, 1.0)
        p.tri(a, b, tip); p.edge(a, tip, 0.05); p.edge(b, tip, 0.05)
    # raised plates: brow arches over the eyes (sockets), cheek guards at the back, a crest down
    # the ridge, a ridge along the nose
    for sx in (1, -1):
        plate(p, V(sx * 0.95, 1.0, -1.35), V(0.6, 0.3, 1.55), V(0.12, sx * 0.15, -sx * 0.38))
        plate(p, V(sx * 1.32, 0.15, -0.15), V(0.45, 0.95, 1.15), V(0, sx * 0.22, -sx * 0.1))
    for z in (-0.25, -0.95, -1.65):
        plate(p, V(0, 1.15, z), V(0.12, 0.38, 0.62), V(-0.5, 0, 0))
    plate(p, V(0, 0.72, -3.0), V(0.5, 0.2, 1.15), V(0.18, 0, 0))
    # white light filling the open mouth (roof + floor), and the eyes
    p.glow.append((V(0, -0.44, -1.7), V(1.3, 0.06, 2.9), V(0, 0, 0), 0))
    jc = turn(V(0, -0.42, -1.6))
    p.glow.append((jc, V(1.0, 0.08, 3.0), V(-JAW_OPEN, 0, 0), 0))
    p.glow.append((V(0, -0.62, -1.5), V(0.9, 0.45, 2.3), V(-JAW_OPEN / 2, 0, 0), 0.15))  # the glow between
    for sx in (1, -1):
        p.glow.append((V(sx * 1.3, 0.45, -1.35), V(0.1, 0.2, 0.9), V(0, sx * 0.25, sx * 0.2), 0))
    return p


# ---------------------------------------------------------------------------------------------
# body: chevron roof plates down the column (root space; the column runs along Y at z = Z0)
# ---------------------------------------------------------------------------------------------
Z0 = 0.95
BODY_FRONT = 0.62   # the body's front (against your back), root space z
BODY_RINGS = [  # y, half width, depth (front to back)   from the neck top down to the tail
    (4.35, 1.1, 1.05), (3.55, 1.05, 1.0), (2.75, 1.15, 1.05),
    (1.95, 1.4, 1.25), (1.15, 1.5, 1.3), (0.35, 1.45, 1.3), (-0.45, 1.3, 1.2), (-1.25, 1.1, 1.05),
    (-2.05, 0.9, 0.9), (-2.85, 0.7, 0.75), (-3.65, 0.52, 0.6), (-4.4, 0.38, 0.48),
]
BODY_V = 0.45       # the plate seams on the back dip into V's this deep
TAIL_TIP = V(0, -6.0, BODY_FRONT + 0.25)
NECK_TOP = V(0, 5.03, BODY_FRONT + 0.55)  # where the head sits (head space origin goes here)


def body_ring(y, w, d):
    zb = BODY_FRONT + d
    right = [(0.6 * w, y, zb), (w, y, BODY_FRONT + 0.55 * d), (0.75 * w, y, BODY_FRONT), ]
    pts = [V(0, y - BODY_V, zb + 0.22)] + [V(*q) for q in right] + [V(0, y, BODY_FRONT)]
    pts += [V(-q[0], q[1], q[2]) for q in reversed(right)]
    return pts


def build_body():
    p = Piece()
    rings = [body_ring(*r) for r in BODY_RINGS]
    n = len(rings[0])
    seen = set()
    def edge(a, b):
        key = tuple(sorted((tuple(np.round(a, 4)), tuple(np.round(b, 4)))))
        if key not in seen:
            seen.add(key)
            p.edge(a, b, 0.05)
    for i in range(len(rings) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]
            p.tri(a, b, c); p.tri(a, c, d)
            edge(a, b); edge(b, c); edge(c, d); edge(d, a)
    for k in range(n):
        k2 = (k + 1) % n
        a, b = rings[-1][k], rings[-1][k2]
        p.tri(a, b, TAIL_TIP); edge(a, TAIL_TIP)
        a, b = rings[0][k], rings[0][k2]
        p.tri(b, a, V(0, BODY_RINGS[0][0] + 0.05, BODY_FRONT + 0.5))
    return p


# ---------------------------------------------------------------------------------------------
# wing (right; flat in X-Y, origin at the shoulder hinge, +X out). Zigzag top edge, scalloped bottom.
# ---------------------------------------------------------------------------------------------
def _arc(a, b, bow, n=5):
    """a scallop from a to b, bowing in (up) by `bow`"""
    mid = (a + b) / 2 + V(0, bow, 0)
    return [a * (1 - u) ** 2 + mid * 2 * (1 - u) * u + b * u * u for u in (i / n for i in range(1, n))]


WP = {
    "S": V(0, 0, 0), "E": V(0.75, 0.4, 0), "N": V(1.25, -0.2, 0), "K": V(1.85, 0.45, 0), "W": V(5.9, 0.95, 0),
    "Wx": V(6.45, 1.3, 0), "Tb": V(5.55, -2.95, 0), "P": V(3.2, -2.75, 0), "B": V(0.25, -1.7, 0),
}
SCALLOP1 = _arc(WP["Tb"], WP["P"], 1.05)
SCALLOP2 = _arc(WP["P"], WP["B"], 0.85)


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
HINGE = V(1.5, 1.7, BODY_FRONT + 0.75)   # right wing's hinge, root space (on the body's side)
HINGE_YAW = 0.12
WING_RAISE = 0.22                         # wings tilted up toward the tips


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

HEAD_SCALE = 1.15
HEAD_PITCH = math.pi / 2   # snout straight up the column


def placed(flap=0.0):
    """(piece, cf in root space) exactly like SpinjitzuDragon places them"""
    out = [(build_body(), T([0, 0, 0]))]
    out.append((build_head(), mul(T(NECK_TOP), ang(HEAD_PITCH, 0, 0), (np.eye(3) * HEAD_SCALE, np.zeros(3)))))
    w = build_wing()
    for side in (1, -1):
        hinge = mul(T([side * HINGE[0], HINGE[1], HINGE[2]]), ang(0, -side * HINGE_YAW, 0), ang(0, 0, side * (WING_RAISE + flap)))
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
            sc.mesh(m, w, (45, 60, 240), (0, 0, 0))
            sc.mesh(hot, w, (150, 165, 255), (150, 165, 255), glow=1.0)
            sc.mesh(glow, w, (255, 255, 255), (0, 0, 0), glow=1.0)
        return [sc.render(v, span=span, center=center) for v in views]
    hover = (np.eye(3), np.zeros(3))
    sc = Scene()
    m, hot, glow = to_mesh(build_head(), G, tube)
    up = mul(T([0, 0, 0]), ang(HEAD_PITCH, 0, 0))
    sc.mesh(glow, up, (255, 255, 255), (0, 0, 0))
    sc.mesh(m, up, (45, 60, 240), (0, 0, 0))
    sc.mesh(hot, up, (150, 165, 255), (150, 165, 255), glow=1.0)
    close = [sc.render(v, span=6.5, center=(0, 1.8, 0)) for v in (rot(math.pi, -0.1), rot(-math.pi / 2, 0), rot(0, -0.5), rot(math.pi * 0.75, 0.35))]
    Image.fromarray(np.concatenate(close, 1)).save(os.path.join(out, "head_close.png"))
    # like the references: hovering from the front (a bit above), from the side; flying from behind + above
    a = render(hover, [rot(math.pi, -0.15), rot(-math.pi / 2, -0.05)], (0, 0.8, 0), span=19)
    fly = (Rx(-math.radians(75)), np.zeros(3))
    b = render(fly, [rot(0.0, -0.7)], (0, 1.0, -3.0), span=19)
    Image.fromarray(np.concatenate(a + b, 1)).save(os.path.join(out, "facet.png"))
    print("ok")
