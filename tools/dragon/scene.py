# Full dragon preview: stand-in blocky character + head/jaw/neck/wings placed like the game does.
import sys, math, os
import numpy as np
from PIL import Image
import geometry as G
from preview import Scene, rot

def Rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def axis_angle(axis, a):
    axis = axis / np.linalg.norm(axis)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K
def compose(A, B):  # (R,t) * (R,t)
    return (A[0] @ B[0], A[0] @ B[1] + A[1])
def mirror_mesh(m):
    out = G.Mesh()
    F = np.diag([-1, 1, 1.0])
    for p, q, r, s in m.tris:
        out.tri(F @ p, F @ r, F @ q, s)
    for pts, r in zip(m.lines, m.radius):
        out.line([F @ p for p in pts], r)
    return out

def box(m, c, size, shade=1.0):
    c = np.array(c, float); h = np.array(size, float) / 2
    P = [c + h * np.array([x, y, z]) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for a, b, cc, d in quads:
        m.tri(P[a], P[b], P[cc], shade); m.tri(P[a], P[cc], P[d], shade)

def character():
    m = G.Mesh()
    box(m, (0, 0, 0), (2, 2, 1)); box(m, (0, 1.6, 0), (1.2, 1.2, 1.2))
    for s in (1, -1):
        box(m, (1.5 * s, 0, 0), (1, 2, 1), 0.9); box(m, (0.5 * s, -2, 0), (1, 2, 1), 0.8)
    return m

def dragon_pose(fly, flap, fold, jaw):
    """returns list of (mesh, (R,t) in root space, kind)"""
    out = []
    head, hot = G.build_head()
    jawm, jhot = G.build_jaw()
    neck = G.build_neck()
    # head: above the character, snout up when hovering, along the body when flying
    pitch = G.HEAD_PITCH_HOVER + (G.HEAD_PITCH_FLY - G.HEAD_PITCH_HOVER) * fly
    hp = G.HEAD_POS_HOVER + (G.HEAD_POS_FLY - G.HEAD_POS_HOVER) * fly
    H = (Rx(pitch) * G.HEAD_SCALE, hp)
    out += [(head, H, "face"), (hot, H, "hot")]
    Rj = Rx(-jaw)
    J = compose(H, (Rj, G.JAW_HINGE - Rj @ G.JAW_HINGE))
    out += [(jawm, J, "face"), (jhot, J, "hot")]
    # neck: collars along a curve from the back to the back of the head
    p0 = G.NECK_BASE
    p2 = H[0] @ G.V(0, 0.05, 0.55) + H[1]
    p1 = G.V(0, (p0[1] + p2[1]) / 2, max(p0[2], p2[2]) + 0.7)
    n = G.NECK_N
    for i in range(n):
        t = (i + 0.5) / n
        pos = G.bezier(p0, p1, p2, t)
        tan = (p1 - p0) * 2 * (1 - t) + (p2 - p1) * 2 * t
        tan /= np.linalg.norm(tan)
        # collar frame: -Z along the neck toward the head, +Y away from the body (back)
        up = np.cross(np.array([1.0, 0, 0]), tan)
        up /= np.linalg.norm(up)
        back = -tan
        right = np.cross(up, back)
        Rn = np.column_stack([right, up, back])
        k = 1.12 - 0.22 * t
        out.append((neck, (Rn * k, pos), "face_hotlines"))
    # wings
    inner, inner_b, outer, outer_b = G.build_wing()
    for side in (1, -1):
        Wp, F4 = G.WING["W"] * [side, 1, 1], G.WING["F4"] * [side, 1, 1]
        hinge = (Ry(-side * G.HINGE_YAW) @ Rz(side * (flap + G.FLY_DIHEDRAL * fly)), G.V(side * G.HINGE[0], G.HINGE[1], G.HINGE[2]))
        fold_R = axis_angle(F4 - Wp, fold * side)
        el = compose(hinge, (fold_R, Wp - fold_R @ Wp))
        parts = [(inner, hinge, "membrane"), (inner_b, hinge, "hot"), (outer, el, "membrane"), (outer_b, el, "hot")]
        for m, cf, kind in parts:
            if side < 0:
                F = np.diag([-1, 1, 1.0])
                m = mirror_mesh(m)
                cf = (cf[0] @ F @ F, cf[1])  # mirrored mesh already; hinge maths uses side
            out.append((m, cf, kind))
    return out

def to_world(root, cf):
    return compose(root, cf)

def scene(fly, flap, fold, jaw, root, wings=True):
    GREEN, DARK, EDGE, MEMB = (60, 230, 40), (28, 140, 22), (215, 255, 180), (70, 235, 50)
    sc = Scene()
    sc.mesh(character(), root, (60, 170, 70), EDGE)
    for m, cf, kind in dragon_pose(fly, flap, fold, jaw):
        w = to_world(root, cf)
        if kind == "face":
            sc.mesh(m, w, DARK, EDGE)
        elif kind == "face_hotlines":
            sc.mesh(m, w, DARK, EDGE)
        elif kind == "hot" and (wings or m.tris):
            sc.mesh(m, w, EDGE, EDGE, glow=1.0)
        elif kind == "membrane" and wings:
            sc.mesh(m, w, MEMB, EDGE, alpha=0.72)
    return sc

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    hover_root = (np.eye(3), np.zeros(3))
    sc = scene(0, 0.15, 0.05, 0.25, hover_root)
    nw = scene(0, 0.15, 0.05, 0.25, hover_root, wings=False)
    views = [sc.render(rot(math.pi, -0.12), span=19, center=(0, 2.5, 0)),          # front
             sc.render(rot(math.pi * 0.72, -0.2), span=19, center=(0, 2.5, 0)),    # 3/4 front
             sc.render(rot(0.15, -0.3), span=19, center=(0, 2.5, 0)),              # behind (your camera)
             nw.render(rot(-math.pi / 2, -0.05), span=19, center=(0, 2.5, 0))]     # side, no wings
    fly_root = (Rx(-math.radians(75)), np.zeros(3))
    sc2 = scene(1, 0.1, 0.1, 0.18, fly_root)
    views += [sc2.render(rot(-math.pi / 2, -0.1), span=19, center=(0, 1, -2.5)),   # side
              sc2.render(rot(0, -math.pi / 2 + 0.01), span=19, center=(0, 1, -2.5)),  # top
              sc2.render(rot(0.25, -0.35), span=19, center=(0, 1, -2.5)),          # chase cam
              sc2.render(rot(math.pi * 0.8, 0.25), span=19, center=(0, 1, -2.5))]  # front, from below
    row1 = np.concatenate(views[:4], 1); row2 = np.concatenate(views[4:], 1)
    Image.fromarray(np.concatenate([row1, row2], 0)).save(os.path.join(out, "scene.png"))
    print("ok")
