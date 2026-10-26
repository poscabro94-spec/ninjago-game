# The rocky part-built dragon: every piece is a list of blocks (centre, size, tilt) that the game
# turns into Neon parts with glowing edges. build_rock.py writes them into DragonModel.luau;
# python rock.py out renders the head.
import math, sys, os
import numpy as np

def B(c, s, r=(0, 0, 0), kind="plate"):
    return {"c": np.array(c, float), "s": np.array(s, float), "r": np.array(r, float), "kind": kind}

def mirror(blocks):
    out = []
    for b in blocks:
        out.append(b)
        if abs(b["c"][0]) > 1e-6:
            m = dict(b); m["c"] = b["c"] * [-1, 1, 1]; m["r"] = b["r"] * [1, -1, -1]
            out.append(m)
    return out

# head space: origin at the neck joint, -Z = snout, +Y = up
HEAD = mirror([
    B((0, 0.75, -0.35), (1.9, 0.85, 1.9), (0.08, 0, 0)),          # skull top
    B((0, 0.2, 0.5), (1.6, 1.2, 0.9), (-0.22, 0, 0)),             # back of the skull
    B((0.82, 0.1, -0.7), (0.6, 1.0, 1.7), (0, 0.1, -0.12)),       # cheeks
    B((0.58, 1.12, -1.35), (0.75, 0.42, 1.2), (0.18, 0.18, -0.28)),  # brows
    B((0, 0.62, -2.25), (1.4, 0.72, 1.6), (0.12, 0, 0)),          # upper snout
    B((0, 0.48, -3.55), (1.15, 0.62, 1.3), (0.05, 0, 0)),         # snout
    B((0, 0.32, -4.4), (0.95, 0.52, 0.6), (-0.18, 0, 0)),         # nose
    B((0.52, 0.02, -2.85), (0.42, 0.55, 2.6), (0, 0.05, 0.04)),   # upper lips
    B((0, 1.2, 0.35), (1.0, 0.45, 1.0), (-0.55, 0, 0)),           # back plates (chunky, no spikes)
    B((0.62, 0.98, 0.55), (0.5, 0.42, 0.85), (-0.45, 0.3, -0.3)),
    B((0, 0.3, -2.0), (0.9, 0.55, 3.2), (0, 0, 0), "core"),       # the white glow inside
    B((0.93, 0.62, -1.55), (0.12, 0.16, 0.55), (0, 0, 0.2), "eye"),
])
# lower jaw (closed; it hinges at JAW_HINGE)
JAW = [
    B((0, -0.82, -0.45), (1.5, 0.5, 1.6), (0.1, 0, 0)),
    B((0, -0.78, -2.05), (1.2, 0.42, 1.8), (0, 0, 0)),
    B((0, -0.68, -3.45), (0.95, 0.38, 1.4), (-0.04, 0, 0)),
    B((0, -0.6, -4.25), (0.72, 0.32, 0.5), (-0.1, 0, 0)),
    B((0, -0.5, -2.4), (0.85, 0.1, 3.2), (0, 0, 0), "core"),      # glowing mouth
]
JAW_HINGE = (0, -0.55, 0.1)
# one neck plate: -Z toward the head, +Y away from the body
NECK = [
    B((0, 0, 0), (1.5, 1.05, 1.0), (0, 0, 0)),
    B((0, 0.62, 0.1), (0.9, 0.3, 0.8), (-0.25, 0, 0)),
]
# chest behind your back (root space, +Z = behind you)
CHEST = mirror([
    B((0, 1.2, 0.95), (2.3, 0.75, 0.8), (0.1, 0, 0)),
    B((0, 0.3, 1.0), (2.6, 0.85, 0.85), (0, 0, 0)),
    B((0, -0.65, 0.9), (2.1, 0.8, 0.75), (-0.1, 0, 0)),
    B((0.95, 0.75, 1.1), (0.7, 0.9, 0.6), (0, -0.2, 0.15)),
])

def corners(b):
    cx, cy, cz = b["r"]
    def R(a, axis):
        c, s = math.cos(a), math.sin(a)
        if axis == 0: return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
        if axis == 1: return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    M = R(cx, 0) @ R(cy, 1) @ R(cz, 2)   # CFrame.Angles(x, y, z)
    h = b["s"] / 2
    return [b["c"] + M @ (h * np.array([x, y, z])) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]

def to_mesh(blocks, G):
    """faces + edge lines like the game shows them (for the preview)"""
    m, glow = G.Mesh(), G.Mesh()
    for b in blocks:
        P = corners(b)
        quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        tgt = glow if b["kind"] in ("core", "eye") else m
        for a, bb, c, d in quads:
            tgt.tri(P[a], P[bb], P[c], 1.0); tgt.tri(P[a], P[c], P[d], 1.0)
        if b["kind"] == "plate":
            for i, j in [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]:
                m.line([P[i], P[j]], 0.035)
    return m, glow

if __name__ == "__main__":
    import geometry as G
    from preview import Scene, rot
    from PIL import Image
    out = sys.argv[1]
    sc = Scene()
    head, hglow = to_mesh(HEAD, G)
    jaw, jglow = to_mesh(JAW, G)
    a = 0.22
    Rj = np.array([[1, 0, 0], [0, math.cos(a), math.sin(a)], [0, -math.sin(a), math.cos(a)]])
    h = np.array(JAW_HINGE)
    GREEN, EDGE = (60, 220, 40), (190, 255, 160)
    sc.mesh(head, (np.eye(3), np.zeros(3)), GREEN, EDGE)
    sc.mesh(hglow, (np.eye(3), np.zeros(3)), (255, 255, 255), EDGE, glow=1.0)
    sc.mesh(jaw, (Rj, h - Rj @ h), GREEN, EDGE)
    sc.mesh(jglow, (Rj, h - Rj @ h), (255, 255, 255), EDGE, glow=1.0)
    views = [rot(-math.pi / 2, -0.1), rot(-0.8, 0.3), rot(math.pi, 0.15), rot(0.3, -0.6)]
    imgs = [sc.render(v, span=7.5, center=(0, 0.2, -1.8)) for v in views]
    Image.fromarray(np.concatenate([np.concatenate(imgs[:2], 1), np.concatenate(imgs[2:], 1)], 0)).save(os.path.join(out, "rock.png"))
    print("ok")
