-- DragonModel v3.0  (ModuleScript in ReplicatedStorage) -- GENERATED, don't edit by hand:
-- change tools/dragon/rock.py (blocks) / geometry.py (wings, placement) and run build.py.
-- The Rising Dragon, built from plain parts by SpinjitzuDragon: chunky glowing blocks with bright
-- edges (rocky, like the show's energy dragons) and a white glow inside. Studs at DragonScale 1.
--   blocks: { centre, size, tilt (CFrame.Angles), kind } kind = "plate" (green, see-through, glowing
--   edges) | "core" (white glow inside) | "eye"
--   Head space: origin at the neck joint, -Z = snout, +Y = up (shown at HeadScale).
--   Neck plate: -Z toward the head, +Y away from the body. Chest: root space (+Z = behind you).
--   Wing (right; the left is the mirror): origin at the shoulder hinge, +X = out, +Y = up, flat.
--   Laid out spread (flying); hovering it's raised (WingRaise) and the hand (W, T, n1, P1) turns
--   down about the wrist (HandFold).

return {
	Head = {
		{ Vector3.new(0, 0.75, -0.35), Vector3.new(1.9, 0.85, 1.9), Vector3.new(0.08, 0, 0), "plate" },
		{ Vector3.new(0, 0.2, 0.5), Vector3.new(1.6, 1.2, 0.9), Vector3.new(-0.22, 0, 0), "plate" },
		{ Vector3.new(0.82, 0.1, -0.7), Vector3.new(0.6, 1, 1.7), Vector3.new(0, 0.1, -0.12), "plate" },
		{ Vector3.new(-0.82, 0.1, -0.7), Vector3.new(0.6, 1, 1.7), Vector3.new(0, -0.1, 0.12), "plate" },
		{ Vector3.new(0.58, 1.12, -1.35), Vector3.new(0.75, 0.42, 1.2), Vector3.new(0.18, 0.18, -0.28), "plate" },
		{ Vector3.new(-0.58, 1.12, -1.35), Vector3.new(0.75, 0.42, 1.2), Vector3.new(0.18, -0.18, 0.28), "plate" },
		{ Vector3.new(0, 0.62, -2.25), Vector3.new(1.4, 0.72, 1.6), Vector3.new(0.12, 0, 0), "plate" },
		{ Vector3.new(0, 0.48, -3.55), Vector3.new(1.15, 0.62, 1.3), Vector3.new(0.05, 0, 0), "plate" },
		{ Vector3.new(0, 0.32, -4.4), Vector3.new(0.95, 0.52, 0.6), Vector3.new(-0.18, 0, 0), "plate" },
		{ Vector3.new(0.52, 0.02, -2.85), Vector3.new(0.42, 0.55, 2.6), Vector3.new(0, 0.05, 0.04), "plate" },
		{ Vector3.new(-0.52, 0.02, -2.85), Vector3.new(0.42, 0.55, 2.6), Vector3.new(0, -0.05, -0.04), "plate" },
		{ Vector3.new(0, 1.2, 0.35), Vector3.new(1, 0.45, 1), Vector3.new(-0.55, 0, 0), "plate" },
		{ Vector3.new(0.62, 0.98, 0.55), Vector3.new(0.5, 0.42, 0.85), Vector3.new(-0.45, 0.3, -0.3), "plate" },
		{ Vector3.new(-0.62, 0.98, 0.55), Vector3.new(0.5, 0.42, 0.85), Vector3.new(-0.45, -0.3, 0.3), "plate" },
		{ Vector3.new(0, 0.3, -2), Vector3.new(0.9, 0.55, 3.2), Vector3.new(0, 0, 0), "core" },
		{ Vector3.new(0.93, 0.62, -1.55), Vector3.new(0.12, 0.16, 0.55), Vector3.new(0, 0, 0.2), "eye" },
		{ Vector3.new(-0.93, 0.62, -1.55), Vector3.new(0.12, 0.16, 0.55), Vector3.new(0, 0, -0.2), "eye" },
	},
	Jaw = {
		{ Vector3.new(0, -0.82, -0.45), Vector3.new(1.5, 0.5, 1.6), Vector3.new(0.1, 0, 0), "plate" },
		{ Vector3.new(0, -0.78, -2.05), Vector3.new(1.2, 0.42, 1.8), Vector3.new(0, 0, 0), "plate" },
		{ Vector3.new(0, -0.68, -3.45), Vector3.new(0.95, 0.38, 1.4), Vector3.new(-0.04, 0, 0), "plate" },
		{ Vector3.new(0, -0.6, -4.25), Vector3.new(0.72, 0.32, 0.5), Vector3.new(-0.1, 0, 0), "plate" },
		{ Vector3.new(0, -0.5, -2.4), Vector3.new(0.85, 0.1, 3.2), Vector3.new(0, 0, 0), "core" },
	},
	Neck = {
		{ Vector3.new(0, 0, 0), Vector3.new(1.5, 1.05, 1), Vector3.new(0, 0, 0), "plate" },
		{ Vector3.new(0, 0.62, 0.1), Vector3.new(0.9, 0.3, 0.8), Vector3.new(-0.25, 0, 0), "plate" },
	},
	Chest = {
		{ Vector3.new(0, 1.2, 0.95), Vector3.new(2.3, 0.75, 0.8), Vector3.new(0.1, 0, 0), "plate" },
		{ Vector3.new(0, 0.3, 1), Vector3.new(2.6, 0.85, 0.85), Vector3.new(0, 0, 0), "plate" },
		{ Vector3.new(0, -0.65, 0.9), Vector3.new(2.1, 0.8, 0.75), Vector3.new(-0.1, 0, 0), "plate" },
		{ Vector3.new(0.95, 0.75, 1.1), Vector3.new(0.7, 0.9, 0.6), Vector3.new(0, -0.2, 0.15), "plate" },
		{ Vector3.new(-0.95, 0.75, 1.1), Vector3.new(0.7, 0.9, 0.6), Vector3.new(0, 0.2, -0.15), "plate" },
	},

	HeadScale = 1.25,
	HeadPosHover = Vector3.new(0, 4.6, 1.3), -- neck joint of the head, root space
	HeadPosFly = Vector3.new(0, 4.4, 0.9),
	HeadPitchHover = 0.75, -- snout raised (radians)
	HeadPitchFly = 1.5,
	HeadBack = Vector3.new(0, 0.2, 0.7), -- where the neck meets the head (head space)
	JawHinge = Vector3.new(0, -0.55, 0.1),
	NeckBase = Vector3.new(0, 1.4, 1), -- where the neck leaves the chest (root space)
	NeckCount = 5,
	Hinge = Vector3.new(0.95, 1.25, 0.95), -- right wing's shoulder hinge (root space)
	HingeYaw = 0.18, -- wings swept back
	WingRaiseHover = 1.02, -- whole wing raised (radians)
	WingRaiseFly = 0.12,
	HandFoldHover = -1.25, -- hand turned about the wrist (negative = down)
	HandFoldFly = -0.1,
	Wing = {
		S = Vector3.new(0, 0, 0),
		W = Vector3.new(5.52, 1.08, 0),
		C = Vector3.new(6.6, 2.76, 0),
		T = Vector3.new(11.28, -0.72, 0),
		X = Vector3.new(14.16, -2.28, 0),
		n1 = Vector3.new(9.24, -1.68, 0),
		P1 = Vector3.new(8.52, -3.36, 0),
		n2 = Vector3.new(6.72, -2.4, 0),
		P2 = Vector3.new(5.52, -4.2, 0),
		n3 = Vector3.new(3.72, -2.88, 0),
		P3 = Vector3.new(2.28, -4.08, 0),
		B = Vector3.new(0.36, -2.52, 0),
	},
	-- membrane: fans from the wrist (arm part / hand part)
	InnerFan = { "P1", "n2", "P2", "n3", "P3", "B", "S" },
	OuterFan = { "T", "n1", "P1" },
	-- glowing bones + edges: piece, from, to, thickness
	Bones = {
		{ "Inner", "S", "W", 0.34 }, { "Inner", "W", "P2", 0.15 },
		{ "Inner", "P1", "n2", 0.12 }, { "Inner", "n2", "P2", 0.12 }, { "Inner", "P2", "n3", 0.12 },
		{ "Inner", "n3", "P3", 0.12 }, { "Inner", "P3", "B", 0.12 }, { "Inner", "B", "S", 0.14 },
		{ "Outer", "W", "T", 0.28 }, { "Outer", "W", "P1", 0.17 },
		{ "Outer", "T", "n1", 0.12 }, { "Outer", "n1", "P1", 0.12 },
	},
	-- flat spikes: piece, base, tip, base width
	Spikes = { { "Outer", "W", "C", 0.4 }, { "Outer", "T", "X", 0.35 } },
	-- where the elemental cloud pours off / energy drips off: piece, point
	WingCloud = { { "Outer", "T" }, { "Outer", "n1" }, { "Outer", "P1" }, { "Inner", "n2" }, { "Inner", "P2" }, { "Inner", "P3" }, { "Inner", "B" } },
	WingDrips = { { "Outer", "T" }, { "Outer", "P1" }, { "Inner", "P2" }, { "Inner", "P3" } },
}
