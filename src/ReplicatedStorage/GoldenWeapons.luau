-- GoldenWeapons v6.0  (ModuleScript in ReplicatedStorage)
-- Shared settings + the client side of the Golden Weapons. Each element has its own weapon
-- (ByElement); switching element (E) swaps it.
-- Nunchucks of Lightning (moves copied from the reference video):
--   idle/walk: one stick in each hand held up in front of you, lightning arc between the heads
--   equip: reach back over the shoulder and pull them out
--   click combo: horizontal sweep -> overhead smash -> spin above the head + slam
--                -> two-handed low sweep (switches hands, big knockback)
-- The second stick is driven by code on every client (a spring that chases where it should
-- be), so it whips with weight but never flops around. NinjaAnimator calls Step() every frame.
-- Sword of Fire + Scythe of Quakes: two-handed. Keyframes move the weapon itself (in front of
--   the upper body) and both arms reach for its handle (IK from the character's own arm joints).
--   Sword combo: slash -> backslash -> overhead chop -> spin slash (fire burst, sets them on fire)
--   Scythe combo: reap -> reap back -> spin -> slam (quake: shockwave + rocks around the impact)
-- Shurikens of Ice: one in each hand, click throws them where you aim (alternating hands,
--   4th throw = both). A hit freezes the target. The server does the flying + hits.
-- Weapons without an imported model are placeholders built from blocks.

local Players = game:GetService("Players")

local GoldenWeapons = {}

GoldenWeapons.Nunchucks = {
	ToolName = "Nunchucks of Lightning",
	HolsterName = "NunchuckHolster",
	ModelName = "NunchuckGold",   -- imported model (one MeshPart)
	MeshName = "NunchuckStick",   -- older import (fallback)
	StickLength = 2.4,            -- studs
	HeadAtNegative = true,        -- dragon head at the -long-axis end of the mesh (flip if upside down)
	ChainGap = 0.7,               -- studs of lightning between the sticks while whipping
	Color = Color3.fromRGB(235, 178, 25),
	Material = Enum.Material.Metal,
	Reflectance = 0.12,
	GemColor = Color3.fromRGB(25, 75, 230),
	BoltColor = Color3.fromRGB(90, 200, 255),
	TrailColor = Color3.fromRGB(255, 205, 70),
	TrailColor2 = Color3.fromRGB(255, 125, 25),
	HitColor = Color3.fromRGB(90, 200, 255),
	HitTextColor = Color3.fromRGB(150, 215, 255),
	-- blue eyes + dots, in the imported mesh's own space (studs, for a 2.4 long stick)
	Gems = {
		{ size = Vector3.new(0.02, 0.085, 0.085), pos = Vector3.new(0.183, 0.073, 0.025), disc = true },
		{ size = Vector3.new(0.02, 0.085, 0.085), pos = Vector3.new(-0.183, 0.073, 0.025), disc = true },
		{ size = Vector3.new(0.025, 0.21, 0.045), pos = Vector3.new(0.136, -0.645, -0.144) },
		{ size = Vector3.new(0.025, 0.21, 0.045), pos = Vector3.new(-0.136, -0.645, -0.144) },
	},
	Follow = 26,                  -- how tightly the second stick follows (higher = stiffer)
	FollowSwing = 42,
	IdleFlourish = { 7, 12 },     -- seconds between idle twirls when standing still
	ComboWindow = 1.6,            -- seconds to click again to continue the combo
	Swings = {
		{ name = "sweep",    time = 0.55, damage = 10, hitAt = 0.5,  range = 5,   knock = 22 },
		{ name = "overhead", time = 0.6,  damage = 12, hitAt = 0.62, range = 5,   knock = 18, up = 28 },
		{ name = "spin",     time = 1.1,  damage = 16, hitAt = 0.86, range = 7,   knock = 30, up = 26, around = true },
		{ name = "lowSweep", time = 0.7,  damage = 22, hitAt = 0.55, range = 6.5, knock = 48, up = 16, final = true },
	},
	Draw = { name = "draw", time = 1.1, grabAt = 0.4 }, -- reach back, grab them off your back, pull
	Flourish = { name = "flourish", time = 0.75 },
	Sounds = {
		Swing = { "rbxassetid://9114276859", "rbxassetid://9114276862" },
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
		Zap = "rbxassetid://9114277757",
	},
}

local N = GoldenWeapons.Nunchucks

GoldenWeapons.Sword = {
	ToolName = "Sword of Fire",
	HolsterName = "SwordHolster",
	ModelName = "SwordOfFire",    -- imported model in ReplicatedStorage (biggest part = the sword,
	                              -- other parts in it, e.g. red eye dots, keep their colour); placeholder without it
	Length = 5,                   -- studs, the imported model is scaled to this
	FlipModel = false,            -- imported model held by the wrong end? set true
	FlipEdge = false,             -- edge facing the wrong way? set true (turns it around the blade)
	GripFromEnd = 0.6,            -- where the right hand holds it, studs from the hilt end
	LeftGap = 0.45,               -- the left hand holds it this far below the right hand
	HiltLength = 1.2,             -- studs from the hilt end to where the blade starts
	BackGrip = Vector3.new(0.55, 1.05, 0.65), -- on your back: hilt over the right shoulder
	BackAngle = math.pi - 0.6,
	-- placeholder sword
	BladeLength = 2.8,
	BladeWidth = 0.4,
	BladeThickness = 0.1,
	GripLength = 1.0,
	GripColor = Color3.fromRGB(150, 30, 15),
	Color = Color3.fromRGB(235, 178, 25),
	Material = Enum.Material.Metal,
	Reflectance = 0.12,
	CoreColor = Color3.fromRGB(255, 110, 20), -- glowing strip down the blade
	FlameColor = Color3.fromRGB(255, 200, 60),
	FlameColor2 = Color3.fromRGB(230, 50, 10),
	FlameRate = 18,               -- flames along the blade (more while swinging)
	FlameRateSwing = 70,
	TrailColor = Color3.fromRGB(255, 220, 90),
	TrailColor2 = Color3.fromRGB(255, 70, 15),
	HitColor = Color3.fromRGB(255, 120, 25),
	HitTextColor = Color3.fromRGB(255, 190, 90),
	BurnTime = 1.5,               -- the final hit sets them on fire (just the look)
	ComboWindow = 1.4,
	Swings = {
		{ name = "slash",     time = 0.45, damage = 11, hitAt = 0.5,  range = 6, knock = 20 },
		{ name = "backslash", time = 0.45, damage = 11, hitAt = 0.5,  range = 6, knock = 20 },
		{ name = "chop",      time = 0.6,  damage = 15, hitAt = 0.6,  range = 6, knock = 16, up = 26 },
		{ name = "spinSlash", time = 0.9,  damage = 24, hitAt = 0.62, range = 8, knock = 45, up = 18, around = true, final = true, burst = true, spin = true },
	},
	Draw = { name = "draw", time = 0.9, grabAt = 0.4 }, -- reach over the shoulder and pull it off your back
	Sounds = {
		Swing = { "rbxassetid://9114276859", "rbxassetid://9114276862" },
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
	},
}
local S = GoldenWeapons.Sword

GoldenWeapons.Scythe = {
	ToolName = "Scythe of Quakes",
	HolsterName = "ScytheHolster",
	ModelName = "ScytheOfQuakes", -- imported model (biggest part = the scythe); placeholder blocks without it
	Length = 5.5,                 -- studs along the shaft
	FlipModel = false,            -- held by the blade end? set true
	FlipEdge = false,             -- blade pointing backwards? set true
	GripFromEnd = 0.5,            -- right hand, studs from the bottom of the shaft
	LeftGap = 0.35,               -- left hand just below it
	HiltLength = 4.4,             -- the blade starts this far up the shaft
	BackGrip = Vector3.new(-0.6, -1.3, 0.7), -- on your back: blade up behind the right shoulder
	BackAngle = -0.52,
	-- placeholder
	ShaftThickness = 0.22,
	BladeLength = 2.2,
	BladeWidth = 0.45,
	BladeThickness = 0.1,
	Color = Color3.fromRGB(235, 178, 25),
	Material = Enum.Material.Metal,
	Reflectance = 0.12,
	TrailColor = Color3.fromRGB(255, 215, 120),
	TrailColor2 = Color3.fromRGB(150, 95, 40),
	HitColor = Color3.fromRGB(230, 150, 60),
	HitTextColor = Color3.fromRGB(255, 205, 130),
	QuakeRadius = 14,             -- the slam hits everyone this close to where it lands
	QuakeColor = Color3.fromRGB(215, 150, 65),
	RockColor = Color3.fromRGB(115, 82, 50),
	ComboWindow = 1.5,
	Swings = {
		{ name = "reap",     time = 0.6, damage = 12, hitAt = 0.5,  range = 7.5, reach = 4, knock = 22 },
		{ name = "reapBack", time = 0.6, damage = 12, hitAt = 0.5,  range = 7.5, reach = 4, knock = 22 },
		{ name = "spin",     time = 0.9, damage = 16, hitAt = 0.6,  range = 9, knock = 34, up = 16, around = true, spin = true },
		{ name = "slam",     time = 0.9, damage = 26, hitAt = 0.65, reach = 5.5, knock = 30, up = 45, final = true, quake = true },
	},
	Draw = { name = "draw", time = 0.9, grabAt = 0.4 },
	Sounds = {
		Swing = { "rbxassetid://9114276859", "rbxassetid://9114276862" },
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
	},
}
local SC = GoldenWeapons.Scythe

GoldenWeapons.Shurikens = {
	ToolName = "Shurikens of Ice",
	HolsterName = "ShurikenHolster",
	ModelName = "ShurikensOfIce", -- imported model of ONE shuriken (used for both + the thrown ones)
	Size = 1.1,                   -- studs across
	Thickness = 0.12,             -- placeholder
	Color = Color3.fromRGB(235, 178, 25),
	Material = Enum.Material.Metal,
	Reflectance = 0.12,
	IceColor = Color3.fromRGB(150, 225, 255),
	TrailColor = Color3.fromRGB(215, 245, 255),
	TrailColor2 = Color3.fromRGB(90, 180, 255),
	HitColor = Color3.fromRGB(120, 210, 255),
	HitTextColor = Color3.fromRGB(180, 235, 255),
	Speed = 95,                   -- studs/s
	Range = 130,                  -- studs before it shatters
	HitRadius = 1.2,
	FreezeTime = 1.2,             -- seconds a hit freezes them (can't move)
	FinalFreezeTime = 2.2,
	Reload = 0.7,                 -- seconds until a new one forms in the hand that threw
	ComboWindow = 1.2,
	Swings = {
		{ name = "throwR",    time = 0.38, release = 0.5, damage = 9,  hands = { "R" } },
		{ name = "throwL",    time = 0.38, release = 0.5, damage = 9,  hands = { "L" } },
		{ name = "throwR",    time = 0.38, release = 0.5, damage = 9,  hands = { "R" } },
		{ name = "throwBoth", time = 0.5,  release = 0.5, damage = 12, hands = { "R", "L" }, final = true },
	},
	Draw = { name = "draw", time = 0.6, grabAt = 0.35 },
	Sounds = {
		Swing = { "rbxassetid://9114276859", "rbxassetid://9114276862" },
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
	},
}
local K = GoldenWeapons.Shurikens

-- in the hand: shuriken flat side out to the side, just below the fist (shuriken space: Y = flat side)
GoldenWeapons.ShurikenHold = CFrame.new(0, -0.45, -0.1) * CFrame.Angles(0, 0, math.pi / 2)

GoldenWeapons.Weapons = { Nunchucks = N, Sword = S, Scythe = SC, Shurikens = K }
-- element -> weapon (elements not listed get none)
GoldenWeapons.ByElement = { Lightning = "Nunchucks", Fire = "Sword", Earth = "Scythe", Ice = "Shurikens" }
local TAU = math.pi * 2
local rng = Random.new()

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
local function R(x, y, z) return CFrame.Angles(x or 0, y or 0, z or 0) end
local function bell(e, a, b) return smooth(e / a) * (1 - smooth((e - b) / (1 - b))) end

-- stick space: chain end (head) at -Y, tail at +Y. Part CFrame = stick CFrame * StickAxis.
GoldenWeapons.HoldOffset = function(R0)
	local half = N.StickLength / 2
	-- gripped near the bottom end, the dragon head (chain end) sticking out of the top of the fist
	return CFrame.fromMatrix(Vector3.new(0, -0.25, -(half - 0.45)), Vector3.xAxis, Vector3.zAxis) * R0
end

-- two-handed weapons: weapon space has its origin at the right hand, +Y toward the tip,
-- +Z = the way the edge (or the scythe blade) faces. Handle = invisible part at the palm.
GoldenWeapons.Palm = CFrame.new(0, -0.2, 0)
-- weapon in the hand when nothing else places it (other clients before Step runs, parkour):
-- out of the fist, angled 60 degrees down the fingers
GoldenWeapons.DefaultHold = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis,
	Vector3.new(0, -math.sin(math.rad(60)), -math.cos(math.rad(60))))

----------------------------------------------------------------------------------------
-- arm poses (NinjaAnimator convention: +x swings a hanging arm forward,
-- +z swings the right arm out / the left arm in)
----------------------------------------------------------------------------------------

-- idle / walking: right hand in front of the waist holding both sticks
local function idleArm(pose)
	-- both hands up in front, a stick in each, apart so the lightning stretches between them
	pose.RightShoulder = R(0.35, 0, 0.38)
	pose.RightElbow = R(0.8, 0, 0)
	pose.LeftShoulder = R(0.35, 0, -0.38)
	pose.LeftElbow = R(0.8, 0, 0)
end

local function swingPose(pose, kind, e)
	if kind == "sweep" then
		pose.RightShoulder = R(1.1, lerp(1.0, -0.9, smooth(e)), 0.3)
		pose.RightElbow = R(lerp(1.1, 0.15, e), 0, 0)
		pose.LeftShoulder = R(0.9, 0, 0.3)
		pose.LeftElbow = R(1.3, 0, 0)
		pose.Waist = R(0, lerp(0.45, -0.5, smooth(e)), 0)
	elseif kind == "overhead" then
		local s = smooth((e - 0.3) / 0.5)
		pose.RightShoulder = R(lerp(2.9, 0.9, s), 0, lerp(0.2, -0.2, s))
		pose.RightElbow = R(lerp(0.3, 0.2, s), 0, 0)
		pose.LeftShoulder = R(0.6, 0, -0.4)
		pose.LeftElbow = R(0.9, 0, 0)
		pose.Waist = R(lerp(0.1, -0.3, s), lerp(0.2, -0.25, s), 0)
	elseif kind == "spin" then
		local slam = smooth((e - 0.78) / 0.22)
		pose.RightShoulder = R(lerp(2.9, 1.3, slam), 0, lerp(0.25, 0.1, slam))
		pose.RightElbow = R(lerp(0.25, 0.1, slam), 0, 0)
		pose.LeftShoulder = R(0.6, 0, -0.6)
		pose.LeftElbow = R(0.7, 0, 0)
		pose.Waist = R(lerp(0.1, -0.35, slam), e * TAU * 0.15, 0)
	elseif kind == "lowSweep" then
		local s = smooth(e)
		pose.RightShoulder = R(1.0, lerp(0.9, -0.6, s), 0.35)
		pose.RightElbow = R(0.4, 0, 0)
		pose.LeftShoulder = R(1.0, lerp(0.6, -0.9, s), -0.2)
		pose.LeftElbow = R(0.4, 0, 0)
		pose.Waist = R(0.15, lerp(0.6, -0.6, s), 0)
	elseif kind == "draw" then
		-- reach back over the right shoulder to the sticks on your back, then pull them over
		if e < 0.4 then
			-- arm swings out to the side and up, so the hand goes over the shoulder (not past the face)
			local u = smooth(e / 0.4)
			pose.RightShoulder = R(lerp(0.12, 3.1, u), 0, lerp(-0.08, -0.05, u) + 0.9 * math.sin(math.pi * u))
			pose.RightElbow = R(lerp(1.0, 1.9, u), 0, 0)
			pose.Neck = R(lerp(0, 0.15, u), lerp(0, -0.35, u), 0)
		else
			local s = smooth((e - 0.4) / 0.6)
			pose.RightShoulder = R(lerp(3.1, 0.12, s), 0, lerp(-0.05, -0.08, s))
			pose.RightElbow = R(lerp(1.9, 1.0, s), 0, 0)
		end
		pose.Waist = R(0, -0.25 * bell(e, 0.3, 0.6), 0)
	else -- flourish
		pose.RightShoulder = R(1.25, 0, 0.45)
		pose.RightElbow = R(0.6, 0, 0)
	end
end

-- direction the free stick points out from the held stick's head (character space:
-- +x right, +y up, -z forward). "bundle" = held next to the other stick, "left" = left hand.
local function swingDir(kind, e)
	if kind == "sweep" then
		local a = math.rad(lerp(-20, 240, smooth(e)))
		return Vector3.new(math.cos(a), 0.1, -math.sin(a))
	elseif kind == "overhead" then
		local a = math.rad(lerp(-150, 125, smooth(e)))
		return Vector3.new(-0.25 * smooth(e), math.cos(a), -math.sin(a)).Unit
	elseif kind == "spin" then
		if e < 0.78 then
			local a = (e / 0.78) * TAU * 2.5
			return Vector3.new(math.cos(a), 0.25, -math.sin(a)).Unit
		end
		local s = smooth((e - 0.78) / 0.22)
		return Vector3.new(0, lerp(0.25, -0.6, s), -1).Unit
	elseif kind == "lowSweep" then
		return "left"
	elseif kind == "draw" then
		return e < 0.8 and "bundle" or "left"
	elseif kind == "flourish" then
		if e > 0.85 then return "left" end
		local a = (e / 0.85) * TAU * 2
		return Vector3.new(math.sin(a), -0.2, -math.cos(a)).Unit
	end
	return "left"
end

----------------------------------------------------------------------------------------
-- two-handed keyframes: they place the WEAPON in UpperTorso space (+x right, +y up,
-- -z forward), both arms then reach for it. Worked out against the R15 arm so neither the
-- weapon nor the hands go through the body.
--   wkey(e reached at, right hand, toward the tip, way the edge/blade faces, upper body turn)
----------------------------------------------------------------------------------------
local V = Vector3.new
local function wkey(e, grip, dir, edgeWay, waist)
	local d = dir.Unit
	local edge = (edgeWay - d * edgeWay:Dot(d)).Unit
	return { e = e, cf = CFrame.fromMatrix(grip, d:Cross(edge), d), waist = waist or CFrame.identity }
end

S.Idle = wkey(0, V(0.05, -0.35, -1.0), V(0.05, 0.75, -0.65), V(0, -0.65, -0.75)) -- blade up and forward
local chopDown = { V(0.05, -0.55, -1.15), V(0, -0.35, -0.94), V(0, -1, 0.3) }
S.Moves = {
	slash = { -- right -> left
		wkey(0.3, V(0.3, 0, -0.85), V(0.65, 0.6, 0.45), V(-0.7, 0, -0.7), R(0, -0.5, 0)),
		wkey(0.55, V(-0.05, -0.4, -1.1), V(-0.45, 0.05, -0.9), V(-1, 0, 0)),
		wkey(1, V(-0.3, -0.5, -0.95), V(-0.95, -0.1, 0.3), V(-0.3, 0, 1), R(0, 0.6, 0)),
	},
	backslash = { -- left -> right
		wkey(0.3, V(-0.25, 0, -0.85), V(-0.65, 0.6, 0.45), V(0.7, 0, -0.7), R(0, 0.5, 0)),
		wkey(0.55, V(0.1, -0.4, -1.1), V(0.45, 0.05, -0.9), V(1, 0, 0)),
		wkey(1, V(0.35, -0.5, -0.95), V(0.95, -0.1, 0.3), V(0.3, 0, 1), R(0, -0.6, 0)),
	},
	chop = { -- up above the head, then straight down in front
		wkey(0.4, V(0.05, 1.55, -0.8), V(0, 0.75, 0.66), V(0, 0.3, -1), R(0.15, 0, 0)),
		wkey(0.65, chopDown[1], chopDown[2], chopDown[3], R(-0.3, 0, 0)),
		wkey(1, chopDown[1], chopDown[2], chopDown[3], R(-0.25, 0, 0)),
	},
	spinSlash = { -- blade level out to the right, the whole body spins once
		wkey(0.15, V(0.2, -0.4, -1.0), V(0.95, 0, -0.3), V(0, 0, -1)),
		wkey(1, V(0.2, -0.4, -1.0), V(0.95, 0, -0.3), V(0, 0, -1)),
	},
}

SC.Idle = wkey(0, V(0.1, -0.4, -1.0), V(0.15, 0.85, -0.5), V(0, 0, -1)) -- shaft up, blade forward
local slamDown = { V(0.05, -0.5, -1.2), V(0, -0.55, -0.83), V(0, -1, 0.2) }
SC.Moves = {
	reap = { -- right -> left, blade leading
		wkey(0.3, V(0.3, -0.2, -0.9), V(0.75, 0.35, -0.55), V(-0.4, 0, -1), R(0, -0.5, 0)),
		wkey(0.55, V(0, -0.5, -1.1), V(-0.1, 0.1, -1), V(-1, 0, 0)),
		wkey(1, V(-0.3, -0.5, -0.95), V(-0.8, 0.1, -0.55), V(-0.3, 0, 1), R(0, 0.6, 0)),
	},
	reapBack = { -- left -> right
		wkey(0.3, V(-0.25, -0.2, -0.9), V(-0.75, 0.35, -0.55), V(0.4, 0, -1), R(0, 0.5, 0)),
		wkey(0.55, V(0.1, -0.5, -1.1), V(0.1, 0.1, -1), V(1, 0, 0)),
		wkey(1, V(0.35, -0.5, -0.95), V(0.8, 0.1, -0.55), V(0.3, 0, 1), R(0, -0.6, 0)),
	},
	spin = { -- shaft level out to the right, the whole body spins once
		wkey(0.15, V(0.2, -0.45, -1.0), V(0.95, 0.05, -0.3), V(0, 0, -1)),
		wkey(1, V(0.2, -0.45, -1.0), V(0.95, 0.05, -0.3), V(0, 0, -1)),
	},
	slam = { -- straight up, then down into the ground in front
		wkey(0.45, V(0.05, 1.5, -0.85), V(0, 0.95, -0.3), V(0, 0, -1), R(0.2, 0, 0)),
		wkey(0.65, slamDown[1], slamDown[2], slamDown[3], R(-0.35, 0, 0)),
		wkey(1, slamDown[1], slamDown[2], slamDown[3], R(-0.3, 0, 0)),
	},
}

local function weaponKey(W, kind, e, from)
	local prevE, prev = 0, from
	for _, k in ipairs(W.Moves[kind] or {}) do
		if e <= k.e then
			local s = smooth((e - prevE) / math.max(k.e - prevE, 1e-3))
			return { cf = prev.cf:Lerp(k.cf, s), waist = prev.waist:Lerp(k.waist, s) }
		end
		prevE, prev = k.e, k
	end
	return prev
end

----------------------------------------------------------------------------------------
-- arm IK (R15): read from the character's own shoulder / elbow / wrist joints
----------------------------------------------------------------------------------------

local rigs = setmetatable({}, { __mode = "k" }) -- [character] = { Right = rig, Left = rig }

-- a joint's child part relative to its parent, with the pose rotation applied
local function link(m, rot)
	return CFrame.new(m.C0.Position) * rot * m.C0.Rotation * m.C1:Inverse()
end

local function armRig(character, side)
	local cache = rigs[character]
	if not cache then
		cache = {}
		rigs[character] = cache
	end
	local r = cache[side]
	if r and r.sh.Parent and r.el.Parent and r.wr.Parent then return r end
	local ua = character:FindFirstChild(side .. "UpperArm")
	local la = character:FindFirstChild(side .. "LowerArm")
	local hand = character:FindFirstChild(side .. "Hand")
	local sh = ua and ua:FindFirstChild(side .. "Shoulder")
	local el = la and la:FindFirstChild(side .. "Elbow")
	local wr = hand and hand:FindFirstChild(side .. "Wrist")
	if not (sh and el and wr and sh:IsA("Motor6D") and el:IsA("Motor6D") and wr:IsA("Motor6D")) then return nil end
	r = { sh = sh, el = el, wr = wr, S = sh.C0.Position, A = sh.C0.Rotation * sh.C1:Inverse() }
	r.upper = (r.A * CFrame.new(el.C0.Position)).Position -- shoulder -> elbow, before the shoulder turns
	cache[side] = r
	return r
end

-- hand relative to the shoulder pivot (before the shoulder turns) with the elbow bent by el
local function handRel(r, el)
	return r.A * link(r.el, R(el, 0, 0)) * link(r.wr, CFrame.identity)
end

-- hand CFrame in UpperTorso space for a shoulder rotation + elbow bend
local function handCF(r, q, el)
	return CFrame.new(r.S) * q * handRel(r, el)
end

local function rotBetween(a, b)
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-6 then
		if dot > 0 then return CFrame.identity end
		local perp = math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis
		return CFrame.fromAxisAngle(a:Cross(perp).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- shoulder rotation + elbow bend that put the hand at target (UpperTorso space), elbow toward pole.
-- Out of reach: the arm points straight at it.
local function solveArm(r, target, pole)
	local d = target - r.S
	local dist = d.Magnitude
	local lo, hi = 0, 2.6 -- elbow bend, lo = straight (longest reach)
	local el
	if dist >= handRel(r, lo).Position.Magnitude then
		el = lo
	elseif dist <= handRel(r, hi).Position.Magnitude then
		el = hi
	else
		for _ = 1, 12 do
			local mid = (lo + hi) / 2
			if handRel(r, mid).Position.Magnitude > dist then lo = mid else hi = mid end
		end
		el = (lo + hi) / 2
	end
	local dir = dist > 1e-4 and d / dist or -Vector3.yAxis
	local q = rotBetween(handRel(r, el).Position.Unit, dir)
	-- twist around the reach line so the elbow points toward the pole
	local e1 = q:VectorToWorldSpace(r.upper)
	local a = e1 - dir * e1:Dot(dir)
	local b = pole - dir * pole:Dot(dir)
	if a.Magnitude > 1e-4 and b.Magnitude > 1e-4 then
		q = CFrame.fromAxisAngle(dir, math.atan2(dir:Dot(a:Cross(b)), a:Dot(b))) * q
	end
	return q, el
end

local POLE_R = V(0.6, -1, 0.35) -- elbows down, out and a little back
local POLE_L = V(-0.6, -1, 0.35)

----------------------------------------------------------------------------------------
-- shuriken throw poses (side 1 = right arm, -1 = left)
----------------------------------------------------------------------------------------

local function holdPose(pose, side)
	local name = side > 0 and "Right" or "Left"
	pose[name .. "Shoulder"] = R(0.4, 0, 0.2 * side)
	pose[name .. "Elbow"] = R(1.0, 0, 0)
end

local function throwPose(pose, side, e)
	local name = side > 0 and "Right" or "Left"
	local back, out, after = R(2.4, 0, 0.35 * side), R(1.45, 0, 0.05 * side), R(1.0, 0, -0.25 * side)
	local sh, el
	if e < 0.45 then -- wind up: hand back by the ear
		local s = smooth(e / 0.45)
		sh, el = R(0.4, 0, 0.2 * side):Lerp(back, s), lerp(1.0, 1.9, s)
	elseif e < 0.6 then -- snap forward, let go
		local s = smooth((e - 0.45) / 0.15)
		sh, el = back:Lerp(out, s), lerp(1.9, 0.1, s)
	else -- follow through across the body
		local s = smooth((e - 0.6) / 0.4)
		sh, el = out:Lerp(after, s), lerp(0.1, 0.4, s)
	end
	pose[name .. "Shoulder"] = sh
	pose[name .. "Elbow"] = R(el, 0, 0)
end

----------------------------------------------------------------------------------------
-- per-tool client state
----------------------------------------------------------------------------------------

local states = {} -- [tool] = state

local function frameFrom(p, q, ref)
	local y = q - p
	y = y.Magnitude > 1e-4 and y.Unit or Vector3.yAxis
	local x = ref - y * ref:Dot(y)
	if x.Magnitude < 1e-3 then x = y:Cross(Vector3.zAxis) end
	return CFrame.fromMatrix((p + q) / 2, x.Unit, y)
end

local function updateBolts(handle, stickB, axis, bowOverride)
	local a0 = handle:FindFirstChild("BoltA0")
	local a1 = stickB:FindFirstChild("BoltA1")
	if a0 and a1 then
		local dist = (a1.WorldPosition - a0.WorldPosition).Magnitude
		-- far apart: the arc sags down. Close together: it loops out past the dragon heads.
		local bow, sag
		if bowOverride then
			bow, sag = bowOverride, 0.28
		elseif dist < 0.6 then
			bow = handle.CFrame:VectorToWorldSpace(axis:Inverse() * Vector3.new(0, -1, 0))
			sag = 0.3
		else
			bow = -Vector3.yAxis
			sag = math.clamp(dist * 0.12, 0.05, 0.45)
		end
		local function aim(att, part)
			local x = part.CFrame:VectorToObjectSpace(bow)
			local z = x:Cross(Vector3.yAxis)
			if z.Magnitude < 1e-3 then z = x:Cross(Vector3.xAxis) end
			att.CFrame = CFrame.fromMatrix(att.Position, x, z.Unit:Cross(x), z.Unit)
		end
		aim(a0, handle)
		aim(a1, stickB)
		for _, name in ipairs({ "BoltCore", "BoltGlow" }) do
			local b = stickB:FindFirstChild(name)
			if b then b.CurveSize0, b.CurveSize1 = sag, -sag end
		end
	end
	-- jittery side arcs
	for i = 1, 2 do
		local j0 = handle:FindFirstChild("Jit0_" .. i)
		local j1 = stickB:FindFirstChild("Jit1_" .. i)
		local b = stickB:FindFirstChild("BoltJit" .. i)
		if j0 and j1 and b then
			j0.CFrame = CFrame.new(j0.Position) * R(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
			j1.CFrame = CFrame.new(j1.Position) * R(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
			-- small flickering crackles that hug the main arc
			b.CurveSize0 = rng:NextNumber(-0.12, 0.12)
			b.CurveSize1 = rng:NextNumber(-0.12, 0.12)
			b.Transparency = NumberSequence.new(rng:NextNumber() < 0.35 and 1 or rng:NextNumber(0.15, 0.6))
		end
	end
end

local function setTrails(tool, on)
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("Trail") and d.Name == "GoldTrail" then d.Enabled = on end
	end
end

local function setFlames(tool, rate)
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "Flames" then d.Rate = rate end
	end
end

-- hide the weapon in your hand while you're still reaching back for it
local function hideInHand(tool, st, hidden)
	if hidden == st.hidden then return end
	st.hidden = hidden
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = hidden and 1 or 0
		elseif d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("PointLight") then d.Enabled = not hidden end
	end
end

local function trackTool(tool, st)
	states[tool] = st
	tool.AncestryChanged:Connect(function()
		if not tool.Parent or not tool.Parent:FindFirstChildOfClass("Humanoid") then states[tool] = nil end
	end)
end

-- Sword / Scythe: place the weapon from the keyframes, then both arms on it
local function meleeStep(W, tool, character, pose, dt, armsFree)
	local weapon = tool:FindFirstChild("Weapon")
	local joint = weapon and weapon:FindFirstChild("WeaponJoint")
	if not joint then return pose end
	local st = states[tool]
	if not st then
		st = { lastId = tool:GetAttribute("SwingId") or 0, swing = W.Draw, t = 0, key = W.Idle, T = CFrame.identity }
		trackTool(tool, st)
	end

	-- new swing started (server bumps SwingId on each click)
	local id = tool:GetAttribute("SwingId") or 0
	if id ~= st.lastId then
		st.lastId = id
		st.swing, st.t = W.Swings[tool:GetAttribute("Swing") or 1] or W.Swings[1], 0
		st.from, st.recoverFrom = st.key, nil
		setTrails(tool, true)
		if W.FlameRateSwing then setFlames(tool, W.FlameRateSwing) end
	end

	local out = table.clone(pose)
	local key, drawing = W.Idle, false
	if st.swing then
		st.t += dt
		local e = math.clamp(st.t / st.swing.time, 0, 1)
		if st.swing == W.Draw then
			drawing = true
			if armsFree then swingPose(out, "draw", e) end
		else
			key = weaponKey(W, st.swing.name, e, st.from or W.Idle)
			if armsFree and st.swing.spin then
				out.Root = R(0, TAU * smooth((e - 0.15) / 0.65), 0) * (out.Root or CFrame.identity)
			end
		end
		if e >= 1 then
			st.recoverFrom = not drawing and key or nil
			st.recover = 0
			st.swing = nil
			setTrails(tool, false)
			if W.FlameRate then setFlames(tool, W.FlameRate) end
			local sparks = tool:FindFirstChild("Sparks", true)
			if sparks then sparks:Emit(16) end
		end
	elseif st.recoverFrom then
		-- ease back into the ready stance
		st.recover += dt
		local s = smooth(st.recover / 0.4)
		key = { cf = st.recoverFrom.cf:Lerp(W.Idle.cf, s), waist = st.recoverFrom.waist:Lerp(CFrame.identity, s) }
		if s >= 1 then st.recoverFrom = nil end
	end
	st.key = key

	local target = CFrame.identity -- weapon relative to the default hold
	local right, left = armRig(character, "Right"), armRig(character, "Left")
	if right and left and armsFree and not drawing then
		local cf = key.cf
		-- right hand: its centre a little back from the grip, toward the shoulder
		local grip = cf.Position
		local qR, eR = solveArm(right, grip - (grip - right.S).Unit * 0.2, POLE_R)
		local palm = handCF(right, qR, eR) * GoldenWeapons.Palm
		local wcf = CFrame.new(palm.Position) * cf.Rotation -- weapon where the hand really ends up
		local leftGrip = wcf * V(0, -W.LeftGap, 0)
		local qL, eL = solveArm(left, leftGrip - (leftGrip - left.S).Unit * 0.2, POLE_L)
		out.RightShoulder, out.RightElbow = qR, R(eR, 0, 0)
		out.LeftShoulder, out.LeftElbow = qL, R(eL, 0, 0)
		out.Waist = key.waist * (out.Waist or CFrame.identity)
		target = joint.C0:Inverse() * palm:Inverse() * wcf
	end
	-- the weapon hangs off the hand, so it follows the arm exactly; smooth the hand -> weapon turn
	st.T = st.T:Lerp(target, 1 - math.exp(-dt * 16))
	joint.Transform = st.T

	hideInHand(tool, st, drawing and st.t < W.Draw.time * W.Draw.grabAt)
	return out
end

-- Shurikens: hold one in each hand, throw animation (the server throws the real ones)
local function shurikenStep(tool, pose, dt, armsFree)
	local st = states[tool]
	if not st then
		st = { lastId = tool:GetAttribute("SwingId") or 0, swing = K.Draw, t = 0 }
		trackTool(tool, st)
	end
	local id = tool:GetAttribute("SwingId") or 0
	if id ~= st.lastId then
		st.lastId = id
		st.swing, st.t = K.Swings[tool:GetAttribute("Swing") or 1] or K.Swings[1], 0
	end

	local out = table.clone(pose)
	local drawing = st.swing == K.Draw
	if st.swing then
		st.t += dt
		local e = math.clamp(st.t / st.swing.time, 0, 1)
		if armsFree then
			if drawing then
				swingPose(out, "draw", e)
				holdPose(out, -1)
			else
				local hands = st.swing.hands
				for _, side in ipairs({ 1, -1 }) do
					if table.find(hands, side > 0 and "R" or "L") then throwPose(out, side, e) else holdPose(out, side) end
				end
				if #hands == 1 then
					-- turn into the throw: back on the wind-up, forward on the release
					local side = hands[1] == "R" and 1 or -1
					local turn = e < 0.45 and lerp(0, -0.3, smooth(e / 0.45)) or lerp(-0.3, 0.25, smooth((e - 0.45) / 0.3))
					out.Waist = R(0, turn * side, 0) * (out.Waist or CFrame.identity)
				end
			end
		end
		if e >= 1 then st.swing = nil end
	elseif armsFree then
		holdPose(out, 1)
		holdPose(out, -1)
	end

	hideInHand(tool, st, drawing and st.t < K.Draw.time * K.Draw.grabAt)
	return out
end

-- returns the pose with the arms overridden, and places the free stick
function GoldenWeapons.Step(character, root, pose, dt, armsFree)
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return pose end
	if tool.Name == S.ToolName then return meleeStep(S, tool, character, pose, dt, armsFree) end
	if tool.Name == SC.ToolName then return meleeStep(SC, tool, character, pose, dt, armsFree) end
	if tool.Name == K.ToolName then return shurikenStep(tool, pose, dt, armsFree) end
	if tool.Name ~= N.ToolName then return pose end
	local handle = tool:FindFirstChild("Handle")
	local stickB = tool:FindFirstChild("StickB")
	local joint = stickB and stickB:FindFirstChild("ChainJoint")
	local headTip = handle and handle:FindFirstChild("HeadTip")
	local leftHand = character:FindFirstChild("LeftHand")
	if not handle or not joint or not headTip or not leftHand then return pose end
	local axis = stickB:GetAttribute("StickAxis")
	if typeof(axis) ~= "CFrame" then axis = CFrame.identity end

	local st = states[tool]
	if not st then
		st = {
			lastId = tool:GetAttribute("SwingId") or 0,
			swing = N.Draw, t = 0, -- pull them off your back
			cur = nil, arc = 0, idle = 0, nextIdle = rng:NextNumber(N.IdleFlourish[1], N.IdleFlourish[2]),
		}
		trackTool(tool, st)
	end

	-- new swing started (server bumps SwingId on each click)
	local id = tool:GetAttribute("SwingId") or 0
	if id ~= st.lastId then
		st.lastId = id
		local n = tool:GetAttribute("Swing") or 1
		st.swing, st.t = N.Swings[n] or N.Swings[1], 0
		setTrails(tool, true)
	end

	-- idle flourish while standing still
	local v = root.AssemblyLinearVelocity
	if not st.swing and armsFree and Vector3.new(v.X, 0, v.Z).Magnitude < 1 then
		st.idle += dt
		if st.idle > st.nextIdle then
			st.idle = 0
			st.nextIdle = rng:NextNumber(N.IdleFlourish[1], N.IdleFlourish[2])
			st.swing, st.t = N.Flourish, 0
			setTrails(tool, true)
		end
	else
		st.idle = 0
	end

	-- arms
	local out = table.clone(pose)
	local dir = "left"
	local dbg = tool:GetAttribute("DebugSwing") -- testing: freeze a move at DebugE (0-1)
	if dbg then
		local e = tool:GetAttribute("DebugE") or 0.5
		local sw = { name = dbg }
		swingPose(out, sw.name, e)
		dir = swingDir(sw.name, e)
		st.swing = nil
	elseif st.swing then
		st.t += dt * (tool:GetAttribute("DebugTimeScale") or 1)
		local e = math.clamp(st.t / st.swing.time, 0, 1)
		if armsFree then swingPose(out, st.swing.name, e) end
		dir = swingDir(st.swing.name, e)
		if e >= 1 then
			-- remember where the arms ended so they ease back instead of snapping
			st.endPose = {}
			for _, key in ipairs({ "RightShoulder", "RightElbow", "LeftShoulder", "LeftElbow", "Waist" }) do
				st.endPose[key] = out[key]
			end
			st.recover = 0.45
			st.swing = nil
			setTrails(tool, false)
			local sparks = stickB:FindFirstChild("Sparks", true)
			if sparks then sparks:Emit(16) end
		end
	elseif armsFree then
		idleArm(out)
		if st.recover and st.recover > 0 and st.endPose then
			st.recover -= dt
			local k = smooth(1 - st.recover / 0.45)
			for key, cf in pairs(st.endPose) do
				out[key] = cf:Lerp(out[key] or CFrame.identity, k)
			end
		end
	end

	-- while reaching back for them the sticks are still on your back: hide the ones in hand
	local hidden = st.swing == N.Draw and st.t < N.Draw.time * N.Draw.grabAt
	if hidden ~= st.hidden then
		hideInHand(tool, st, hidden)
		if hidden then st.cur = nil elseif st.swing == N.Draw then setTrails(tool, true) end
	end

	-- where the free stick should be
	local want
	local torso = character:FindFirstChild("UpperTorso")
	if dir == "bundle" then
		want = handle.CFrame * axis:Inverse() * CFrame.new(0.32, 0.05, 0.05) * R(0, 0.1, 0.05) * axis
	elseif dir == "tuck" and torso then
		-- tucked under the right arm, dragon head up by the armpit
		want = torso.CFrame * CFrame.new(1.0, -0.2, 0.4) * R(math.pi, 0, -0.06) * axis
	elseif dir == "left" then
		want = leftHand.CFrame * GoldenWeapons.HoldOffset(axis)
	else
		local d = root.CFrame:VectorToWorldSpace(dir)
		local a = headTip.WorldPosition
		local p = a + d * N.ChainGap
		local q = a + d * (N.ChainGap + N.StickLength)
		local ref = math.abs(d:Dot(root.CFrame.UpVector)) > 0.8 and root.CFrame.LookVector or root.CFrame.UpVector
		want = frameFrom(p, q, ref) * axis
	end

	-- spring toward it, in the character's own space so running/turning doesn't drag it
	local wantLocal = root.CFrame:ToObjectSpace(want)
	if not st.cur or (st.cur.Position - wantLocal.Position).Magnitude > 12 then
		st.cur = wantLocal
	else
		local rate = st.swing and N.FollowSwing or ((st.recover or 0) > 0 and 9 or N.Follow)
		local k = 1 - math.exp(-dt * rate)
		st.cur = st.cur:Lerp(wantLocal, k)
	end
	joint.Transform = handle.CFrame:Inverse() * (root.CFrame * st.cur)

	-- lightning arc
	st.arc -= dt
	if st.arc <= 0 then
		st.arc = 0.035
		-- tucked: bow the arc out to the side so it isn't hidden inside the arm
		updateBolts(handle, stickB, axis, dir == "tuck" and (root.CFrame.RightVector * 0.8 + root.CFrame.LookVector * 0.5).Unit or nil)
	end
	return out
end

return GoldenWeapons
