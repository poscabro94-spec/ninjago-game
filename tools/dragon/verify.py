# Re-renders the dragon from the generated DragonModel.luau using the same maths as
# SpinjitzuDragon:_placeMeshDragon (decode, centre offsets, mirroring, hinges, neck curve), to
# check the game data + code match the design previews. Usage: python verify.py out_dir
import re, sys, os, math
import numpy as np
from PIL import Image
from preview import Scene, rot
import geometry as G

SRC = open(os.path.join(os.path.dirname(__file__), "..", "..", "src", "ReplicatedStorage", "DragonModel.luau")).read()

def v3(s):
    return np.array([float(x) for x in re.match(r"Vector3\.new\(([^)]*)\)", s).group(1).split(",")])

def mesh(name, mirror=False):
    m = re.search(name + r' = \{ c = (Vector3\.new\([^)]*\)), n = \d+,\s*v = "([^"]*)",\s*t = "([^"]*)" \}', SRC)
    c = v3(m.group(1)); v = [int(x) for x in m.group(2).split(",")]; t = [int(x) for x in m.group(3).split(",")]
    P = [np.array([(-v[i] if mirror else v[i]) / 1000, v[i + 1] / 1000, v[i + 2] / 1000]) for i in range(0, len(v), 3)]
    out = G.Mesh()
    for i in range(0, len(t), 6):
        a, b, cc = t[i], t[i + 1], t[i + 2]
        sa, sb, sc = t[i + 3] / 20, t[i + 4] / 20, t[i + 5] / 20
        if mirror: b, cc, sb, sc = cc, b, sc, sb
        out.tri(P[a], P[b], P[cc], (sa, sb, sc))
    if mirror: c = np.array([-c[0], c[1], c[2]])
    return out, c

def num(name):
    return float(re.search(r"\n\t" + name + r" = ([-\d.]+)", SRC).group(1))
def vec(name):
    return v3(re.search(r"\n\t" + name + r" = (Vector3\.new\([^)]*\))", SRC).group(1))
def wingpt(name):
    return v3(re.search(r"\n\t\t" + name + r" = (Vector3\.new\([^)]*\))", SRC).group(1))

def Rx(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def angles(x, y, z): return (Rx(x) @ Ry(y) @ Rz(z), np.zeros(3))
def T(p): return (np.eye(3), np.array(p, float))
def mul(*cfs):
    R, t = np.eye(3), np.zeros(3)
    for R2, t2 in cfs:
        R, t = R @ R2, R @ t2 + t
    return R, t
def axis_angle(axis, a):
    axis = axis / np.linalg.norm(axis)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return (np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K, np.zeros(3))
def scaled(m, k):
    out = G.Mesh()
    for p, q, r, s in m.tris: out.tri(p * k, q * k, r * k, s)
    return out
def lerp(a, b, t): return a + (b - a) * t
def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t)

def place(rootCF, flap, fold, fb, effort, beat, t, sc=1.0, ws=1.0):
    items = []  # (mesh, cf, kind)
    hs = sc * num("HeadScale")
    def put(name, k, pieceCF, kind, mirror=False):
        m, c = mesh(name, mirror)
        items.append((scaled(m, k), mul(rootCF, pieceCF, T(c * k)), kind))
    Hinge, yaw, dih = vec("Hinge"), num("HingeYaw"), num("FlyDihedral")
    for side in (1, -1):
        at = lambda v: np.array([v[0] * side, v[1], v[2]]) * ws
        W, F4 = at(wingpt("W")), at(wingpt("F4"))
        hinge = mul(T([side * Hinge[0] * sc, Hinge[1] * sc, Hinge[2] * sc]), angles(0, -side * yaw, 0), angles(0, 0, side * (flap + dih * fb)))
        put("InnerMembrane", ws, hinge, "membrane", side < 0); put("InnerHot", ws, hinge, "hot", side < 0)
        elbow = mul(hinge, T(W), axis_angle(F4 - W, fold * side), T(-W))
        put("OuterMembrane", ws, elbow, "membrane", side < 0); put("OuterHot", ws, elbow, "hot", side < 0)
    pitch = lerp(num("HeadPitchHover"), num("HeadPitchFly"), fb) + math.sin(t * 2) * 0.04 + beat * 0.03 * effort
    headLocal = mul(T(lerp(vec("HeadPosHover"), vec("HeadPosFly"), fb) * sc), angles(pitch, math.sin(t * 0.7) * 0.06, 0))
    put("HeadFace", hs, headLocal, "face"); put("HeadHot", hs, headLocal, "hot")
    roar = smoothstep(0.1, 0.45, t) * (1 - smoothstep(0.9, 1.6, t))
    jaw = lerp(0.2, 0.1, fb) + 0.45 * roar + math.sin(t * 3) * 0.03
    hj = vec("JawHinge") * hs
    jl = mul(headLocal, T(hj), angles(-jaw, 0, 0), T(-hj))
    put("JawFace", hs, jl, "face"); put("JawHot", hs, jl, "hot")
    p0 = vec("NeckBase") * sc
    p2 = headLocal[0] @ (vec("HeadBack") * hs) + headLocal[1]
    p1 = np.array([0, (p0[1] + p2[1]) / 2, max(p0[2], p2[2]) + 0.7 * sc])
    n = int(num("NeckCount"))
    for i in range(1, n + 1):
        f = (i - 0.5) / n
        k = (1.12 - 0.22 * f) * sc
        pos = p0 * (1 - f) ** 2 + p1 * 2 * (1 - f) * f + p2 * f * f
        tan = (p1 - p0) * 2 * (1 - f) + (p2 - p1) * 2 * f; tan /= np.linalg.norm(tan)
        up = np.cross([1.0, 0, 0], tan); up /= np.linalg.norm(up)
        back = -tan
        cf = (np.column_stack([np.cross(up, back), up, back]), pos)
        put("NeckFace", k, cf, "face"); put("NeckHot", k, cf, "hot")
    return items

if __name__ == "__main__":
    from scene import character
    out = sys.argv[1]
    def render_all(items, root, views, center):
        sc = Scene()
        sc.mesh(character(), root, (60, 170, 70), (0, 0, 0))
        for m, cf, kind in items:
            col = {"face": (28, 140, 22), "hot": (215, 255, 180), "membrane": (70, 235, 50)}[kind]
            sc.mesh(m, cf, col, col, alpha=0.7 if kind == "membrane" else 1.0, glow=1.0 if kind == "hot" else 0.0)
        return [sc.render(v, span=19, center=center) for v in views]
    hover = (np.eye(3), np.zeros(3))
    a = render_all(place(hover, 0.15, 0.05, 0, 0.3, 0.3, 3.0), hover,
                   [rot(math.pi * 0.72, -0.2), rot(0.15, -0.3), rot(-math.pi / 2, -0.05)], (0, 2.5, 0))
    fly = (Rx(-math.radians(75)), np.zeros(3))
    b = render_all(place(fly, 0.1, 0.1, 1, 1, 0.5, 3.0), fly,
                   [rot(-math.pi / 2, -0.1), rot(0.25, -0.35), rot(math.pi * 0.8, 0.25)], (0, 1, -2.5))
    Image.fromarray(np.concatenate([np.concatenate(a, 1), np.concatenate(b, 1)], 0)).save(os.path.join(out, "verify.png"))
    print("ok")
