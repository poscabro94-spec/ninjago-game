-- ElementPowers v3.2  (ModuleScript in ReplicatedStorage)
-- Elemental powers, used with empty hands (no Golden Weapon out): all six elements.
--   tap left click:    a shot from the right hand -> the left hand -> a big one from both hands
--   hold left click:   both hands out, a beam from each meets in front of you and one big beam
--                      goes on to where you aim
--   Lightning  balls; the big one explodes + electrocutes (3s x 5)       | lightning beam
--   Fire       fireballs; the big one explodes + sets them burning (3s x 5) | flamethrower, burns
--   Ice        ice shards; the big one freezes them in ice up to the neck  | frost beam, freezes
--                                                                           after 5s on someone
--   Earth      rocks; the third is an earth wave along the ground          | sand blast, pushes back
--   Water      water orbs; the big one soaks them (half speed for 3s)      | water jet, shoves + soaks
--   Energy     energy orbs; the big one bursts and throws everyone far     | energy beam
-- Clash: two beams pointed at each other lock together; both mash F, the clash point slides
--   toward whoever's slower, the loser gets hit by the winner's effect AND their own (Effect).
-- Settings + the arm poses (NinjaAnimator calls Step every frame, on every client).
-- The server (ElementPowersServer) sets these attributes on the character: PowerElement,
--   PowerMove + PowerId (a shot started), PowerBeam (beam on), PowerAim (where it points)

local Players = game:GetService("Players")

local Powers = {}

Powers.DemoBot = true -- a Lightning bot behind the Lightning Spinjitzu bot that shows the powers on a loop
Powers.LocalAim = nil -- set every frame by ElementPowersClient while you beam: your arms follow your mouse
Powers.HoldTime = 0.22 -- hold left click this long and it's the beam instead of a shot

local THROW = "rbxassetid://9114276859"
local HITS = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" }
local BOOM = "rbxassetid://73278613369675"
local ZAP = "rbxassetid://9114277757"

-- shared shape of the combo: right, left, both hands (the third one is each element's own)
local function combo(damage, size, third)
	third.name, third.time, third.release, third.hands = "ballBoth", third.time or 0.6, third.release or 0.55, "B"
	third.final = true
	return {
		{ name = "ballR", time = 0.35, release = 0.45, damage = damage, size = size, hands = "R" },
		{ name = "ballL", time = 0.35, release = 0.45, damage = damage, size = size, hands = "L" },
		third,
	}
end

-- Shot = how the shots look (lightning / fire / ice / rock / water / energy).
-- Status on the third shot: "shock" / "burn" (StatusTime seconds, StatusDamage each second),
-- "freeze" (FreezeTime), "slow" (SlowTime, half speed), "blast" (thrown far back).
-- Effect = what this element does to someone who loses a beam clash (same names + "launch").
-- Beam: BeamStatus "burn" / "freeze" (after FreezeAfter seconds on the same target) / "push" /
-- "soak" (push + slow).
-- BeamStyle: colours of the beam's core / glow / haze, crackling arcs, a particle stream.
Powers.Lightning = {
	Shot = "lightning",
	Color = Color3.fromRGB(90, 200, 255),
	CoreColor = Color3.fromRGB(235, 250, 255),
	HitColor = Color3.fromRGB(90, 200, 255),
	HitTextColor = Color3.fromRGB(150, 215, 255),
	Sounds = { Throw = THROW, Hit = HITS, Final = BOOM, Zap = ZAP,
		BeamLoop = "" }, -- optional: a looping electric hum (asset id); "" = crackling zaps instead
	BallSpeed = 110,              -- studs/s
	BallRange = 160,              -- studs before it fizzles out
	ComboWindow = 1.2,            -- seconds to click again to continue
	Balls = combo(10, 1.1, { damage = 26, size = 2.6, blast = 9, status = "shock" }),
	StatusTime = 3, StatusDamage = 5,
	Effect = "shock",
	BeamRange = 70,               -- studs
	BeamDamage = 4,               -- per tick
	BeamTick = 0.15,              -- seconds between damage ticks
	BeamRadius = 0.9,             -- how thick the beam is for hitting
	BeamStyle = { core = Color3.fromRGB(235, 250, 255), glow = Color3.fromRGB(90, 200, 255), haze = Color3.fromRGB(90, 200, 255),
		arcs = true, crackle = true },
}

Powers.Fire = {
	Shot = "fire",
	Color = Color3.fromRGB(255, 110, 20),
	CoreColor = Color3.fromRGB(255, 230, 140),
	HitColor = Color3.fromRGB(255, 120, 25),
	HitTextColor = Color3.fromRGB(255, 190, 90),
	Sounds = { Throw = THROW, Hit = HITS, Final = BOOM },
	BallSpeed = 95,
	BallRange = 140,
	ComboWindow = 1.2,
	Balls = combo(10, 1.3, { damage = 24, size = 3, blast = 10, status = "burn" }),
	StatusTime = 3, StatusDamage = 5,
	Effect = "burn",
	BeamRange = 30,               -- a flamethrower doesn't reach far
	BeamDamage = 2,
	BeamTick = 0.15,
	BeamRadius = 1.6,
	BeamStatus = "burn",          -- keeps them burning while it's on them
	BeamStyle = { core = Color3.fromRGB(255, 240, 160), glow = Color3.fromRGB(255, 140, 30), haze = Color3.fromRGB(220, 50, 10),
		stream = { texture = "rbxasset://textures/particles/fire_main.dds", from = Color3.fromRGB(255, 220, 90),
			to = Color3.fromRGB(230, 50, 10), size = 1.4, speed = 45 } },
}

Powers.Ice = {
	Shot = "ice",
	Color = Color3.fromRGB(150, 225, 255),
	CoreColor = Color3.fromRGB(240, 252, 255),
	HitColor = Color3.fromRGB(120, 210, 255),
	HitTextColor = Color3.fromRGB(180, 235, 255),
	Sounds = { Throw = THROW, Hit = HITS, Final = BOOM },
	BallSpeed = 120,
	BallRange = 160,
	ComboWindow = 1.2,
	Balls = combo(10, 1.0, { damage = 18, size = 2.2, status = "freeze" }),
	FreezeTime = 2.5,             -- seconds frozen (ice up to the neck, can't move)
	Effect = "freeze",
	BeamRange = 60,
	BeamDamage = 3,
	BeamTick = 0.15,
	BeamRadius = 1.0,
	BeamStatus = "freeze",
	FreezeAfter = 5,              -- seconds the beam has to stay on someone before they freeze
	BeamStyle = { core = Color3.fromRGB(245, 253, 255), glow = Color3.fromRGB(150, 225, 255), haze = Color3.fromRGB(200, 240, 255),
		stream = { texture = "rbxasset://textures/particles/sparkles_main.dds", from = Color3.fromRGB(255, 255, 255),
			to = Color3.fromRGB(150, 225, 255), size = 0.5, speed = 50 } },
}

Powers.Earth = {
	Shot = "rock",
	Color = Color3.fromRGB(190, 140, 75),
	CoreColor = Color3.fromRGB(235, 200, 140),
	HitColor = Color3.fromRGB(230, 150, 60),
	HitTextColor = Color3.fromRGB(255, 205, 130),
	RockColor = Color3.fromRGB(115, 82, 50),
	Sounds = { Throw = THROW, Hit = HITS, Final = BOOM },
	BallSpeed = 85,
	BallRange = 120,
	ComboWindow = 1.2,
	-- the third: rocks burst out of the ground in a line toward the aim, throwing everyone up
	Balls = combo(12, 1.4, { damage = 22, size = 0, wave = { length = 40, step = 2.5, radius = 4, up = 48 }, time = 0.6 }),
	Effect = "launch",            -- thrown high up
	BeamRange = 35,
	BeamDamage = 2,
	BeamTick = 0.15,
	BeamRadius = 2.2,
	BeamStatus = "push",          -- the sand pushes them back
	BeamStyle = { core = Color3.fromRGB(235, 205, 150), glow = Color3.fromRGB(200, 150, 85), haze = Color3.fromRGB(160, 115, 65),
		stream = { texture = "rbxasset://textures/particles/smoke_main.dds", from = Color3.fromRGB(225, 190, 130),
			to = Color3.fromRGB(150, 105, 60), size = 3, speed = 40 } },
}

Powers.Water = {
	Shot = "water",
	Color = Color3.fromRGB(40, 150, 255),
	CoreColor = Color3.fromRGB(200, 240, 255),
	HitColor = Color3.fromRGB(60, 170, 255),
	HitTextColor = Color3.fromRGB(150, 210, 255),
	Sounds = { Throw = THROW, Hit = HITS, Final = BOOM },
	BallSpeed = 100,
	BallRange = 150,
	ComboWindow = 1.2,
	Balls = combo(10, 1.2, { damage = 20, size = 2.8, blast = 9, status = "slow" }),
	SlowTime = 3,                 -- soaked: half speed for this long
	Effect = "slow",
	BeamRange = 45,
	BeamDamage = 2,
	BeamTick = 0.15,
	BeamRadius = 1.5,
	BeamStatus = "soak",          -- shoves them back and soaks them
	BeamStyle = { core = Color3.fromRGB(220, 245, 255), glow = Color3.fromRGB(60, 160, 255), haze = Color3.fromRGB(30, 110, 220),
		stream = { texture = "rbxasset://textures/particles/smoke_main.dds", from = Color3.fromRGB(220, 240, 255),
			to = Color3.fromRGB(40, 130, 255), size = 1.8, speed = 55 } },
}

Powers.Energy = {
	Shot = "energy",
	Color = Color3.fromRGB(70, 230, 60),
	CoreColor = Color3.fromRGB(235, 255, 150),
	HitColor = Color3.fromRGB(110, 240, 80),
	HitTextColor = Color3.fromRGB(190, 255, 140),
	Sounds = { Throw = THROW, Hit = HITS, Final = BOOM },
	BallSpeed = 105,
	BallRange = 160,
	ComboWindow = 1.2,
	-- the big one bursts with rays of light and throws everyone far back
	Balls = combo(11, 1.3, { damage = 26, size = 3, blast = 11, status = "blast" }),
	Effect = "blast",
	BeamRange = 70,
	BeamDamage = 5,
	BeamTick = 0.15,
	BeamRadius = 1.1,
	BeamStyle = { core = Color3.fromRGB(240, 255, 180), glow = Color3.fromRGB(80, 235, 60), haze = Color3.fromRGB(40, 190, 40),
		arcs = true, stream = { texture = "rbxasset://textures/particles/sparkles_main.dds", from = Color3.fromRGB(240, 255, 170),
			to = Color3.fromRGB(80, 235, 60), size = 0.6, speed = 55 } },
}

Powers.ByElement = { Lightning = Powers.Lightning, Fire = Powers.Fire, Ice = Powers.Ice, Earth = Powers.Earth,
	Water = Powers.Water, Energy = Powers.Energy }

-- beam clash: mash this key; each press pushes the clash point this much of the way
Powers.ClashKey = Enum.KeyCode.F
Powers.ClashPush = 0.025
Powers.ClashDamage = 30         -- the loser takes this, plus both elements' effects
Powers.ClashMaxTime = 15        -- nobody won by then: both get knocked back

-- the NPC you fight (menu > Duels > Fight an NPC)
Powers.FightNPC = {
	Health = 400,
	MashRate = 4.5,               -- presses a second in a clash (a quick human does 6-8)
	DamageScale = 0.4,            -- its shots and beams do this much of the normal damage
	Pause = { 3.5, 5.5 },         -- seconds between its attacks
	BeamTime = 2,                 -- seconds it holds a beam
}

----------------------------------------------------------------------------------------
-- arm poses (NinjaAnimator convention: +x swings a hanging arm forward, +z swings the
-- right arm out / the left arm in)
----------------------------------------------------------------------------------------

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
local function R(x, y, z) return CFrame.Angles(x or 0, y or 0, z or 0) end

-- pull the hand back by the hip, then punch the palm straight out
local function push(pose, side, e)
	local name = side > 0 and "Right" or "Left"
	local back, out = R(-0.35, 0, 0.3 * side), R(1.55, 0, 0.05 * side)
	local sh, el
	if e < 0.4 then
		local s = smooth(e / 0.4)
		sh, el = R(0.2, 0, 0.15 * side):Lerp(back, s), lerp(0.6, 1.7, s)
	elseif e < 0.55 then
		local s = smooth((e - 0.4) / 0.15)
		sh, el = back:Lerp(out, s), lerp(1.7, 0.05, s)
	else
		local s = smooth((e - 0.55) / 0.45)
		sh, el = out:Lerp(R(0.5, 0, 0.15 * side), s * 0.6), lerp(0.05, 0.4, s)
	end
	pose[name .. "Shoulder"] = sh
	pose[name .. "Elbow"] = R(el, 0, 0)
end

local states = setmetatable({}, { __mode = "k" }) -- [character] = { id, move, t }

local function ballFor(P, name)
	for _, b in ipairs(P and P.Balls or {}) do
		if b.name == name then return b end
	end
	return nil
end

function Powers.Step(character, root, pose, dt, armsFree)
	if character:FindFirstChildOfClass("Tool") then return pose end
	local st = states[character]
	if not st then
		st = { id = character:GetAttribute("PowerId") or 0 }
		states[character] = st
	end
	local id = character:GetAttribute("PowerId") or 0
	if id ~= st.id then
		st.id = id
		st.move, st.t = ballFor(Powers.ByElement[character:GetAttribute("PowerElement") or ""], character:GetAttribute("PowerMove") or ""), 0
	end
	if not armsFree then return pose end

	local out = pose
	if st.move then
		out = table.clone(pose)
		st.t += dt
		local e = math.clamp(st.t / st.move.time, 0, 1)
		if st.move.hands == "B" then
			push(out, 1, e)
			push(out, -1, e)
			out.Waist = R(lerp(0.15, -0.2, smooth((e - 0.4) / 0.2)), 0, 0) * (out.Waist or CFrame.identity)
		else
			local side = st.move.hands == "R" and 1 or -1
			push(out, side, e)
			-- turn into it: away on the wind-up, into the push on the release
			local turn = e < 0.4 and lerp(0, -0.3, smooth(e / 0.4)) or lerp(-0.3, 0.2, smooth((e - 0.4) / 0.25))
			out.Waist = R(0, turn * side, 0) * (out.Waist or CFrame.identity)
		end
		if e >= 1 then st.move = nil end
	end

	-- beam: both arms straight out toward the aim, hands close together, trembling a little
	local aim = character:GetAttribute("PowerAim")
	local me = Players.LocalPlayer
	if Powers.LocalAim and me and character == me.Character then aim = Powers.LocalAim end
	if character:GetAttribute("PowerBeam") and typeof(aim) == "Vector3" then
		out = out == pose and table.clone(pose) or out
		local d = root.CFrame:VectorToObjectSpace(aim - (root.Position + Vector3.new(0, 1.5, 0)))
		local pitch = d.Magnitude > 0.1 and math.asin(math.clamp(d.Unit.Y, -0.9, 0.9)) or 0
		local t = os.clock()
		local shake = math.sin(t * 47) * 0.03 + math.sin(t * 31) * 0.02
		-- (+z swings the right arm out and the left arm in, so both point inward)
		out.RightShoulder = R(math.pi / 2 + pitch + shake, 0, -0.32)
		out.RightElbow = R(0.12, 0, 0)
		out.LeftShoulder = R(math.pi / 2 + pitch - shake, 0, 0.32)
		out.LeftElbow = R(0.12, 0, 0)
		out.Waist = R(0.08, 0, 0) * (out.Waist or CFrame.identity) -- lean back into it
	end
	return out
end

-- Rising Dragon: while the dragon is out (rising / flying) your power comes out of its mouth, and
-- its head turns to look where the power goes (DragonNeck). nil = not on the dragon
local DragonModel, DragonNeck -- (loaded the first time they're needed; false = missing)
function Powers.DragonMouth(character)
	local phase = character and character:GetAttribute("DragonPhase")
	if phase ~= "rise" and phase ~= "fly" then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	if DragonModel == nil then
		local function load(name)
			local m = script.Parent:FindFirstChild(name)
			local ok, res = pcall(function() return m and require(m) end)
			return ok and res or false
		end
		DragonModel, DragonNeck = load("DragonModel"), load("DragonNeck")
	end
	if not DragonModel or not DragonNeck then return nil end
	-- the dragon you can see (on a client) says exactly where its mouth is
	local live = DragonNeck.Live[character]
	if live then return live end
	local config = script.Parent:FindFirstChild("SpinjitzuConfig")
	local okC, Config = pcall(function() return require(config) end)
	local okS, s = pcall(function() return character:GetScale() end)
	local scale = (okS and s or 1) * (okC and Config.DragonScale or 1)
	local aim = character:GetAttribute("PowerBeam") and character:GetAttribute("PowerAim")
	local look = typeof(aim) == "Vector3" and DragonNeck.LookAt(DragonModel, root.CFrame, scale, aim) or nil
	return root.CFrame:PointToWorldSpace(DragonNeck.Mouth(DragonModel, look) * scale)
end

return Powers
