-- NinjaParkour v1.5  (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Parkour for your own character:
--   Hurdle / vault: run into a low obstacle (waist high) and you vault over it.
--   Mantle: jump at (or walk into while in the air) a ledge up to ~head+ height and you climb it.
--   Wall run: jump next to a wall while running along it. Space = wall jump off it.
--   Sprint: hold Left Shift.
--   On a wall: Space = wall jump, steer away from the wall = hop off.
-- The move name is sent to the server so every client can play the right pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local P = {
	WalkSpeed = 16,
	SprintSpeed = 26,
	SprintKey = Enum.KeyCode.LeftShift,
	VaultMinHeight = 1.0,   -- studs above your feet
	VaultMaxHeight = 3.4,
	VaultMaxDepth = 5,      -- longer than this and you climb onto it instead
	VaultMinSpeed = 8,
	MantleMaxHeight = 7.5,
	WallRunMinSpeed = 7,
	WallRunTime = 1.8,      -- seconds on one wall
	WallRunSpeed = 30,
	WallJumpOut = 32,
	WallJumpUp = 42,
}

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NinjaParkour")

local move = nil       -- current move state
local cooldown = 0
local lastWallNormal = nil
local jumpQueued = false

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function cast(from, dir)
	return workspace:Raycast(from, dir, params)
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or nil
end

local function setMove(character, name)
	character:SetAttribute("ParkourMove", name) -- instant locally
	remote:FireServer(name)                    -- replicated to everyone
end

local function busy(character)
	return character:GetAttribute("SpinjitzuActive") or character:GetAttribute("DragonPhase")
		or character:GetAttribute("CreationPhase")
end

----------------------------------------------------------------------------------------
-- driving the body along a path (works with Roblox physics, replicates to everyone)
----------------------------------------------------------------------------------------

local function begin(character, root, humanoid, name, data)
	local att = Instance.new("Attachment")
	att.Name = "ParkourAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = root.AssemblyLinearVelocity
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 30
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	move = data
	move.name, move.t, move.att, move.lv, move.ao = name, 0, att, lv, ao
	move.character, move.root, move.humanoid = character, root, humanoid
	setMove(character, name)
end

local function finish(exitVelocity)
	if not move then return end
	local m = move
	move = nil
	for _, inst in ipairs({ m.lv, m.ao, m.att }) do inst:Destroy() end
	if m.humanoid.Parent then
		m.humanoid.PlatformStand = false
		m.humanoid.AutoRotate = true
		m.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if exitVelocity and m.root.Parent then m.root.AssemblyLinearVelocity = exitVelocity end
	setMove(m.character, nil)
	cooldown = 0.25
end

local function bezier(a, b, c, t)
	return a * (1 - t) ^ 2 + b * 2 * (1 - t) * t + c * t * t
end

-- follow path(t) over `dur` seconds
local function followPath(dt)
	local m = move
	m.t += dt
	local f = math.clamp(m.t / m.dur, 0, 1)
	local fNext = math.clamp((m.t + dt) / m.dur, 0, 1)
	local target = m.path(fNext)
	local v = (target - m.root.Position) / math.max(dt, 1 / 240)
	if v.Magnitude > 150 then v = v.Unit * 150 end
	m.lv.VectorVelocity = v
	m.ao.CFrame = CFrame.lookAt(Vector3.zero, m.dir)
	return f >= 1
end

----------------------------------------------------------------------------------------
-- detection
----------------------------------------------------------------------------------------

local function feetY(root, humanoid)
	return root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
end

-- top of whatever is in front, scanning down from `fromY`
local function topAt(pos, fromY, depth)
	local hit = cast(Vector3.new(pos.X, fromY, pos.Z), Vector3.new(0, -depth, 0))
	return hit and hit.Position.Y, hit
end

local function tryVault(root, humanoid, fwd, speed)
	if speed < P.VaultMinSpeed then return false end
	local fy = feetY(root, humanoid)
	local reach = 2.2 + speed * 0.06
	local hit = cast(Vector3.new(root.Position.X, fy + 0.8, root.Position.Z), fwd * reach)
	if not hit or math.abs(hit.Normal.Y) > 0.4 then return false end
	local probeY = fy + P.VaultMaxHeight + 0.6
	local top = topAt(hit.Position + fwd * 0.3, probeY, P.VaultMaxHeight + 0.6)
	if not top then return false end
	local h = top - fy
	if h < P.VaultMinHeight or h > P.VaultMaxHeight then return false end
	-- something tall right behind it? that's a wall, not a hurdle
	if cast(Vector3.new(root.Position.X, top + 1.6, root.Position.Z), fwd * (reach + 1.5)) then return false end
	-- find the far side
	local landX = nil
	for d = 0.8, P.VaultMaxDepth, 0.4 do
		local t2 = topAt(hit.Position + fwd * d, top + 0.5, 12)
		if not t2 or t2 < top - 0.6 then landX = d break end
	end
	local rootOff = root.Position.Y - fy
	local p0 = root.Position
	local over = hit.Position + fwd * ((landX or 1) * 0.5)
	local mid = Vector3.new(over.X, top + rootOff + 0.5, over.Z)
	local landing
	if landX then
		local far = hit.Position + fwd * (landX + 2.2)
		local gy = topAt(far, top + 1, 30) or fy
		landing = Vector3.new(far.X, gy + rootOff, far.Z)
	else
		local far = hit.Position + fwd * 1.6 -- long block: hop up onto it
		landing = Vector3.new(far.X, top + rootOff, far.Z)
	end
	local dist = (landing - p0).Magnitude
	local dur = math.clamp(dist / math.max(speed, 18), 0.32, 0.6)
	begin(root.Parent, root, humanoid, "vault", {
		dur = dur, dir = fwd, exitSpeed = math.max(speed, P.WalkSpeed),
		path = function(f) return bezier(p0, mid, landing, f) end,
	})
	return true
end

local function tryMantle(root, humanoid, fwd, needAir)
	local fy = feetY(root, humanoid)
	local hit = cast(root.Position, fwd * 2.4)
	if not hit then hit = cast(root.Position + Vector3.new(0, 1.5, 0), fwd * 2.4) end
	if not hit or math.abs(hit.Normal.Y) > 0.4 then return false end
	local n = flat(hit.Normal)
	if not n then return false end
	local into = -n
	local top = topAt(hit.Position + into * 0.7, fy + P.MantleMaxHeight + 0.6, P.MantleMaxHeight + 0.6)
	if not top then return false end
	local h = top - fy
	if h <= (needAir and 1.5 or P.VaultMaxHeight) or h > P.MantleMaxHeight then return false end
	-- room to stand on top
	if cast(Vector3.new(hit.Position.X, top + 0.2, hit.Position.Z) + into * 1.2, Vector3.new(0, 4.5, 0)) then return false end
	local rootOff = root.Position.Y - fy
	local p0 = root.Position
	local up = Vector3.new(p0.X, top + rootOff + 0.4, p0.Z) + into * 0.3
	local stand = Vector3.new(hit.Position.X, top + rootOff, hit.Position.Z) + into * 1.6
	begin(root.Parent, root, humanoid, "mantle", {
		dur = 0.55, dir = into, exitSpeed = 6,
		path = function(f)
			if f < 0.6 then return p0:Lerp(up, math.sin(f / 0.6 * math.pi / 2)) end
			return up:Lerp(stand, (f - 0.6) / 0.4)
		end,
	})
	return true
end

-- a wall beside you that you could run along: side (1 right / -1 left), wall normal, run direction
local function findWall(root, fwd, maxFacing, ahead)
	local right = fwd:Cross(Vector3.yAxis)
	local dirs = { right, -right }
	if ahead then -- flying at a wall: also look ahead and diagonally
		table.insert(dirs, (fwd + right).Unit)
		table.insert(dirs, (fwd - right).Unit)
		table.insert(dirs, fwd)
	end
	for _, rd in ipairs(dirs) do
		local hit = cast(root.Position, rd * 3.6)
		local side = rd:Dot(right) >= 0 and 1 or -1
		if hit and math.abs(hit.Normal.Y) < 0.25 then
			local n = flat(hit.Normal)
			if n and math.abs(fwd:Dot(n)) < maxFacing and not (lastWallNormal and n:Dot(lastWallNormal) > 0.7) then
				local d = fwd - n * fwd:Dot(n)
				if d.Magnitude > 0.2 then return side, n, d.Unit end
			end
		end
	end
	return nil
end

local function startWallRun(root, humanoid, side, n, dir, speed, vy)
	side = dir:Cross(Vector3.yAxis):Dot(-n) > 0 and 1 or -1 -- which side of the run the wall is on
	begin(root.Parent, root, humanoid, side > 0 and "wallrunR" or "wallrunL", {
		wall = true, side = side, n = n, dir = dir, dur = P.WallRunTime,
		speed = math.max(speed, P.WallRunSpeed), vy = math.clamp(vy, 1, 6),
	})
	lastWallNormal = n
end

local function tryWallRun(root, humanoid, fwd, speed)
	if speed < P.WallRunMinSpeed then return false end
	local side, n, dir = findWall(root, fwd, 0.75)
	if not side then return false end
	startWallRun(root, humanoid, side, n, dir, speed, root.AssemblyLinearVelocity.Y)
	return true
end

-- flying off a wall after a wall jump (keeps the push; grabs the next wall)
local function airStep(dt)
	local m = move
	m.t += dt
	m.v -= Vector3.new(0, workspace.Gravity * dt, 0)
	m.lv.VectorVelocity = m.v
	local hv = flat(m.v)
	if hv then m.ao.CFrame = CFrame.lookAt(Vector3.zero, hv) end
	local root, humanoid = m.root, m.humanoid
	if m.t > 0.06 and hv then
		local side, n, dir = findWall(root, hv, 0.95, true)
		if side then
			local speed = Vector3.new(m.v.X, 0, m.v.Z).Magnitude
			local vy = m.v.Y
			finish(nil)
			startWallRun(root, humanoid, side, n, dir, speed, vy)
			return
		end
	end
	local down = cast(root.Position, Vector3.new(0, -(humanoid.HipHeight + root.Size.Y / 2 + 0.4), 0))
	if m.t > m.dur or (down and m.t > 0.1) then finish(m.v) end
end

local function wallRunStep(dt)
	local m = move
	m.t += dt
	local root = m.root
	local hit = cast(root.Position, -m.n * 4.2)
	local down = cast(root.Position, Vector3.new(0, -(m.humanoid.HipHeight + root.Size.Y / 2 + 0.3), 0))
	if not hit or m.t > m.dur or (down and m.t > 0.15) then
		finish(m.dir * m.speed * 0.8 + Vector3.new(0, math.min(m.vy, 0), 0))
		return
	end
	m.n = flat(hit.Normal) or m.n
	m.dir = (m.dir - m.n * m.dir:Dot(m.n)).Unit
	m.vy -= 10 * dt
	local keep = (1.5 - hit.Distance) * 10
	m.lv.VectorVelocity = m.dir * m.speed + m.n * keep + Vector3.new(0, m.vy, 0)
	-- tilt so the feet are on the wall
	m.ao.CFrame = CFrame.lookAt(Vector3.zero, m.dir) * CFrame.Angles(0, 0, 0.4 * m.side)
	-- Space = wall jump; steering away from the wall = hop off
	local md = m.humanoid.MoveDirection
	local hop = jumpQueued and m.t > 0.08
	local drop = md.Magnitude > 0.1 and md:Dot(m.n) > 0.55 and m.t > 0.12
	if hop or drop then
		jumpQueued = false
		local out = hop and (m.n * P.WallJumpOut + Vector3.new(0, P.WallJumpUp, 0) + m.dir * m.speed * 0.6)
			or (m.n * 16 + Vector3.new(0, 10, 0) + m.dir * m.speed * 0.7)
		finish(nil)
		begin(root.Parent, root, m.humanoid, "walljump", { air = true, v = out, dur = 0.8, dir = flat(out) or m.dir })
	end

end

----------------------------------------------------------------------------------------
-- main loop
----------------------------------------------------------------------------------------

-- only a fresh press counts (holding Space keeps firing JumpRequest)
local lastJumpReq = 0
UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	if now - lastJumpReq > 0.2 then jumpQueued = true end
	lastJumpReq = now
end)

player.CharacterAdded:Connect(function()
	if move then move = nil end
	lastWallNormal = nil
end)

RunService.Heartbeat:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		jumpQueued = false
		return
	end
	local list = { character }
	local fx = workspace:FindFirstChild("SpinjitzuFX")
	if fx then table.insert(list, fx) end
	params.FilterDescendantsInstances = list

	if move then
		if not move.root.Parent then move = nil return end
		if move.wall then
			wallRunStep(dt)
		elseif move.air then
			airStep(dt)
		elseif followPath(dt) then
			finish(move.dir * move.exitSpeed)
		end
		jumpQueued = false
		return
	end

	if busy(character) then
		jumpQueued = false
		return
	end

	-- sprint
	local want = UserInputService:IsKeyDown(P.SprintKey) and P.SprintSpeed or P.WalkSpeed
	if humanoid.WalkSpeed ~= want and (humanoid.WalkSpeed == P.WalkSpeed or humanoid.WalkSpeed == P.SprintSpeed) then
		humanoid.WalkSpeed = want
	end

	cooldown -= dt
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local inAir = not cast(root.Position, Vector3.new(0, -(humanoid.HipHeight + root.Size.Y / 2 + 0.4), 0))
	if not inAir then lastWallNormal = nil end
	local wantsMove = humanoid.MoveDirection.Magnitude > 0.1
	local fwd = flat(humanoid.MoveDirection) or flat(root.CFrame.LookVector)
	if cooldown > 0 or not fwd then
		jumpQueued = false
		return
	end

	if wantsMove and tryVault(root, humanoid, fwd, speed) then
	elseif jumpQueued and not inAir and tryMantle(root, humanoid, fwd, false) then
	elseif inAir and wantsMove and tryMantle(root, humanoid, fwd, true) then
	elseif inAir and wantsMove and vel.Y > -25 and tryWallRun(root, humanoid, fwd, speed) then
	end
	jumpQueued = false
end)
