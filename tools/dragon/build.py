# Writes src/ReplicatedStorage/DragonModel.luau: the rocky part-built Rising Dragon (blocks from
# rock.py, wing outline + placement from geometry.py). Run from this folder: python build.py
import os
import geometry as G
import rock as K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "src", "ReplicatedStorage", "DragonModel.luau")


def n(x):
    s = ("%.3f" % x).rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def vec(v):
    return "Vector3.new(%s, %s, %s)" % tuple(n(x) for x in v)


def blocks(name, lst):
    rows = "\n".join('\t\t{ %s, %s, %s, "%s" },' % (vec(b["c"]), vec(b["s"]), vec(b["r"]), b["kind"]) for b in lst)
    return "\t%s = {\n%s\n\t},\n" % (name, rows)


def main():
    P = G.WING
    pts = "\n".join("\t\t%s = %s," % (k, vec(v)) for k, v in P.items())
    src = f'''-- DragonModel v3.0  (ModuleScript in ReplicatedStorage) -- GENERATED, don't edit by hand:
-- change tools/dragon/rock.py (blocks) / geometry.py (wings, placement) and run build.py.
-- The Rising Dragon, built from plain parts by SpinjitzuDragon: chunky glowing blocks with bright
-- edges (rocky, like the show's energy dragons) and a white glow inside. Studs at DragonScale 1.
--   blocks: {{ centre, size, tilt (CFrame.Angles), kind }} kind = "plate" (green, see-through, glowing
--   edges) | "core" (white glow inside) | "eye"
--   Head space: origin at the neck joint, -Z = snout, +Y = up (shown at HeadScale).
--   Neck plate: -Z toward the head, +Y away from the body. Chest: root space (+Z = behind you).
--   Wing (right; the left is the mirror): origin at the shoulder hinge, +X = out, +Y = up, flat.
--   Laid out spread (flying); hovering it's raised (WingRaise) and the hand (W, T, n1, P1) turns
--   down about the wrist (HandFold).

return {{
{blocks("Head", K.HEAD)}{blocks("Jaw", K.JAW)}{blocks("Neck", K.NECK)}{blocks("Chest", K.CHEST)}
	HeadScale = {G.HEAD_SCALE},
	HeadPosHover = {vec(G.HEAD_POS_HOVER)}, -- neck joint of the head, root space
	HeadPosFly = {vec(G.HEAD_POS_FLY)},
	HeadPitchHover = {G.HEAD_PITCH_HOVER}, -- snout raised (radians)
	HeadPitchFly = {G.HEAD_PITCH_FLY},
	HeadBack = {vec(G.V(0, 0.2, 0.7))}, -- where the neck meets the head (head space)
	JawHinge = {vec(K.JAW_HINGE)},
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
	-- membrane: fans from the wrist (arm part / hand part)
	InnerFan = {{ "P1", "n2", "P2", "n3", "P3", "B", "S" }},
	OuterFan = {{ "T", "n1", "P1" }},
	-- glowing bones + edges: piece, from, to, thickness
	Bones = {{
		{{ "Inner", "S", "W", 0.34 }}, {{ "Inner", "W", "P2", 0.15 }},
		{{ "Inner", "P1", "n2", 0.12 }}, {{ "Inner", "n2", "P2", 0.12 }}, {{ "Inner", "P2", "n3", 0.12 }},
		{{ "Inner", "n3", "P3", 0.12 }}, {{ "Inner", "P3", "B", 0.12 }}, {{ "Inner", "B", "S", 0.14 }},
		{{ "Outer", "W", "T", 0.28 }}, {{ "Outer", "W", "P1", 0.17 }},
		{{ "Outer", "T", "n1", 0.12 }}, {{ "Outer", "n1", "P1", 0.12 }},
	}},
	-- flat spikes: piece, base, tip, base width
	Spikes = {{ {{ "Outer", "W", "C", 0.4 }}, {{ "Outer", "T", "X", 0.35 }} }},
	-- where the elemental cloud pours off / energy drips off: piece, point
	WingCloud = {{ {{ "Outer", "T" }}, {{ "Outer", "n1" }}, {{ "Outer", "P1" }}, {{ "Inner", "n2" }}, {{ "Inner", "P2" }}, {{ "Inner", "P3" }}, {{ "Inner", "B" }} }},
	WingDrips = {{ {{ "Outer", "T" }}, {{ "Outer", "P1" }}, {{ "Inner", "P2" }}, {{ "Inner", "P3" }} }},
}}
'''
    with open(OUT, "w") as f:
        f.write(src)
    print("wrote", os.path.normpath(OUT), len(src) // 1024, "KB")


if __name__ == "__main__":
    main()
