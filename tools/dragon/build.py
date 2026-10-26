# Writes src/ReplicatedStorage/DragonModel.luau from facet.py (the Rising Dragon: faceted head,
# chevron body column, flat wings). Run from this folder: python build.py
import os
import facet as F

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "src", "ReplicatedStorage", "DragonModel.luau")


def n(x):
    s = ("%.3f" % x).rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def vec(v):
    return "Vector3.new(%s, %s, %s)" % tuple(n(x) for x in v)


def nums(vals, per_line):
    vals = [n(v) for v in vals]
    lines = [", ".join(vals[i:i + per_line]) for i in range(0, len(vals), per_line)]
    return "\n".join("\t\t\t" + l + "," for l in lines)


def piece(name, p):
    tris = [x for a, b, c in p.tris for v in (a, b, c) for x in v]
    edges = [x for a, b, th in p.edges for x in (*a, *b, th)]
    glow = "\n".join("\t\t\t{ %s, %s, %s, %s }," % (vec(c), vec(s), vec(r), n(tr)) for c, s, r, tr in p.glow)
    return (f"\t{name} = {{\n\t\ttris = {{ -- x, y, z of each corner, 3 corners a triangle\n{nums(tris, 9)}\n\t\t}},\n"
            f"\t\tedges = {{ -- from x, y, z, to x, y, z, thickness\n{nums(edges, 7)}\n\t\t}},\n"
            f"\t\tglow = {{ -- centre, size, tilt, transparency\n{glow}\n\t\t}},\n\t}},\n")


def main():
    W = F.WP
    pts = "\n".join("\t\t%s = %s," % (k, vec(v)) for k, v in W.items())
    src = f'''-- DragonModel v4.0  (ModuleScript in ReplicatedStorage) -- GENERATED, don't edit by hand:
-- change tools/dragon/facet.py and run build.py (python facet.py out renders it).
-- The Rising Dragon, built from plain parts by SpinjitzuDragon: flat see-through glowing facets
-- with thick bright outlines, one tall column behind you. Studs at DragonScale 1.
--   Head: head space (origin at the neck joint, -Z = snout), turned to point up the column.
--   Body: neck + body + tail chevron plates, root space (+Z = behind you, the column runs up Y).
--   Wing: the right wing, flat in X-Y, origin at its hinge, +X out (the left one is the mirror).

return {{
{piece("Head", F.build_head())}{piece("Body", F.build_body())}{piece("Wing", F.build_wing())}
	NeckTop = {vec(F.NECK_TOP)}, -- where the head sits (root space)
	HeadPitch = {n(F.HEAD_PITCH)}, -- snout turned up the column
	HeadScale = {F.HEAD_SCALE},
	TailTip = {vec(F.TAIL_TIP)},
	Hinge = {vec(F.HINGE)}, -- right wing's hinge (root space)
	HingeYaw = {F.HINGE_YAW}, -- wings swept back a little
	WingPoints = {{
{pts}
	}},
	WingCloud = {{ "W", "Tb", "s1", "P", "s2", "B" }}, -- the elemental cloud pours off these
	WingDrips = {{ "W", "Tb", "P", "s2" }}, -- long drips of energy hang off these
}}
'''
    with open(OUT, "w") as f:
        f.write(src)
    print("wrote", os.path.normpath(OUT), len(src) // 1024, "KB")


if __name__ == "__main__":
    main()
