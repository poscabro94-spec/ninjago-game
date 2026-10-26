-- NinjaAnimator v1.6  (ModuleScript in ReplicatedStorage)
-- Procedural player animations, no animation assets: idle, walk, run, jump, fall, landing,
-- plus the parkour moves (vault, mantle, wall run). Every client animates every player, so
-- everyone sees the same thing. SpinjitzuClient calls NinjaAnimator.Step() in Stepped
-- BEFORE the Spinjitzu / dragon poses, so those still play on top.
-- Bots tagged "AnimatedNPC" (e.g. the Lightning power demo bot) are animated the same way.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GoldenWeapons = require(game:GetService("ReplicatedStorage"):WaitForChild("GoldenWeapons"))
-- optional: if the ElementPowers module is missing, everything else still animates
local ElementPowers
do
	local m = game:GetService("ReplicatedStorage"):WaitForChild("ElementPowers", 5)
	local ok, mod = pcall(function() return m and require(m) end)
	if ok and mod then
		ElementPowers = mod
	else
		warn("[NinjaAnimator] ElementPowers module missing or broken (ReplicatedStorage): no power arm moves", mod)
	end
end

local Animator = {}

local TAU = math.pi * 2
local states = {} -- [character] = per-character animation state

local JOINT_ALIAS = { RootJoint = "Root" }
local JOINTS = {
	Root = true, Waist = true, Neck = true,
	RightShoulder = true, LeftShoulder = true, RightElbow = true, LeftElbow = true,
	RightHip = true, LeftHip = true, RightKnee = true, LeftKnee = true,
}

local function lerp(a, b, t) return a + (b - a) * t end
local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x) return x * x * (3 - 2 * x) end

-- a pose is { key = {x, y, z, offset?} } in the parent part's space:
-- +x swings a hanging limb forward (knees/elbows: -x knee bends back, +x elbow bends forward),
-- z swings an arm/leg outward (sign handled per side), Root/Waist: -x leans forward
local function R(x, y, z, off)
	local cf = CFrame.Angles(x or 0, y or 0, z or 0)
	if off then cf = CFrame.new(off) * cf end
	return cf
end

-- side: 1 = right, -1 = left (so "out" rotations mirror)
local function limb(pose, side, shoulderX, shoulderOut, elbow, hipX, hipOut, knee)
	local S = side > 0 and "Right" or "Left"
	pose[S .. "Shoulder"] = R(shoulderX, 0, (shoulderOut or 0) * side)
	pose[S .. "Elbow"] = R(elbow or 0, 0, 0)
	pose[S .. "Hip"] = R(hipX, 0, (hipOut or 0) * side)
	pose[S .. "Knee"] = R(knee or 0, 0, 0)
end

local function blendPose(a, b, t)
	if t <= 0 then return a end
	if t >= 1 then return b end
	local out = {}
	for k in pairs(JOINTS) do
		local A, B = a[k] or CFrame.identity, b[k] or CFrame.identity
		out[k] = A:Lerp(B, t)
	end
	return out
end

----------------------------------------------------------------------------------------
-- base poses
----------------------------------------------------------------------------------------

local function idlePose(t)
	local b = math.sin(t * 1.7)
	local p = { Root = R(0, 0, 0, Vector3.new(0, b * 0.03, 0)), Waist = R(b * 0.025, 0, 0), Neck = R(-b * 0.02, 0, 0) }
	limb(p, 1, 0.05, 0.08 + b * 0.02, 0.15, 0, 0.03, -0.05)
	limb(p, -1, 0.05, 0.08 + b * 0.02, 0.15, 0, 0.03, -0.05)
	return p
end

-- ph = stride phase, rb = 0 walk .. 1 run
-- right leg forward when s > 0. Legs reach further forward than back, the knee folds while
-- the leg swings through, heels kick up when sprinting, arms pump with bent elbows and the
-- shoulders counter-rotate against the hips.
local function gaitPose(ph, rb)
	local s, c = math.sin(ph), math.cos(ph)
	local hipF, hipB = lerp(0.45, 1.0, rb), lerp(0.35, 0.7, rb)
	local kneeA = lerp(0.65, 1.25, rb)
	local armA = lerp(0.35, 0.85, rb)
	local function hip(x) return x > 0 and x * hipF or x * hipB end
	local function knee(swing, behind)
		return -(lerp(0.08, 0.18, rb) + kneeA * math.max(0, swing) ^ 0.8 + 0.55 * rb * math.max(0, behind))
	end
	local p = {
		Root = R(lerp(-0.04, -0.28, rb), s * lerp(0.06, 0.12, rb), 0, Vector3.new(0, -math.abs(c) * lerp(0.05, 0.12, rb), 0)),
		Waist = R(lerp(0, -0.05, rb), -s * lerp(0.12, 0.24, rb), 0),
		Neck = R(lerp(0.03, 0.24, rb), s * 0.08, 0),
	}
	local fwdBias = lerp(0.05, 0.2, rb)
	local elbow = lerp(0.3, 1.25, rb)
	limb(p, 1, -s * armA + fwdBias, 0.08, elbow + 0.3 * math.max(0, -s), hip(s), 0, knee(c, -s))
	limb(p, -1, s * armA + fwdBias, 0.08, elbow + 0.3 * math.max(0, s), hip(-s), 0, knee(-c, s))
	return p
end

local function jumpPose()
	local p = { Root = R(-0.1, 0, 0), Waist = R(-0.05, 0, 0), Neck = R(0.05, 0, 0) }
	limb(p, 1, 0.6, 0.55, 0.45, 1.0, 0.05, -1.4)
	limb(p, -1, 0.3, 0.55, 0.45, -0.1, 0.05, -0.45)
	return p
end

local function fallPose(t)
	local f = math.sin(t * 9) * 0.06
	local p = { Root = R(0.05, 0, 0), Waist = R(0, 0, 0), Neck = R(-0.1, 0, 0) }
	limb(p, 1, 0.2 + f, 1.1, 0.35, 0.35, 0.08, -0.65)
	limb(p, -1, 0.2 - f, 1.1, 0.35, 0.05, 0.08, -0.3)
	return p
end

local function landPose(k)
	local p = { Root = R(-0.3 * k, 0, 0, Vector3.new(0, -0.75 * k, 0)), Waist = R(-0.15 * k, 0, 0), Neck = R(0.25 * k, 0, 0) }
	limb(p, 1, 0.35 * k, 0.35 * k, 0.5 * k, 0.95 * k, 0.1 * k, -1.55 * k)
	limb(p, -1, 0.35 * k, 0.35 * k, 0.5 * k, 0.95 * k, 0.1 * k, -1.55 * k)
	return p
end

----------------------------------------------------------------------------------------
-- parkour poses (t = seconds since the move started)
----------------------------------------------------------------------------------------

local function vaultPose(t)
	local k = smooth(t / 0.12)
	local p = { Root = R(-0.5 * k, 0, 0.3 * k), Waist = R(-0.15 * k, 0, 0), Neck = R(0.35 * k, 0, 0) }
	limb(p, 1, 1.3 * k, 0.1, 0.1, 1.45 * k, 0.15, -1.7 * k)   -- right hand planted forward-down, leg tucked
	limb(p, -1, 0.7 * k, 0.9 * k, 0.3, 0.65 * k, 0.5 * k, -0.7 * k)
	return p
end

local function mantlePose(t)
	local pull = smooth(t / 0.15) * (1 - smooth((t - 0.25) / 0.15))
	local push = smooth((t - 0.25) / 0.15)
	local reach = { Root = R(-0.2, 0, 0), Waist = R(-0.1, 0, 0), Neck = R(-0.3, 0, 0) }
	limb(reach, 1, 2.8, 0.15, 0.55, 0.3, 0, -0.8)
	limb(reach, -1, 2.8, 0.15, 0.55, 0.6, 0, -1.2)
	local up = { Root = R(-0.45, 0, 0, Vector3.new(0, -0.3, 0)), Waist = R(-0.2, 0, 0), Neck = R(0.3, 0, 0) }
	limb(up, 1, 0.35, 0.3, 0.2, 1.55, 0.1, -1.85)
	limb(up, -1, 0.35, 0.3, 0.2, 0.25, 0.1, -0.55)
	return blendPose(blendPose(idlePose(0), reach, math.max(pull, 1 - push)), up, push)
end

local function wallRunPose(ph, side)
	local p = gaitPose(ph, 1)
	-- arm on the wall side reaches out to the wall, body leans into the run
	local S = side > 0 and "Right" or "Left"
	p[S .. "Shoulder"] = R(0.3, 0, 1.25 * side)
	p[S .. "Elbow"] = R(0.35, 0, 0)
	return p
end

----------------------------------------------------------------------------------------
-- per character
----------------------------------------------------------------------------------------

local function collectJoints(character)
	local joints = {}
	for _, m in ipairs(character:GetDescendants()) do
		local isMotor, isAnim = m:IsA("Motor6D"), m:IsA("AnimationConstraint")
		if isMotor or isAnim then
			local key = (m.Name:gsub(" ", ""))
			key = JOINT_ALIAS[key] or key
			local c0 = isMotor and m.C0 or (m.Attachment0 and m.Attachment0.CFrame)
			if JOINTS[key] and c0 then
				joints[key] = { motor = m, rot = c0.Rotation, cur = CFrame.identity }
			end
		end
	end
	return joints
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function grounded(character, root, humanoid)
	local list = { character }
	local fx = workspace:FindFirstChild("SpinjitzuFX")
	if fx then table.insert(list, fx) end
	rayParams.FilterDescendantsInstances = list
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.6
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams) ~= nil
end

local function reset(st)
	for _, j in pairs(st.joints) do
		if j.motor.Parent then j.motor.Transform = CFrame.identity end
		j.cur = CFrame.identity
	end
end

-- character is paused (Spinjitzu dragon / Creation own the body)
local function paused(character)
	return character:GetAttribute("DragonPhase") ~= nil or character:GetAttribute("CreationPhase") ~= nil
end

function Animator.Step(dt)
	dt = math.min(dt, 0.1)
	local characters = CollectionService:GetTagged("AnimatedNPC")
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(characters, player.Character) end
	end
	for _, character in ipairs(characters) do
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local st = states[character]
			if not st then
				st = { joints = collectJoints(character), t = 0, ph = 0, air = 0, land = 0, wasAir = false, move = nil, moveT = 0, rb = 0 }
				states[character] = st
			end
			if paused(character) then
				if not st.paused then reset(st) st.paused = true end
			else
				st.paused = false
				st.t += dt
				local vel = root.AssemblyLinearVelocity
				local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
				local onGround = grounded(character, root, humanoid)

				local move = character:GetAttribute("ParkourMove")
				if move ~= st.move then st.move, st.moveT = move, 0 end
				st.moveT += dt

				local pose
				if move == "vault" then
					pose = vaultPose(st.moveT)
				elseif move == "mantle" then
					pose = mantlePose(st.moveT)
				elseif move == "wallrunR" or move == "wallrunL" then
					st.ph += dt * (math.max(speed, 20) * 0.5 + 1)
					pose = wallRunPose(st.ph, move == "wallrunR" and 1 or -1)
				elseif not onGround then
					st.air += dt
					pose = vel.Y > 2 and jumpPose() or blendPose(jumpPose(), fallPose(st.t), smooth((2 - vel.Y) / 14))
				else
					if st.wasAir and st.air > 0.35 then st.land = 0.28 end
					st.air = 0
					local rbTarget = clamp01((speed - 8) / 12)
					st.rb = lerp(st.rb, rbTarget, 1 - math.exp(-dt * 6))
					if speed > 0.6 then
						st.ph = (st.ph + dt * (speed * 0.5 + 1.2)) % TAU
						pose = blendPose(idlePose(st.t), gaitPose(st.ph, st.rb), smooth(speed / 3))
					else
						pose = idlePose(st.t)
					end
					if st.land > 0 then
						st.land -= dt
						pose = blendPose(pose, landPose(1), smooth(st.land / 0.12))
					end
				end
				st.wasAir = not onGround and move == nil
				pose = GoldenWeapons.Step(character, root, pose, dt, move == nil)
				if ElementPowers then pose = ElementPowers.Step(character, root, pose, dt, move == nil) end

				local a = 1 - math.exp(-dt * (move and 22 or 14))
				for key, j in pairs(st.joints) do
					if j.motor.Parent then
						j.cur = j.cur:Lerp(pose[key] or CFrame.identity, a)
						j.motor.Transform = j.rot:Inverse() * j.cur * j.rot
					end
				end
			end
		end
	end
	for character, st in pairs(states) do
		if not character.Parent then states[character] = nil end
	end
end

-- stop the default Animate script on your own character (its animations replicate,
-- so this stops them for everyone; every client then animates you procedurally)
function Animator.TakeOver(character)
	task.spawn(function()
		local animate = character:WaitForChild("Animate", 10)
		if animate then animate.Disabled = true end
		local hum = character:WaitForChild("Humanoid", 10)
		local animator = hum and hum:WaitForChild("Animator", 10)
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
			animator.AnimationPlayed:Connect(function(track)
				if animate and animate.Disabled then track:Stop(0) end
			end)
		end
	end)
end

return Animator
