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
        self.gtris = []   # glowing white triangles (the inside of the mouth)
        self.teeth = []   # solid teeth (their own colour)

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
JAW = [  # heavier: a strong angle at the back, tapering to a chin
    (0.35, 1.2, -0.4, -1.2), (-0.7, 1.15, -0.4, -1.08), (-1.9, 0.98, -0.4, -0.88),
    (-2.9, 0.75, -0.4, -0.74), (-3.5, 0.55, -0.42, -0.7),
]
JAW_TIP = V(0, -0.5, -3.9)
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
    # the inside of the mouth is white: the roof, the floor, the gums the teeth grow from and the
    # back of the throat (the gap between the jaws stays open)
    p.glow.append((V(0, -0.43, -1.75), V(1.15, 0.04, 3.1), V(0, 0, 0), 0, "block"))         # roof
    jc = turn(V(0, -0.41, -1.75))
    p.glow.append((jc, V(1.05, 0.04, 3.1), V(-JAW_OPEN, 0, 0), 0, "block"))                # floor
    for sx in (1, -1):
        p.glow.append((V(sx * 0.56, -0.5, -1.85), V(0.05, 0.16, 2.9), V(0, 0, 0), 0, "block"))     # upper gums
        p.glow.append((turn(V(sx * 0.54, -0.35, -1.75)), V(0.05, 0.16, 2.7), V(-JAW_OPEN, 0, 0), 0, "block"))  # lower
    throat = [V(-0.55, -0.42, 0.05), V(0.55, -0.42, 0.05), turn(V(0.55, -0.42, 0.1)), turn(V(-0.55, -0.42, 0.1))]
    p.gtris.append((throat[0], throat[1], throat[2])); p.gtris.append((throat[0], throat[2], throat[3]))
    # ... with jagged teeth along both jaws (solid, so they stand out against the light)
    for sx in (1, -1):
        for i, z in enumerate([-0.55, -1.0, -1.45, -1.9, -2.35, -2.8, -3.2]):
            ln = 0.38 if i % 2 == 0 else 0.26
            x = sx * (0.62 - 0.03 * i)
            a, b, tip = V(x, -0.4, z + 0.2), V(x, -0.4, z - 0.2), V(x, -0.4 - ln, z - 0.05)
            p.teeth.append((a, b, tip))
        for i, z in enumerate([-0.5, -0.95, -1.4, -1.85, -2.3, -2.75]):
            ln = 0.32 if i % 2 == 0 else 0.22
            x = sx * (0.6 - 0.03 * i)
            a, b, tip = turn(V(x, -0.42, z + 0.2)), turn(V(x, -0.42, z - 0.2)), turn(V(x, -0.42 + ln, z - 0.05))
            p.teeth.append((a, b, tip))
    # jawline: bumpy plates along the outside of the lower jaw, a block at each jaw angle, a chin
    for sx in (1, -1):
        for z, s in ((-0.6, 0.85), (-1.6, 0.75), (-2.5, 0.6)):
            c = turn(V(sx * (0.95 if z > -1 else 0.82 if z > -2 else 0.66), -0.82, z))
            plate(p, c, V(0.32, 0.38 * s, 0.85), V(-JAW_OPEN, sx * 0.08, sx * 0.25))
        plate(p, turn(V(sx * 1.05, -0.95, 0.35)), V(0.45, 0.6, 0.6), V(-JAW_OPEN, sx * 0.15, sx * 0.15))
    plate(p, turn(V(0, -0.85, -3.5)), V(0.55, 0.3, 0.55), V(-JAW_OPEN + 0.25, 0, 0))
    # eyes: glowing white ovals set into sockets framed by plates (brow above, cheekbone below,
    # a plate in front and behind), so they peek out instead of sitting on a flat face
    for sx in (1, -1):
        p.glow.append((V(sx * 1.2, 0.5, -1.38), V(0.14, 0.34, 0.75), V(0, sx * 0.25, sx * 0.2), 0, "oval"))
        plate(p, V(sx * 1.22, 0.2, -1.4), V(0.3, 0.2, 1.05), V(0, sx * 0.25, -sx * 0.35))     # cheekbone / lower lid
        plate(p, V(sx * 1.18, 0.5, -0.82), V(0.32, 0.5, 0.22), V(0, sx * 0.25, 0))           # behind the eye
        plate(p, V(sx * 1.12, 0.46, -1.98), V(0.28, 0.36, 0.2), V(0, sx * 0.3, 0))           # in front
    return p


# ---------------------------------------------------------------------------------------------
# body: chevron roof plates down the column (root space; the column runs along Y at z = Z0)
# ---------------------------------------------------------------------------------------------
Z0 = 0.95
BODY_FRONT = 0.62   # the body's front (against your back), root space z
BODY_RINGS = [  # y, half width, depth (front to back)   from the neck top down to the tail
    (4.35, 1.1, 1.05), (3.55, 1.05, 1.0), (2.75, 1.15, 1.05),
    (1.95, 1.4, 1.25), (1.15, 1.5, 1.3), (0.35, 1.45, 1.3), (-0.45, 1.3, 1.2), (-1.25, 1.1, 1.05),
    (-2.05, 0.9, 0.9), (-2.85, 0.74, 0.77), (-3.65, 0.62, 0.66), (-4.45, 0.52, 0.57), (-5.25, 0.44, 0.5),
    (-6.05, 0.37, 0.44), (-6.85, 0.31, 0.38), (-7.65, 0.25, 0.32), (-8.4, 0.2, 0.27),
]
BODY_V = 0.45       # the plate seams on the back dip into V's this deep
TAIL_TIP = V(0, -10.0, BODY_FRONT + 0.2)
NECK_TOP = V(0, 5.28, BODY_FRONT + 0.6)  # where the head sits (head space origin goes here)


BODY_GROW = 1.2   # the body is this much wider + deeper than the numbers above


def body_ring(y, w, d):
    w, d = w * BODY_GROW, d * BODY_GROW
    zb = BODY_FRONT + d
    right = [(0.6 * w, y, zb), (w, y, BODY_FRONT + 0.55 * d), (0.75 * w, y, BODY_FRONT), ]
    pts = [V(0, y - BODY_V, zb + 0.22)] + [V(*q) for q in right] + [V(0, y, BODY_FRONT)]
    pts += [V(-q[0], q[1], q[2]) for q in reversed(right)]
    return pts


TAIL_FROM = 7   # rings from this one down are the tail: separate segments that swing
NECK_FROM = 3   # rings above this one are the neck: segments that bend so the head can look round
NECK_SKIRT = 0.45   # each neck segment carries on this far down inside the one below (no gaps when bent)
NECK_BEND = [0.2, 0.22, 0.24, 0.34]   # how much of a turn each neck joint + the head take


def _loft_rings(p, rings, tip=None, top=None):
    n = len(rings[0])
    for i in range(len(rings) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]
            p.tri(a, b, c); p.tri(a, c, d)
    for k in range(n):
        k2 = (k + 1) % n
        if tip is not None:
            p.tri(rings[-1][k], rings[-1][k2], tip)
        if top is not None:
            p.tri(rings[0][k2], rings[0][k], top)


def spine(i):
    """the middle of body ring i (root space): where the tail segments bend"""
    y, w, d = BODY_RINGS[i]
    return V(0, y, BODY_FRONT + d * BODY_GROW / 2)


def build_body():
    """the neck + body (one piece, root space); the tail is build_tail()"""
    p = Piece()
    rings = [body_ring(*r) for r in BODY_RINGS[NECK_FROM:TAIL_FROM + 1]]
    y = BODY_RINGS[NECK_FROM][0]
    _loft_rings(p, rings, top=V(0, y + 0.05, spine(NECK_FROM)[2]))
    return p


def build_neck():
    """(joints, segments) like build_tail but going up: joint 1 sits on the body, segment i's
    triangles are relative to joint i, the last joint is where the head sits. Each segment has a
    skirt reaching down inside the one below so bending never opens a gap."""
    joints, segs = [], []
    for i in range(NECK_FROM, 0, -1):
        j = spine(i)
        joints.append(j)
        y, w, d = BODY_RINGS[i]
        skirt = body_ring(y - NECK_SKIRT, w * 0.96, d * 0.96)
        rings = [[q - j for q in r] for r in (skirt, body_ring(*BODY_RINGS[i]), body_ring(*BODY_RINGS[i - 1]))]
        s = Piece()
        top = V(0, BODY_RINGS[0][0] + 0.05, BODY_FRONT + 0.6) - j if i == 1 else None
        _loft_rings(s, rings, top=None)
        if top is not None:
            n = len(rings[-1])
            for k in range(n):
                s.tri(rings[-1][k], rings[-1][(k + 1) % n], top)
        segs.append(s)
    joints.append(NECK_TOP)
    return joints, segs


def bend(look):
    """the neck turned so the head points along `look` (root space; None = straight up): a list
    of (rotation matrix, position) for each joint, the last one the head's"""
    joints, _ = build_neck()
    R_all, theta = np.eye(3), 0.0
    axis = None
    if look is not None:
        u = np.array(look, float) / np.linalg.norm(look)
        c = np.cross([0, 1, 0], u)
        if np.linalg.norm(c) > 1e-6:
            axis = c / np.linalg.norm(c)
            theta = min(math.acos(max(-1, min(1, u[1]))), MAX_BEND)
    out, acc, pos = [], 0.0, joints[0]
    for i, wgt in enumerate(NECK_BEND):
        acc += wgt * theta
        R = axis_angle(axis, acc) if axis is not None else np.eye(3)
        if i > 0:
            pos = pos + out[-1][0] @ (joints[i] - joints[i - 1])
        out.append((R, pos))
    return out


MAX_BEND = 2.3


def axis_angle(a, t):
    x, y, z = a
    c, s, C = math.cos(t), math.sin(t), 1 - math.cos(t)
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def build_tail():
    """(joints, segments): joint i is where segment i hangs from (root space); segment i's
    triangles are relative to its joint. The last joint is the tail tip."""
    rings = [body_ring(*r) for r in BODY_RINGS]
    joints, segs = [], []
    for i in range(TAIL_FROM, len(BODY_RINGS)):
        j = spine(i)
        joints.append(j)
        s = Piece()
        last = i == len(BODY_RINGS) - 1
        if last:
            _loft_rings(s, [[q - j for q in rings[i]]], tip=TAIL_TIP - j)
        else:
            _loft_rings(s, [[q - j for q in rings[i]], [q - j for q in rings[i + 1]]])
        segs.append(s)
    joints.append(TAIL_TIP)
    return joints, segs


# ---------------------------------------------------------------------------------------------
# wing (right; flat in X-Y, origin at the shoulder hinge, +X out). Zigzag top edge, scalloped bottom.
# ---------------------------------------------------------------------------------------------
def _arc(a, b, bow, n=5):
    """a scallop from a to b, bowing in (up) by `bow`"""
    mid = (a + b) / 2 + V(0, bow, 0)
    return [a * (1 - u) ** 2 + mid * 2 * (1 - u) * u + b * u * u for u in (i / n for i in range(1, n))]


WP = {
    "S": V(0, 0, 0), "E": V(0.75, 0.4, 0), "N": V(1.25, -0.2, 0), "K": V(1.85, 0.45, 0), "W": V(8.4, 1.35, 0),
    "Wx": V(9.1, 1.8, 0), "Tb": V(8.0, -3.3, 0), "P1": V(5.6, -3.1, 0), "P": V(3.2, -2.8, 0), "B": V(0.25, -1.7, 0),
    # the root carries on into the body, so there's no gap between the wing and the body
    "R1": V(-0.95, -1.7, 0), "R0": V(-0.95, 0.15, 0),
}
SCALLOP0 = _arc(WP["Tb"], WP["P1"], 0.95)
SCALLOP1 = _arc(WP["P1"], WP["P"], 0.95)
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
HINGE = V(1.45, 1.7, BODY_FRONT + 0.85)   # right wing's hinge, root space (on the body's side)
HINGE_YAW = 0.12
WING_RAISE = 0.22                         # wings tilted up toward the tips


def build_wing():
    p = Piece()
    outline = ([WP[k] for k in WING_OUTLINE] + SCALLOP0 + [WP["P1"]] + SCALLOP1 + [WP["P"]] + SCALLOP2 + [WP["B"], WP["R1"], WP["R0"]])
    for a, b, c in ear_clip(outline):
        p.tri(a, b, c)
    # bones: leading edge, outer edge, and one down to each point between the sections
    for a, b, th in [("S", "E", 0.12), ("E", "N", 0.1), ("N", "K", 0.1), ("K", "W", 0.14), ("W", "Tb", 0.09),
                     ("N", "P", 0.07), ("K", "P1", 0.07), ("B", "S", 0.07), ("W", "Wx", 0.08)]:
        p.edge(WP[a], WP[b], th)
    for chain in ([WP["Tb"]] + SCALLOP0 + [WP["P1"]], [WP["P1"]] + SCALLOP1 + [WP["P"]], [WP["P"]] + SCALLOP2 + [WP["B"], WP["R1"], WP["R0"]]):
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
    for a, b, c in piece.gtris:
        glow.tri(a, b, c)
    for c, s, r, *_ in piece.glow:
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
MOUTH = V(0, -0.6, -1.7)   # where powers come out: back in the throat (head space)


def mouth():
    """the middle of the open mouth in root space (head at rest)"""
    R = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]]) * HEAD_SCALE   # Angles(pi/2, 0, 0)
    return R @ MOUTH + NECK_TOP


def placed(flap=0.0, look=None):
    """(piece, cf in root space) exactly like SpinjitzuDragon places them"""
    out = [(build_body(), T([0, 0, 0]))]
    joints, segs = build_tail()
    for j, s in zip(joints, segs):
        out.append((s, T(j)))
    chain = bend(look)
    _, nsegs = build_neck()
    for (R, pos), s in zip(chain, nsegs):
        out.append((s, (R, pos)))
    R, pos = chain[-1]
    out.append((build_head(), mul((R, pos), ang(HEAD_PITCH, 0, 0), (np.eye(3) * HEAD_SCALE, np.zeros(3)))))
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

    def render(root, views, center, span=17, look=None):
        sc = Scene()
        sc.mesh(character(), root, (70, 80, 70), (0, 0, 0))
        for piece, cf in placed(0.05, look):
            m, hot, glow = to_mesh(piece, G, tube)
            w = mul(root, cf)
            sc.mesh(m, w, (45, 60, 240), (0, 0, 0))
            pass  # (no outlines any more)
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
    # looking (beaming) forward + down, and off to the side
    c = render(hover, [rot(-math.pi / 2, -0.05), rot(math.pi * 0.8, -0.3)], (0, 1.5, 0), span=19, look=(0, -0.5, -1))
    d = render(hover, [rot(math.pi, -0.15), rot(0.4, -0.4)], (0, 1.5, 0), span=19, look=(1, 0.3, -1))
    Image.fromarray(np.concatenate(c + d, 1)).save(os.path.join(out, "bend.png"))
    print("ok")
