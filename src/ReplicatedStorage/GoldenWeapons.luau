-- GoldenWeapons v5.0  (ModuleScript in ReplicatedStorage)
-- Shared settings + the client side of the Golden Weapons. Each element has its own weapon
-- (ByElement); switching element (E) swaps it.
-- Nunchucks of Lightning (moves copied from the reference video):
--   idle/walk: one stick in each hand held up in front of you, lightning arc between the heads
--   equip: reach back over the shoulder and pull them out
--   click combo: horizontal sweep -> overhead smash -> spin above the head + slam
--                -> two-handed low sweep (switches hands, big knockback)
-- The second stick is driven by code on every client (a spring that chases where it should
-- be), so it whips with weight but never flops around. NinjaAnimator calls Step() every frame.
-- Sword of Fire: held at an angle in the fist so the blade extends the arm, flames along the blade.
--   click combo: slash -> backslash -> overhead chop -> spin slash (fire burst, sets them on fire)
--   Placeholder sword built from parts until a "SwordOfFire" model is imported.

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
	ModelName = "SwordOfFire",    -- imported model (one MeshPart) in ReplicatedStorage; placeholder without it
	Length = 3.9,                 -- studs, the imported model is scaled to this
	FlipModel = false,            -- imported model held by the wrong end? set true
	GripFromEnd = 0.45,           -- where the hand holds it, studs from the hilt end
	HiltLength = 1.0,             -- studs from the hilt end to where the blade starts
	-- placeholder sword
	BladeLength = 2.8,
	BladeWidth = 0.4,
	BladeThickness = 0.1,
	GripLength = 0.8,
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
		{ name = "spinSlash", time = 0.9,  damage = 24, hitAt = 0.62, range = 8, knock = 45, up = 18, around = true, final = true, burst = true },
	},
	Draw = { name = "draw", time = 0.9, grabAt = 0.4 }, -- reach over the shoulder and pull it off your back
	Sounds = {
		Swing = { "rbxassetid://9114276859", "rbxassetid://9114276862" },
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
	},
}
local S = GoldenWeapons.Sword

GoldenWeapons.Weapons = { Nunchucks = N, Sword = S }
-- element -> weapon (elements not listed get none). Still to come: Earth = Scythe, Ice = Shurikens
GoldenWeapons.ByElement = { Lightning = "Nunchucks", Fire = "Sword" }
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

-- sword space: +Y toward the tip, X = the flat side. Part CFrame = sword CFrame * axis.
-- The blade leaves the fist at 60 degrees toward the fingers, so it carries on from the forearm.
local SWORD_TILT = math.rad(60)
GoldenWeapons.SwordHold = function(R0, gripY)
	local blade = Vector3.new(0, -math.sin(SWORD_TILT), -math.cos(SWORD_TILT))
	return CFrame.fromMatrix(Vector3.new(0, -0.2, 0), Vector3.xAxis, blade) * CFrame.new(0, -gripY, 0) * R0
end

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

-- Sword: right shoulder + elbow keyframes (worked out for the 60 degree grip so the blade sweeps
-- through in front of you, edge first, without going through the body). Shoulders blend as
-- rotations, so the big angles in the follow-throughs are fine.
local function key(x, y, z, el, waist) return { sh = R(x, y, z), el = el, waist = waist } end
local SWORD_IDLE = key(-0.1, -0.2, -0.1, 1.8) -- ready stance: blade up and forward
local SWORD_MOVES = {
	-- { e this key is reached at, key }   (each move starts from wherever the arm was)
	slash = { -- right -> left
		{ 0.3, key(-0.2, -1.5, -0.9, 2.1, R(0, -0.4, 0)) },
		{ 0.6, key(0.6, -1.3, -0.7, 0, R(0, 0.1, 0)) },
		{ 1, key(2.4, 1.4, -1.3, 1.2, R(0, 0.5, 0)) },
	},
	backslash = { -- left -> right
		{ 0.3, key(0.4, 1.6, 0.4, 1.3, R(0, 0.5, 0)) },
		{ 0.6, key(0.3, 1.3, 0.9, 0, R(0, -0.1, 0)) },
		{ 1, key(3.2, -0.8, 2.0, 1.0, R(0, -0.5, 0)) },
	},
	chop = { -- up over the head, then straight down in front
		{ 0.4, key(1.9, 0, 0, 1.7, R(0.15, 0, 0)) },
		{ 0.65, key(1.0, 0, 0, 0, R(-0.3, 0, 0)) },
		{ 1, key(1.0, 0, 0, 0, R(-0.25, 0, 0)) },
	},
	spinSlash = { -- arm out to the side, blade level, the whole body spins once
		{ 0.15, key(0.1, -0.3, 1.1, 0.8, R(0, 0, 0)) },
		{ 1, key(0.1, -0.3, 1.1, 0.8, R(0, 0, 0)) },
	},
}

local function blendKey(a, b, s)
	return {
		sh = a.sh:Lerp(b.sh, s),
		el = lerp(a.el, b.el, s),
		waist = (a.waist or CFrame.identity):Lerp(b.waist or CFrame.identity, s),
	}
end

local function swordKey(kind, e, from)
	local prevE, prevK = 0, from
	for _, k in ipairs(SWORD_MOVES[kind] or {}) do
		if e <= k[1] then return blendKey(prevK, k[2], smooth((e - prevE) / math.max(k[1] - prevE, 1e-3))) end
		prevE, prevK = k[1], k[2]
	end
	return prevK
end

local function applyKey(pose, k, withWaist)
	pose.RightShoulder = k.sh
	pose.RightElbow = R(k.el, 0, 0)
	if withWaist and k.waist then pose.Waist = k.waist end
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

local function swordStep(tool, pose, dt, armsFree)
	if not tool:FindFirstChild("Handle") then return pose end
	local st = states[tool]
	if not st then
		st = { lastId = tool:GetAttribute("SwingId") or 0, swing = S.Draw, t = 0, arm = SWORD_IDLE }
		trackTool(tool, st)
	end

	-- new swing started (server bumps SwingId on each click)
	local id = tool:GetAttribute("SwingId") or 0
	if id ~= st.lastId then
		st.lastId = id
		st.swing, st.t = S.Swings[tool:GetAttribute("Swing") or 1] or S.Swings[1], 0
		st.from, st.recoverFrom = st.arm, nil
		setTrails(tool, true)
		setFlames(tool, S.FlameRateSwing)
	end

	local out = table.clone(pose)
	if st.swing then
		st.t += dt
		local e = math.clamp(st.t / st.swing.time, 0, 1)
		if st.swing == S.Draw then
			if armsFree then swingPose(out, "draw", e) end
			st.arm = SWORD_IDLE
		else
			local k = swordKey(st.swing.name, e, st.from or SWORD_IDLE)
			st.arm = k
			if armsFree then
				applyKey(out, k, true)
				if st.swing.name == "spinSlash" then
					out.LeftShoulder = R(0.1, 0, -1.1)
					out.LeftElbow = R(0.3, 0, 0)
					out.Root = R(0, TAU * smooth((e - 0.15) / 0.65), 0) * (out.Root or CFrame.identity)
				else
					out.LeftShoulder = R(0.4, 0, -0.25) -- guard
					out.LeftElbow = R(1.3, 0, 0)
				end
			end
		end
		if e >= 1 then
			st.recoverFrom = st.swing ~= S.Draw and st.arm or nil
			st.recover = 0
			st.swing = nil
			setTrails(tool, false)
			setFlames(tool, S.FlameRate)
			local sparks = tool:FindFirstChild("Sparks", true)
			if sparks then sparks:Emit(16) end
		end
	else
		-- ease back into the ready stance
		local k = SWORD_IDLE
		if st.recoverFrom then
			st.recover += dt
			local s = smooth(st.recover / 0.4)
			k = blendKey(st.recoverFrom, SWORD_IDLE, s)
			if s >= 1 then st.recoverFrom = nil end
		end
		st.arm = k
		if armsFree then applyKey(out, k, k ~= SWORD_IDLE) end
	end

	hideInHand(tool, st, st.swing == S.Draw and st.t < S.Draw.time * S.Draw.grabAt)
	return out
end

-- returns the pose with the arms overridden, and places the free stick
function GoldenWeapons.Step(character, root, pose, dt, armsFree)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool.Name == S.ToolName then return swordStep(tool, pose, dt, armsFree) end
	if not tool or tool.Name ~= N.ToolName then return pose end
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
