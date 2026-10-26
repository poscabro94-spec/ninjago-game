# Renders the whole part-built dragon on a stand-in character, placed with the same steps as
# SpinjitzuDragon:_placeBody (hovering + flying). Usage: python rockscene.py out_dir
import sys, os, math
import numpy as np
from PIL import Image
import geometry as G
import rock as K
from preview import Scene, rot

def Rx(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def ang(x, y, z): return (Rx(x) @ Ry(y) @ Rz(z), np.zeros(3))
def T(p): return (np.eye(3), np.array(p, float))
def mul(*cfs):
    R, t = np.eye(3), np.zeros(3)
    for R2, t2 in cfs: R, t = R @ R2, R @ t2 + t
    return R, t
def lerp(a, b, t): return a + (b - a) * t

def scaled_blocks(lst, k):
    return [dict(b, c=b["c"] * k, s=b["s"] * k) for b in lst]

def wing_mesh():
    P = G.WING
    inner, outer = G.Mesh(), G.Mesh()
    on = {"Inner": inner, "Outer": outer}
    for piece, names in [("Inner", ["P1", "n2", "P2", "n3", "P3", "B", "S"]), ("Outer", ["T", "n1", "P1"])]:
        for a, b in zip(names[:-1], names[1:]):
            on[piece].tri(P["W"], P[a], P[b], 1.0)
    bones = [("Inner", "S", "W", .34), ("Inner", "W", "P2", .15), ("Inner", "P1", "n2", .12), ("Inner", "n2", "P2", .12),
             ("Inner", "P2", "n3", .12), ("Inner", "n3", "P3", .12), ("Inner", "P3", "B", .12), ("Inner", "B", "S", .14),
             ("Outer", "W", "T", .28), ("Outer", "W", "P1", .17), ("Outer", "T", "n1", .12), ("Outer", "n1", "P1", .12),
             ("Outer", "W", "C", .1), ("Outer", "T", "X", .1)]
    for piece, a, b, th in bones:
        on[piece].line([P[a], P[b]], th / 2)
    return inner, outer

def character():
    from preview import tube  # noqa
    m = G.Mesh()
    def box(c, size):
        b = K.B(c, size); P = K.corners(b)
        for a, bb, cc, d in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
            m.tri(P[a], P[bb], P[cc]); m.tri(P[a], P[cc], P[d])
    box((0, 0, 0), (2, 2, 1)); box((0, 1.6, 0), (1.2, 1.2, 1.2))
    for s in (1, -1): box((1.5 * s, 0, 0), (1, 2, 1)); box((0.5 * s, -2, 0), (1, 2, 1))
    return m

def place(rootCF, fb, flap=0.0, fold=0.0, t=3.0, sc=1.0):
    items = []  # (mesh, cf, kind)
    hs = sc * G.HEAD_SCALE
    def blocks(lst, k, cf):
        m, glow = K.to_mesh(scaled_blocks(lst, k), G)
        items.append((m, mul(rootCF, cf), "plate")); items.append((glow, mul(rootCF, cf), "core"))
    blocks(K.CHEST, sc, T([0, 0, 0]))
    raise_ = lerp(G.WING_RAISE_HOVER, G.WING_RAISE_FLY, fb) + flap
    hand = min(0, lerp(G.HAND_FOLD_HOVER, G.HAND_FOLD_FLY, fb) - fold)
    inner, outer = wing_mesh()
    for side in (1, -1):
        W = np.array([G.WING["W"][0] * side, G.WING["W"][1], 0])
        hinge = mul(T([side * G.HINGE[0], G.HINGE[1], G.HINGE[2]]), ang(0, -side * G.HINGE_YAW, 0), ang(0, 0, side * raise_))
        wrist = mul(hinge, T(W), ang(0, 0, side * hand), T(-W))
        flip = ang(0, math.pi, 0) if side < 0 else T([0, 0, 0])
        items.append((inner, mul(rootCF, hinge, flip), "wing")); items.append((outer, mul(rootCF, wrist, flip), "wing"))
    pitch = lerp(G.HEAD_PITCH_HOVER, G.HEAD_PITCH_FLY, fb)
    headLocal = mul(T(lerp(G.HEAD_POS_HOVER, G.HEAD_POS_FLY, fb) * sc), ang(pitch, 0, 0))
    blocks(K.HEAD, hs, headLocal)
    jh = np.array(K.JAW_HINGE) * hs
    blocks(K.JAW, hs, mul(headLocal, T(jh), ang(-0.22, 0, 0), T(-jh)))
    p0 = G.NECK_BASE * sc
    p2 = headLocal[0] @ (np.array([0, 0.2, 0.7]) * hs) + headLocal[1]
    p1 = np.array([0, (p0[1] + p2[1]) / 2, max(p0[2], p2[2]) + 0.6 * sc])
    n = G.NECK_N
    for i in range(1, n + 1):
        f = (i - 0.5) / n
        pos = p0 * (1 - f) ** 2 + p1 * 2 * (1 - f) * f + p2 * f * f
        tan = (p1 - p0) * 2 * (1 - f) + (p2 - p1) * 2 * f; tan /= np.linalg.norm(tan)
        up = np.cross([1.0, 0, 0], tan); up /= np.linalg.norm(up)
        back = -tan
        blocks(K.NECK, (1.1 - 0.2 * f) * sc, (np.column_stack([np.cross(up, back), up, back]), pos))
    return items

def render(items, root, views, center):
    sc = Scene()
    sc.mesh(character(), root, (90, 90, 100), (0, 0, 0))
    for m, cf, kind in items:
        if kind == "plate": sc.mesh(m, cf, (60, 220, 40), (190, 255, 160))
        elif kind == "core": sc.mesh(m, cf, (255, 255, 255), (0, 0, 0), glow=1.0)
        else: sc.mesh(m, cf, (60, 230, 40), (190, 255, 160), alpha=0.75)
    return [sc.render(v, span=20, center=center) for v in views]

if __name__ == "__main__":
    out = sys.argv[1]
    hover = (np.eye(3), np.zeros(3))
    a = render(place(hover, 0), hover, [rot(math.pi, -0.25), rot(0.2, -0.3), rot(-math.pi / 2, -0.05)], (0, 2.8, 0))
    fly = (Rx(-math.radians(75)), np.zeros(3))
    b = render(place(fly, 1), fly, [rot(-math.pi / 2 - 0.5, -0.3), rot(math.pi * 0.85, -0.6), rot(0.2, -0.45)], (0, 1, -3))
    Image.fromarray(np.concatenate([np.concatenate(a, 1), np.concatenate(b, 1)], 0)).save(os.path.join(out, "rockscene.png"))
    print("ok")
