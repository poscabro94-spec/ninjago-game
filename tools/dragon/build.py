# Writes src/ReplicatedStorage/DragonModel.luau from geometry.py (run from this folder:
# python build.py). Every mesh is centred on its own bounding box, so its part's centre is the
# mesh's centre whichever way Roblox places EditableMesh origins.
import os
import numpy as np
import geometry as G
from preview import tube

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "src", "ReplicatedStorage", "DragonModel.luau")


def seams(m):
    """every seam line of a mesh as a strip (its faces stay in the face mesh)"""
    tris = []
    for pts, rad in zip(m.lines, m.radius):
        for p, q, r in tube(pts, rad):
            tris.append((p, q, r, (1.0, 1.0, 1.0)))
    return tris


def encode(tris):
    verts, index, out_t = [], {}, []
    pts = np.array([p for t in tris for p in t[:3]])
    lo, hi = pts.min(0), pts.max(0)
    c = (lo + hi) / 2
    for p, q, r, s in tris:
        ids = []
        for v in (p, q, r):
            key = tuple(int(round(x * 1000)) for x in (v - c))
            if key not in index:
                index[key] = len(verts)
                verts.append(key)
            ids.append(index[key])
        if len(set(ids)) < 3:
            continue
        out_t += ids + [int(round(min(max(x, 0), 1) * 20)) for x in s]
    vs = ",".join(str(n) for k in verts for n in k)
    ts = ",".join(str(n) for n in out_t)
    return c, vs, ts, len(out_t) // 6


def vec(v):
    return "Vector3.new(%s, %s, %s)" % tuple(("%.3f" % x).rstrip("0").rstrip(".") or "0" for x in v)


def mesh_entry(name, tris, lines):
    c, vs, ts, n = encode(tris)
    lines.append('\t%s = { c = %s, n = %d,\n\t\tv = "%s",\n\t\tt = "%s" },' % (name, vec(c), n, vs, ts))
    return n


def main():
    head, head_hot = G.build_head()
    jaw, jaw_hot = G.build_jaw()
    neck = G.build_neck()
    chest = G.build_chest()
    inner, inner_b, outer, outer_b = G.build_wing()
    out = []
    total = 0
    total += mesh_entry("HeadFace", head.tris, out)
    total += mesh_entry("HeadHot", seams(head) + head_hot.tris, out)
    total += mesh_entry("JawFace", jaw.tris, out)
    total += mesh_entry("JawHot", seams(jaw) + jaw_hot.tris, out)
    total += mesh_entry("NeckFace", neck.tris, out)
    total += mesh_entry("NeckHot", seams(neck), out)
    total += mesh_entry("ChestFace", chest.tris, out)
    total += mesh_entry("ChestHot", seams(chest), out)
    total += mesh_entry("InnerMembrane", inner.tris, out)
    total += mesh_entry("InnerHot", seams(inner_b) + inner_b.tris, out)
    total += mesh_entry("OuterMembrane", outer.tris, out)
    total += mesh_entry("OuterHot", seams(outer_b) + outer_b.tris, out)

    P = G.WING
    pts = "\n".join("\t\t%s = %s," % (k, vec(v)) for k, v in P.items())
    halo = [
        ("Inner", [P["S"], P["W"]], 0.65), ("Inner", [P["W"], P["P2"]], 0.3),
        ("Inner", [P["P1"], P["n2"], P["P2"], P["n3"], P["P3"], P["B"]], 0.3),
        ("Outer", [P["W"], P["T"]], 0.55), ("Outer", [P["W"], P["P1"]], 0.35), ("Outer", [P["T"], P["n1"], P["P1"]], 0.3),
    ]
    halo_s = "\n".join('\t\t{ "%s", %.2f, { %s } },' % (pc, w, ", ".join(vec(p) for p in line)) for pc, line, w in halo)
    cloud = [("Outer", P["T"]), ("Outer", P["n1"]), ("Outer", P["P1"]), ("Inner", P["n2"]), ("Inner", P["P2"]),
             ("Inner", P["n3"]), ("Inner", P["P3"]), ("Inner", P["B"])]
    cloud_s = "\n".join('\t\t{ "%s", %s },' % (pc, vec(p)) for pc, p in cloud)
    drips = [("Outer", P["T"]), ("Outer", P["P1"]), ("Inner", P["P2"]), ("Inner", P["P3"])]
    drip_s = "\n".join('\t\t{ "%s", %s },' % (pc, vec(p)) for pc, p in drips)

    src = f'''-- DragonModel v2.0  (ModuleScript in ReplicatedStorage) -- GENERATED, don't edit by hand:
-- change tools/dragon/geometry.py and run tools/dragon/build.py (scene.py / verify.py render it).
-- The Rising Dragon's meshes (SpinjitzuDragon builds them with EditableMesh on each client) and
-- where everything goes. Studs at DragonScale 1.
--   meshes: c = the mesh's centre in its piece's space, v = vertices (thousandths of a stud,
--   relative to c), t = triangles (3 vertex indices from 0 + 3 corner shades 0..20)
--   Head space: origin at the neck joint, -Z = snout, +Y = up (shown at HeadScale).
--   Chest: root space (+Z = behind you).
--   Wing space (right wing): origin at the shoulder hinge, +X = out, +Y = up, flat in X-Y and
--   symmetric front/back, so the left wing is the same mesh turned round. Laid out spread (flying);
--   hovering it's raised (WingRaise) and the hand (W, T, n1, P1) turns down about the wrist (HandFold).
--   Neck plate space: -Z toward the head, +Y away from the body.
-- {total} triangles.

return {{
{chr(10).join(out)}

	HeadScale = {G.HEAD_SCALE},
	HeadPosHover = {vec(G.HEAD_POS_HOVER)}, -- neck joint of the head, root space
	HeadPosFly = {vec(G.HEAD_POS_FLY)},
	HeadPitchHover = {G.HEAD_PITCH_HOVER}, -- snout raised (radians)
	HeadPitchFly = {G.HEAD_PITCH_FLY},
	HeadBack = {vec(G.V(0, 0.05, 0.6))}, -- where the neck meets the head (head space)
	JawHinge = {vec(G.JAW_HINGE)},
	NeckBase = {vec(G.NECK_BASE)}, -- where the neck leaves the chest (root space)
	NeckCount = {G.NECK_N},
	Hinge = {vec(G.HINGE)}, -- right wing's shoulder hinge (root space)
	HingeYaw = {G.HINGE_YAW}, -- wings swept back
	WingRaiseHover = {G.WING_RAISE_HOVER}, -- whole wing raised (radians)
	WingRaiseFly = {G.WING_RAISE_FLY},
	HandFoldHover = {G.HAND_FOLD_HOVER}, -- hand turned about the wrist (negative = down)
	HandFoldFly = {G.HAND_FOLD_FLY},
	Wing = {{
{pts}
	}},
	-- soft glow along the bones + trailing edge: piece, width, points
	WingHalo = {{
{halo_s}
	}},
	-- where the elemental cloud pours off: piece, point
	WingCloud = {{
{cloud_s}
	}},
	-- energy dripping off the trailing edge: piece, point
	WingDrips = {{
{drip_s}
	}},
}}
'''
    with open(OUT, "w") as f:
        f.write(src)
    print("wrote", os.path.normpath(OUT), total, "triangles,", len(src) // 1024, "KB")


if __name__ == "__main__":
    main()
