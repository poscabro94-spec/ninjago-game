-- ElementPowers v1.0  (ModuleScript in ReplicatedStorage)
-- Elemental powers, used with empty hands (no Golden Weapon out). For now: Lightning.
--   left click:        lightning ball from the right hand -> the left hand -> a big one from
--                      both hands that explodes
--   hold right click:  lightning beam to where you aim
-- Settings + the arm poses (NinjaAnimator calls Step every frame, on every client).
-- The server (ElementPowersServer) sets these attributes on the character:
--   PowerMove + PowerId (a throw started), PowerBeam (beam on), PowerAim (where it points)

local Powers = {}

Powers.Lightning = {
	Color = Color3.fromRGB(90, 200, 255),
	CoreColor = Color3.fromRGB(235, 250, 255),
	HitColor = Color3.fromRGB(90, 200, 255),
	HitTextColor = Color3.fromRGB(150, 215, 255),
	Sounds = {
		Throw = "rbxassetid://9114276859",
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
		Zap = "rbxassetid://9114277757",
	},
	BallSpeed = 110,              -- studs/s
	BallRange = 160,              -- studs before it fizzles out
	ComboWindow = 1.2,            -- seconds to click again to continue
	Balls = {
		{ name = "ballR",    time = 0.35, release = 0.45, damage = 10, size = 1.1, hands = "R" },
		{ name = "ballL",    time = 0.35, release = 0.45, damage = 10, size = 1.1, hands = "L" },
		{ name = "ballBoth", time = 0.6,  release = 0.55, damage = 26, size = 2.6, hands = "B", blast = 9, final = true },
	},
	BeamRange = 70,               -- studs
	BeamDamage = 4,               -- per tick
	BeamTick = 0.15,              -- seconds between damage ticks
	BeamRadius = 0.9,             -- how thick the beam is for hitting
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

local function ballFor(name)
	for _, b in ipairs(Powers.Lightning.Balls) do
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
		st.move, st.t = ballFor(character:GetAttribute("PowerMove") or ""), 0
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

	-- beam: right arm straight out toward the aim, left hand braced under the wrist
	local aim = character:GetAttribute("PowerAim")
	if character:GetAttribute("PowerBeam") and typeof(aim) == "Vector3" then
		out = out == pose and table.clone(pose) or out
		local d = root.CFrame:VectorToObjectSpace(aim - (root.Position + Vector3.new(0, 1.5, 0)))
		local pitch = d.Magnitude > 0.1 and math.asin(math.clamp(d.Unit.Y, -0.9, 0.9)) or 0
		out.RightShoulder = R(math.pi / 2 + pitch, 0, 0)
		out.RightElbow = R(0, 0, 0)
		out.LeftShoulder = R(math.pi / 2 + pitch - 0.25, 0, 0.5) -- (+z = left arm in, toward the right hand)
		out.LeftElbow = R(0.6, 0, 0)
	end
	return out
end

return Powers
