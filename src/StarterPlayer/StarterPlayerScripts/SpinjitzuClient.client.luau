-- SpinjitzuClient v11.0  (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Q toggles Spinjitzu, X Shatterspin, E switches element, R does the Dragon (spin -> rise -> 6s of
-- flight -> landing). Flying, you keep going where the camera looks (A/D drift, Space up, Ctrl down,
-- Shift faster); C locks onto a Shatterspinner and the camera keeps them in front of you.
-- Renders the tornado / dragon for every player (and NPCs tagged "SpinjitzuNPC"),
-- drives the character spin, limb poses, and your own dragon flight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local SpinjitzuEffect = require(ReplicatedStorage:WaitForChild("SpinjitzuEffect"))
local Dragon = require(ReplicatedStorage:WaitForChild("SpinjitzuDragon"))
local NinjaAnimator = require(ReplicatedStorage:WaitForChild("NinjaAnimator"))
local toggleRemote = ReplicatedStorage:WaitForChild("SpinjitzuToggle")

local NPC_TAG = "SpinjitzuNPC"
local SPIN_DOWN = 0.32 -- seconds the spin keeps unwinding after Spinjitzu ends
local FLY_PITCH = math.rad(75) -- how far the body tips forward when flying

local localPlayer = Players.LocalPlayer
local byCharacter = {}  -- [character] = active Spinjitzu effect
local running = {}      -- [effect] = true (includes effects playing their ending)
local spinState = {}    -- [character] = { angle, humanoid }
local dragons = {}      -- [character] = active dragon
local dragonRunning = {} -- [dragon] = true (includes dragons fading out)
local npcFlights = {}   -- [npc] = local flight path state
local npcHome = {}      -- [npc] = where the bot stands (before any local spin)

local function smoothstep(e0, e1, x)
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function killEffect(character, instant)
	local fx = byCharacter[character]
	if not fx then return end
	byCharacter[character] = nil
	if instant then
		fx:Destroy()
		running[fx] = nil
	else
		fx:Stop()
	end
end

local function isAlive(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function refresh(character)
	local wanted = character:GetAttribute("SpinjitzuActive") == true and isAlive(character)
	local fx = byCharacter[character]
	if wanted and not fx then
		-- finish any older effect on this character (e.g. still playing its ending)
		for other in pairs(running) do
			if other.character == character then
				other:Destroy()
				running[other] = nil
			end
		end
		fx = SpinjitzuEffect.new(character,
			character:GetAttribute("SpinjitzuColor") or Config.Color,
			character:GetAttribute("SpinjitzuHighlight") or Config.HighlightColor,
			character:GetAttribute("SpinjitzuElement"))
		if fx then
			byCharacter[character] = fx
			running[fx] = true
		end
	elseif not wanted and fx then
		-- going into the dragon: no landing pose, no spin-down
		if character:GetAttribute("DragonPhase") or character:GetAttribute("CreationPhase") then fx.noEndPose = true end
		killEffect(character, false)
	end
end

----------------------------------------------------------------------------------------
-- your own dragon flight (physics on your character, replicates to everyone)
----------------------------------------------------------------------------------------

local flight = nil
local playLanding -- (below)
local lockBlend = 0 -- 0..1: how much the lock-on camera / steering has taken over

-- the root of the Shatterspinner you're locked onto (nil = none)
local function lockTarget(character)
	local v = character and character:FindFirstChild("DragonLock")
	local target = v and v:IsA("ObjectValue") and v.Value
	return target and target.Parent and target:FindFirstChild("HumanoidRootPart") or nil
end

local function notify(text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Rising Dragon", Text = text, Duration = 2 })
	end)
end

-- the lock key: lock onto the Shatterspinner nearest the middle of your screen (in range), or
-- let go if you're locked on already. The server checks it (Shatterspin.lockOn)
local function toggleLock()
	local character = localPlayer.Character
	local phase = character and character:GetAttribute("DragonPhase")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if (phase ~= "rise" and phase ~= "fly") or not root then return end
	if lockTarget(character) then
		toggleRemote:FireServer("lock", nil)
		return
	end
	local cam = workspace.CurrentCamera.CFrame
	local best, bestScore
	local function consider(model)
		local r = model ~= character and model:GetAttribute("Shatterspin") and model:FindFirstChild("HumanoidRootPart")
		if not r then return end
		local dist = (r.Position - root.Position).Magnitude
		if dist > (Config.DragonLockRange or 250) then return end
		local off = math.acos(math.clamp((r.Position - cam.Position).Unit:Dot(cam.LookVector), -1, 1))
		local score = off + dist / 300
		if not bestScore or score < bestScore then best, bestScore = model, score end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then consider(p.Character) end
	end
	for _, npc in ipairs(CollectionService:GetTagged(NPC_TAG)) do consider(npc) end
	if best then
		toggleRemote:FireServer("lock", best)
	else
		notify("No Shatterspinner in range")
	end
end

local function groundBelow(character, pos, dist)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { character }
	local fxf = workspace:FindFirstChild("SpinjitzuFX")
	if fxf then table.insert(ignore, fxf) end
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(pos, Vector3.new(0, -dist, 0), params)
end

local function flightStop()
	if not flight then return end
	for _, inst in ipairs({ flight.lv, flight.ao, flight.att }) do
		if inst then inst:Destroy() end
	end
	local cam = workspace.CurrentCamera
	if cam and flight.fov then cam.FieldOfView = flight.fov end
	if flight.humanoid.Parent then
		flight.humanoid.PlatformStand = false
		flight.humanoid.AutoRotate = true
	end
	flight = nil
end

local function flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then return fallback end
	return f.Unit
end

-- the default control scripts give WASD / thumbstick as a camera-relative move vector
local function getControls()
	if flight and flight.controls ~= nil then return flight.controls end
	local controls = false
	local ps = localPlayer:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if pm then
		local ok, mod = pcall(require, pm)
		if ok and mod and mod.GetControls then controls = mod:GetControls() or false end
	end
	if flight then flight.controls = controls end
	return controls
end

local function readMove()
	local mv = Vector3.zero
	local controls = getControls()
	if controls then
		local ok, v = pcall(function() return controls:GetMoveVector() end)
		if ok and typeof(v) == "Vector3" then mv = v end
	end
	if mv.Magnitude < 1e-3 then -- fallback: raw keys
		local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
		local z = (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
		mv = Vector3.new(x, 0, z)
	end
	local up = UserInputService:IsKeyDown(Config.DragonUpKey or Enum.KeyCode.Space)
	if not up and controls then
		local ok, j = pcall(function() return controls.activeController and controls.activeController:GetIsJumping() end)
		up = ok and j == true
	end
	local down = UserInputService:IsKeyDown(Config.DragonDownKey or Enum.KeyCode.LeftControl)
	return mv, (up and 1 or 0) - (down and 1 or 0)
end

local function flightStart(character)
	if flight then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	local att = Instance.new("Attachment")
	att.Name = "DragonFlightAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 14
	ao.Parent = root
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	local heading = flatUnit(workspace.CurrentCamera.CFrame.LookVector, Vector3.new(0, 0, -1))
	flight = {
		character = character, root = root, humanoid = humanoid, att = att, lv = lv, ao = ao,
		heading = heading, vel = Vector3.zero, riseT = 0, flyT = 0, startY = root.Position.Y,
		fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView, boost = 0,
	}
	ao.CFrame = CFrame.lookAt(Vector3.zero, heading)
end

-- superhero landings (yours + everyone else's), see Dragon.Land
local landings = {} -- [character] = landing
local landedAt = {} -- [character] = os.clock() of the last one played (yours plays before the server says)
playLanding = function(character)
	if landedAt[character] and os.clock() - landedAt[character] < 1.5 then return end
	landedAt[character] = os.clock()
	if landings[character] then landings[character]:Destroy() end
	landings[character] = Dragon.Land(character)
end

local function flightUpdate(dt)
	if not flight then return end
	local character = flight.character
	if not character.Parent or not flight.root.Parent then
		flightStop()
		return
	end
	local phase = character:GetAttribute("DragonPhase")
	local pos = flight.root.Position
	if phase == "rise" then
		-- straight up, fast at first then easing off
		local T = Config.DragonRiseTime or 3
		local H = Config.DragonRiseHeight or 35
		flight.riseT += dt
		local f = math.clamp(flight.riseT / T, 0, 1)
		local targetY = flight.startY + H * (1 - (1 - f) ^ 2)
		local feed = f < 1 and H * 2 * (1 - f) / T or 0
		flight.vel = Vector3.new(0, feed + (targetY - pos.Y) * 6, 0)
		flight.lv.VectorVelocity = flight.vel
		flight.ao.CFrame = CFrame.lookAt(Vector3.zero, flight.heading)
	elseif phase == "fly" then
		flight.flyT += dt
		local speed = Config.DragonFlySpeed or 50
		-- Shift: boost (the camera widens a little so it feels fast)
		local boosting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		flight.boost += ((boosting and 1 or 0) - flight.boost) * (1 - math.exp(-dt * 5))
		local fast = speed * (1 + ((Config.DragonBoost or 1.9) - 1) * flight.boost)
		local camCF = workspace.CurrentCamera.CFrame
		local camLook = camCF.LookVector
		-- locked onto a Shatterspinner: you fly straight at them
		local lockRoot = lockTarget(character)
		if lockRoot then
			local to = lockRoot.Position - pos
			if to.Magnitude > 0.5 then camLook = camLook:Lerp(to.Unit, lockBlend).Unit end
		end
		local fwdFlat = flatUnit(camLook, flight.heading)
		local rightFlat = fwdFlat:Cross(Vector3.yAxis)
		-- forward follows where the camera looks (pitch limited), sideways stays flat
		local maxPitch = lockRoot and 1.45 or 1.1
		local pitch = math.clamp(math.asin(math.clamp(camLook.Y, -1, 1)), -maxPitch, maxPitch)
		local fwd3 = fwdFlat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		-- always going forward (where you look); A/D drift sideways, Space / Ctrl up and down
		local mv, vert = readMove()
		local dir = (fwd3 + rightFlat * mv.X * 0.5 + Vector3.yAxis * vert * 0.5).Unit
		flight.vel = flight.vel:Lerp(dir * fast, 1 - math.exp(-dt * 3))
		local cam = workspace.CurrentCamera
		if cam and flight.fov then
			local moving = math.clamp((flight.vel.Magnitude - speed) / (fast - speed + 1), 0, 1)
			cam.FieldOfView = flight.fov + 14 * flight.boost * moving
		end
		local vel = flight.vel
		-- gentle bob while hovering in place
		vel += Vector3.new(0, math.sin(flight.flyT * 2) * 0.8 * (1 - math.clamp(vel.Magnitude / 8, 0, 1)), 0)
		-- don't scrape the ground
		local hit = groundBelow(character, pos, 5)
		if hit then vel = Vector3.new(vel.X, math.max(vel.Y, (5 - (pos.Y - hit.Position.Y)) * 6), vel.Z) end
		flight.lv.VectorVelocity = vel

		-- face where you're going; tip forward with horizontal speed, nose up/down with climb
		local horiz = Vector3.new(vel.X, 0, vel.Z)
		local hs = horiz.Magnitude
		if hs > 2 then flight.heading = flight.heading:Lerp(horiz.Unit, math.min(1, dt * 6)).Unit end
		local tip = FLY_PITCH * math.clamp(hs / (speed * 0.6), 0, 1)
		local climb = math.atan2(vel.Y, math.max(hs, 1)) * math.clamp(hs / 10, 0, 1) * 0.6
		flight.ao.CFrame = CFrame.lookAt(Vector3.zero, flight.heading) * CFrame.Angles(climb - tip, 0, 0)
	elseif phase == "land" then
		-- dive STRAIGHT down head first, flip feet-first just before the floor, slam into it
		flight.landT = (flight.landT or 0) + dt
		local feet = flight.humanoid.RigType == Enum.HumanoidRigType.R6 and flight.root.Size.Y * 0.5 + 2
			or flight.humanoid.HipHeight + flight.root.Size.Y * 0.5
		local fall = math.min(170, 40 + flight.landT * 260)
		flight.vel = Vector3.new(0, -fall, 0)
		flight.lv.VectorVelocity = flight.vel
		local below = groundBelow(character, pos, 400)
		local height = below and pos.Y - below.Position.Y or math.huge
		local flip = height < math.max(14, fall * 0.28)
		flight.ao.Responsiveness = flip and 45 or 20
		flight.ao.CFrame = CFrame.lookAt(Vector3.zero, flight.heading) * CFrame.Angles(flip and 0 or -math.rad(165), 0, 0)
		local hit = groundBelow(character, pos, feet + fall * dt * 2 + 0.5)
		if hit or flight.landT > 3 then
			local root, humanoid = flight.root, flight.humanoid
			if hit then root.CFrame = CFrame.lookAt(hit.Position + Vector3.new(0, feet, 0), hit.Position + Vector3.new(0, feet, 0) + flight.heading) end
			flightStop()
			root.AssemblyLinearVelocity = Vector3.zero
			toggleRemote:FireServer("landed")
			if hit then
				playLanding(character)
				-- stuck in the pose for a moment
				local speed, jump = humanoid.WalkSpeed, humanoid.JumpPower
				humanoid.WalkSpeed, humanoid.JumpPower = 0, 0
				task.delay(0.9, function()
					if humanoid.Parent and humanoid.WalkSpeed == 0 then humanoid.WalkSpeed, humanoid.JumpPower = speed, jump end
				end)
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- NPC dragon flight (bots are anchored; every client animates the same path locally)
----------------------------------------------------------------------------------------

local function npcFlightUpdate(npc, dt)
	local st = npcFlights[npc]
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not st or not root then return end
	local phase = npc:GetAttribute("DragonPhase")
	local home = st.start
	local H = Config.DragonRiseHeight or 35
	local up = Vector3.yAxis
	if phase == "rise" then
		st.t += dt
		local f = math.clamp(st.t / (Config.DragonRiseTime or 3), 0, 1)
		root.CFrame = home + up * H * (1 - (1 - f) ^ 2)
	elseif phase == "fly" then
		-- big oval up high
		st.ft += dt
		local RS, RF = 30, 22
		local speed = (Config.DragonFlySpeed or 50) * 0.7 * smoothstep(0, 0.8, st.ft)
		st.ang += speed / ((RS + RF) / 2) * dt
		local right, look = home.RightVector, home.LookVector
		local center = home.Position + right * RS + up * H
		local p = center - right * math.cos(st.ang) * RS + look * math.sin(st.ang) * RF
		p += up * (math.sin(st.ft * 0.9) * 3 * smoothstep(0, 1.5, st.ft))
		local tangent = (right * math.sin(st.ang) * RS + look * math.cos(st.ang) * RF).Unit
		root.CFrame = CFrame.lookAt(p, p + tangent) * CFrame.Angles(-FLY_PITCH * smoothstep(0, 0.6, st.ft), 0, 0)
	elseif phase == "land" then
		if not st.landFrom then st.landFrom, st.lt = root.CFrame, 0 end
		st.lt += dt
		local f = smoothstep(0, 2.3, st.lt)
		local rot = st.landFrom.Rotation:Lerp(home.Rotation, smoothstep(0, 1, st.lt))
		root.CFrame = CFrame.new(st.landFrom.Position:Lerp(home.Position, f)) * rot
	end
end

----------------------------------------------------------------------------------------
-- dragon visuals for everyone
----------------------------------------------------------------------------------------

local creatingDragon = {} -- [character] = true while its dragon is being built

local function killDragon(character, instant)
	local d = dragons[character]
	dragons[character] = nil
	if d then
		if instant then
			d:Destroy()
			dragonRunning[d] = nil
		else
			d:Stop()
		end
	end
	if character == localPlayer.Character then flightStop() end
	local st = npcFlights[character]
	if st then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then root.CFrame = npcHome[character] or st.start end
		npcFlights[character] = nil
	end
end

local function dragonRefresh(character)
	local phase = character:GetAttribute("DragonPhase")
	local out = (phase == "rise" or phase == "fly" or phase == "land") and isAlive(character)
	if out then
		local d = dragons[character]
		if not d then
			-- (the first dragon can wait a moment for its meshes: don't start a second one meanwhile)
			if creatingDragon[character] then return end
			creatingDragon[character] = true
			d = Dragon.new(character,
				character:GetAttribute("SpinjitzuColor") or Config.Color,
				character:GetAttribute("SpinjitzuHighlight") or Config.HighlightColor,
				character:GetAttribute("SpinjitzuElement"))
			creatingDragon[character] = nil
			if not d then return end
			phase = character:GetAttribute("DragonPhase")
			if not ((phase == "rise" or phase == "fly" or phase == "land") and isAlive(character)) then
				d:Destroy() -- it ended while it was being built
				return
			end
			dragons[character] = d
			dragonRunning[d] = true
		end
		d:SetPhase(phase)
		if character == localPlayer.Character then
			flightStart(character)
		elseif CollectionService:HasTag(character, NPC_TAG) and not npcFlights[character] then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local home = npcHome[character] or root.CFrame
				root.CFrame = home
				npcFlights[character] = { start = home, t = 0, ft = 0, ang = 0 }
			end
		end
	elseif phase == nil then
		killDragon(character, false)
	end
end

----------------------------------------------------------------------------------------
-- watching characters
----------------------------------------------------------------------------------------

local function watchCharacter(character)
	local conns = {}
	local function cleanup()
		killEffect(character, true)
		killDragon(character, true)
		npcHome[character] = nil
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end
	table.insert(conns, character:GetAttributeChangedSignal("SpinjitzuActive"):Connect(function()
		refresh(character)
	end))
	table.insert(conns, character:GetAttributeChangedSignal("DragonPhase"):Connect(function()
		dragonRefresh(character)
	end))
	table.insert(conns, character:GetAttributeChangedSignal("DragonLanded"):Connect(function()
		playLanding(character)
	end))
	table.insert(conns, character:GetAttributeChangedSignal("SpinjitzuColor"):Connect(function()
		if byCharacter[character] and not character:GetAttribute("DragonPhase") then
			killEffect(character, true)
			refresh(character)
		end
	end))
	table.insert(conns, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then cleanup() end
	end))
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if not humanoid then return end
		if hrp and CollectionService:HasTag(character, NPC_TAG) and not character:GetAttribute("SpinjitzuActive") and not character:GetAttribute("DragonPhase") then
			npcHome[character] = hrp.CFrame
		end
		table.insert(conns, humanoid.Died:Connect(function()
			killEffect(character, true)
			killDragon(character, true)
		end))
		refresh(character)
		dragonRefresh(character)
	end)
end

local function watchPlayer(player)
	if player.Character then watchCharacter(player.Character) end
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(function(character)
		killEffect(character, true)
		killDragon(character, true)
	end)
end

for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
-- our own procedural animations replace the default ones
if localPlayer.Character then NinjaAnimator.TakeOver(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(NinjaAnimator.TakeOver)
Players.PlayerAdded:Connect(watchPlayer)

for _, npc in ipairs(CollectionService:GetTagged(NPC_TAG)) do watchCharacter(npc) end
CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(watchCharacter)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Config.Keybind then
		toggleRemote:FireServer()
	elseif Config.CycleKey and input.KeyCode == Config.CycleKey then
		toggleRemote:FireServer("cycle")
	elseif Config.DragonKey and input.KeyCode == Config.DragonKey then
		toggleRemote:FireServer("dragon")
	elseif Config.CreationKey and input.KeyCode == Config.CreationKey then
		toggleRemote:FireServer("creation")
	elseif Config.ShatterKey and input.KeyCode == Config.ShatterKey then
		toggleRemote:FireServer("shatter")
	elseif Config.DragonLockKey and input.KeyCode == Config.DragonLockKey then
		toggleLock()
	end
end)

-- messages from the server (e.g. why the Tornado of Creation can't start)
toggleRemote.OnClientEvent:Connect(function(kind, text)
	if kind == "launch" then -- thrown out of the Tornado of Creation
		local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root and typeof(text) == "Vector3" then root.AssemblyLinearVelocity = text end
		return
	end
	if kind ~= "notify" then return end
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Spinjitzu", Text = text, Duration = 3 })
	end)
end)

-- ninja inside the Tornado of Creation are hidden for everyone
local creationHidden = {}
local function setHidden(ch, v)
	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = v end
	end
end
local function creationHideUpdate()
	for ch in pairs(creationHidden) do
		if ch:GetAttribute("CreationPhase") ~= "inside" or not ch.Parent then
			creationHidden[ch] = nil
			if ch.Parent then setHidden(ch, 0) end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch and ch:GetAttribute("CreationPhase") == "inside" then creationHidden[ch] = true end
	end
	for _, npc in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		if npc:GetAttribute("CreationPhase") == "inside" then creationHidden[npc] = true end
	end
	for ch in pairs(creationHidden) do setHidden(ch, 1) end
end

-- little popup when you switch element
localPlayer:GetAttributeChangedSignal("SpinjitzuElement"):Connect(function()
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "Spinjitzu",
			Text = "Element: " .. tostring(localPlayer:GetAttribute("SpinjitzuElement")),
			Duration = 2,
		})
	end)
end)

-- this client spins its own character, plus NPCs (nobody else owns them)
local function drivesSpin(character)
	return character == localPlayer.Character or CollectionService:HasTag(character, NPC_TAG)
end

-- windup: spin starts slower and speeds up; ending: spin unwinds to a stop
local function spinMultiplier(fx)
	if not fx.stopping then
		local w = Config.WindupTime or 0
		local ramp = w > 0 and math.clamp(fx.time / w, 0, 1) or 1
		return 0.3 + 0.7 * ramp * ramp
	end
	if fx.noEndPose then return 0 end
	local ts = fx.time - (fx.stopAt or fx.time)
	if ts < SPIN_DOWN then
		return (1 - ts / SPIN_DOWN) ^ 2
	end
	return 0
end

----------------------------------------------------------------------------------------
-- particle budget: Roblox stops drawing particles past a limit, which made far-away
-- tornadoes show only bits. Far / crowded effects emit fewer particles so all stay whole.
----------------------------------------------------------------------------------------

local PARTICLE_BUDGET = Config.ParticleBudget or 9000
local lodBase = setmetatable({}, { __mode = "k" }) -- [emitter] = its designed Rate
local lodTimer = 0

local function lodUpdate(dt)
	lodTimer -= dt
	if lodTimer > 0 then return end
	lodTimer = 0.25
	local camPos = workspace.CurrentCamera.CFrame.Position
	local groups, total, fixed = {}, 0, 0
	local function add(list, root, mine, prio)
		if not list or not root then return end
		local dist = (root.Position - camPos).Magnitude
		local f = (mine or prio) and 1 or math.clamp(1 - (dist - 40) / 160, 0.3, 1) -- full up close, 30% at 200+ studs
		local cost = 0
		for _, pe in ipairs(list) do
			if pe.Parent and pe.Enabled then
				local base = pe:GetAttribute("LodBase") or lodBase[pe]
				if not base then
					base = pe.Rate
					lodBase[pe] = base
				end
				cost += base * (pe.Lifetime.Min + pe.Lifetime.Max) / 2
			end
		end
		if prio then fixed += cost else total += cost * f end
		table.insert(groups, { list = list, f = f, mine = mine, prio = prio })
	end
	local myChar = localPlayer.Character
	for fx in pairs(running) do
		-- (the Tornado of Creation and Shatterspin's swarm always get full detail)
		add(fx.emitters, fx.root, fx.character == myChar, fx.character.Name == "TornadoOfCreation" or fx.preset == Config.Presets.Shatter)
	end
	for d in pairs(dragonRunning) do add(d.emitters, d.root, d.character == myChar) end
	-- the Tornado of Creation always gets full detail; everything else shares what's left
	local scale = math.min(1, math.max(PARTICLE_BUDGET - fixed, PARTICLE_BUDGET * 0.25) / math.max(total, 1))
	for _, g in ipairs(groups) do
		local m = g.prio and 1 or g.f * (g.mine and math.max(scale, 0.6) or scale)
		for _, pe in ipairs(g.list) do
			if pe.Parent then
				local base = pe:GetAttribute("LodBase") or lodBase[pe]
				if base then
					local want = base * m
					if math.abs(pe.Rate - want) > 0.03 * base + 0.01 then pe.Rate = want end
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local spinning = {}
	for fx in pairs(running) do
		if not fx:Update(dt) then
			running[fx] = nil
			if byCharacter[fx.character] == fx then
				byCharacter[fx.character] = nil
			end
		elseif drivesSpin(fx.character) then
			local m = spinMultiplier(fx)
			if m > 0 then
				spinning[fx.character] = math.max(spinning[fx.character] or 0, m)
			end
		end
	end

	for character, m in pairs(spinning) do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if humanoid and root then
			local st = spinState[character]
			if not st then
				local look = root.CFrame.LookVector
				st = { angle = math.atan2(-look.X, -look.Z), humanoid = humanoid }
				spinState[character] = st
				humanoid.AutoRotate = false
			end
			st.angle += Config.CharacterSpinSpeed * m * Config.SpinDirection * dt
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, st.angle, 0)
		end
	end

	for character, st in pairs(spinState) do
		if not spinning[character] then
			if st.humanoid.Parent and not (flight and flight.character == character) then
				st.humanoid.AutoRotate = true
			end
			spinState[character] = nil
		end
	end

	-- dragons: move NPCs along their path first, then update visuals to follow
	for npc in pairs(npcFlights) do npcFlightUpdate(npc, dt) end
	flightUpdate(dt)
	lodUpdate(dt)
	creationHideUpdate()
	for d in pairs(dragonRunning) do
		if not d:Update(dt) then
			dragonRunning[d] = nil
			if dragons[d.character] == d then dragons[d.character] = nil end
		end
	end
end)

-- limb poses: Stepped runs after the Animator, so these override walk/idle
RunService.Stepped:Connect(function(_, dt)
	NinjaAnimator.Step(dt) -- walk / run / jump / parkour poses first, Spinjitzu poses on top
	for fx in pairs(running) do
		fx:ApplyPose()
	end
	for d in pairs(dragonRunning) do
		d:ApplyPose()
	end
	for character, l in pairs(landings) do
		if l:Update(dt) then
			l:ApplyPose()
		else
			landings[character] = nil
		end
	end
end)

----------------------------------------------------------------------------------------
-- dragon HUD: a bar showing how long you've got left in the air, and lock-on. Locked on: a
-- reticle slams onto them, red rings spin round them, a tether runs from you to them, the screen
-- edges flash red + "LOCKED ON"; the camera swings round to keep them in front of you so you fly
-- straight at them
----------------------------------------------------------------------------------------

local RED = Color3.fromRGB(255, 45, 55)
local hud = Instance.new("ScreenGui")
hud.Name = "DragonHUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.Enabled = false
hud.Parent = localPlayer:WaitForChild("PlayerGui")
local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 1)
barBack.Position = UDim2.new(0.5, 0, 1, -110)
barBack.Size = UDim2.fromOffset(280, 10)
barBack.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
barBack.BackgroundTransparency = 0.3
barBack.BorderSizePixel = 0
barBack.Parent = hud
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
local barText = Instance.new("TextLabel")
barText.BackgroundTransparency = 1
barText.AnchorPoint = Vector2.new(0.5, 1)
barText.Position = UDim2.new(0.5, 0, 0, -4)
barText.Size = UDim2.fromOffset(280, 18)
barText.Font = Enum.Font.GothamBold
barText.TextSize = 14
barText.TextColor3 = Color3.new(1, 1, 1)
barText.TextStrokeTransparency = 0.5
barText.Parent = barBack
local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 1, 6)
hint.Size = UDim2.fromOffset(320, 16)
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextColor3 = Color3.fromRGB(230, 230, 235)
hint.TextStrokeTransparency = 0.6
hint.Parent = barBack

-- the reticle: four corner brackets + a diamond in the middle, over the target
local reticle = Instance.new("BillboardGui")
reticle.Name = "DragonLockReticle"
reticle.AlwaysOnTop = true
reticle.Size = UDim2.fromOffset(120, 120)
reticle.Enabled = false
reticle.Parent = hud
local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundTransparency = 1
frame.Parent = reticle
for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
	for _, horiz in ipairs({ true, false }) do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(c[1], c[2])
		f.Position = UDim2.fromScale(c[1], c[2])
		f.Size = horiz and UDim2.new(0.32, 0, 0, 4) or UDim2.new(0, 4, 0.32, 0)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = RED
		f.Parent = frame
	end
end
local diamond = Instance.new("Frame")
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.fromScale(0.5, 0.5)
diamond.Size = UDim2.fromOffset(16, 16)
diamond.Rotation = 45
diamond.BackgroundTransparency = 1
diamond.Parent = frame
local stroke = Instance.new("UIStroke")
stroke.Color = RED
stroke.Thickness = 2.5
stroke.Parent = diamond
local lockText = Instance.new("TextLabel")
lockText.BackgroundTransparency = 1
lockText.AnchorPoint = Vector2.new(0.5, 0)
lockText.Position = UDim2.new(0.5, 0, 1, 6)
lockText.Size = UDim2.fromOffset(160, 18)
lockText.Font = Enum.Font.GothamBlack
lockText.TextSize = 14
lockText.TextColor3 = RED
lockText.TextStrokeTransparency = 0.4
lockText.Text = "LOCKED - RAM THEM"
lockText.Parent = reticle

-- the moment you lock on: red flash round the edges of the screen + a big "LOCKED ON"
local edge = Instance.new("Frame")
edge.Size = UDim2.fromScale(1, 1)
edge.BackgroundTransparency = 1
edge.Parent = hud
local edgeStroke = Instance.new("UIStroke")
edgeStroke.Color = RED
edgeStroke.Thickness = 36
edgeStroke.Transparency = 1
edgeStroke.Parent = edge
local banner = Instance.new("TextLabel")
banner.BackgroundTransparency = 1
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.28)
banner.Size = UDim2.fromOffset(500, 60)
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 46
banner.TextColor3 = RED
banner.TextStrokeColor3 = Color3.new(0, 0, 0)
banner.TextStrokeTransparency = 0.2
banner.Text = "LOCKED ON"
banner.TextTransparency = 1
banner.Parent = hud
local lockSound = Instance.new("Sound")
lockSound.SoundId = "rbxassetid://9114277757"
lockSound.Volume = 0.8
lockSound.PlaybackSpeed = 1.5
lockSound.Parent = hud

-- in the world (only you see them): spinning red rings round them + a tether from you to them
local lockFx = nil -- { target, adorns, rings, a0, a1, beam }
local function dropLockFx()
	if not lockFx then return end
	for _, inst in ipairs(lockFx.parts) do inst:Destroy() end
	lockFx = nil
end
local function makeLockFx(myRoot, targetRoot)
	dropLockFx()
	local parts = {}
	local rings = {}
	for i, r in ipairs({ { 5.5, 0.35, 300 }, { 7, 0.25, 80 }, { 7, 0.25, 80 }, { 7, 0.25, 80 }, { 4, 0.3, 360 } }) do
		local ad = Instance.new("CylinderHandleAdornment")
		ad.Adornee = targetRoot
		ad.Radius, ad.InnerRadius, ad.Height, ad.Angle = r[1], r[1] - r[2], 0.12, r[3]
		ad.Color3 = i == 5 and Color3.new(1, 1, 1) or RED
		ad.Transparency = i == 5 and 0.4 or 0.1
		ad.AlwaysOnTop = true
		ad.ZIndex = 1
		ad.Parent = targetRoot
		table.insert(parts, ad)
		rings[i] = { ad = ad, phase = (i - 2) * math.pi * 2 / 3, spin = i == 1 and 2.5 or -4 }
	end
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = myRoot, targetRoot
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.3, 0.6
	beam.Color = ColorSequence.new(Color3.new(1, 0.6, 0.6), RED)
	beam.LightEmission, beam.LightInfluence, beam.Brightness = 1, 0, 3
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 4
	beam.TextureSpeed = 4
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	beam.Parent = a0
	table.insert(parts, a0)
	table.insert(parts, a1)
	lockFx = { target = targetRoot, parts = parts, rings = rings, t = 0 }
	-- slam!
	lockSound:Play()
	edgeStroke.Transparency = 0.15
	TweenService:Create(edgeStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	banner.TextTransparency, banner.TextStrokeTransparency = 0, 0.2
	banner.Size = UDim2.fromOffset(900, 110)
	TweenService:Create(banner, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(500, 60) }):Play()
	task.delay(1.1, function()
		TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

RunService:BindToRenderStep("DragonHUD", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local character = localPlayer.Character
	local phase = character and character:GetAttribute("DragonPhase")
	local onDragon = phase == "rise" or phase == "fly" or phase == "land"
	hud.Enabled = onDragon
	if not onDragon then
		lockBlend = 0
		reticle.Adornee, reticle.Enabled = nil, false
		dropLockFx()
		return
	end
	-- time left
	local ends = character:GetAttribute("DragonEnds")
	local col = character:GetAttribute("SpinjitzuColor") or Config.Color
	if phase == "fly" and typeof(ends) == "number" then
		local left = math.max(0, ends - workspace:GetServerTimeNow())
		barFill.Size = UDim2.fromScale(math.clamp(left / (Config.DragonFlyTime or 9), 0, 1), 1)
		barFill.BackgroundColor3 = left < 1.5 and RED or col
		barText.Text = ("%.1f"):format(left)
	elseif phase == "rise" then
		barFill.Size = UDim2.fromScale(1, 1)
		barFill.BackgroundColor3 = col
		barText.Text = "RISING"
	else
		barFill.Size = UDim2.fromScale(0, 1)
		barText.Text = "DIVE!"
	end
	-- lock-on
	local locked = phase ~= "land" and lockTarget(character) or nil
	local key = Config.DragonLockKey and Config.DragonLockKey.Name or "C"
	hint.Text = locked and ("fly into them!  (%s = let go)"):format(key) or ("%s = lock onto a Shatterspinner"):format(key)
	local root = character:FindFirstChild("HumanoidRootPart")
	if locked and root then
		if not lockFx or lockFx.target ~= locked then makeLockFx(root, locked) end
		lockFx.t += dt
		local t = lockFx.t
		-- the reticle slams in from big + spun round, then pulses
		local slam = math.clamp(t / 0.25, 0, 1)
		local pulse = 1 + math.sin(os.clock() * 12) * 0.06
		local size = (0.6 + (1 - slam) ^ 2 * 1.6) * pulse
		frame.Size = UDim2.fromScale(size, size)
		frame.Rotation = (1 - slam) * 180
		diamond.Rotation = 45 + os.clock() * 120
		reticle.Adornee, reticle.Enabled = locked, true
		for i, r in ipairs(lockFx.rings) do
			local tilt = i == 5 and CFrame.Angles(0, 0, 0) or CFrame.Angles(0, 0, math.sin(os.clock() * 1.3 + i) * 0.25)
			r.ad.CFrame = tilt * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, r.phase + os.clock() * r.spin)
			if i == 5 then
				local k = (t * 1.6) % 1 -- a white ring shrinking in on them, over and over
				r.ad.Radius, r.ad.InnerRadius = 9 - k * 7, 8.7 - k * 7
				r.ad.Transparency = 0.2 + k * 0.8
			end
		end
	else
		reticle.Adornee, reticle.Enabled = nil, false
		dropLockFx()
	end
	-- the camera swings round behind you to face them
	local want = locked and 1 or 0
	lockBlend += (want - lockBlend) * (1 - math.exp(-dt * 6))
	local cam = workspace.CurrentCamera
	if lockBlend > 0.01 and locked and root and cam then
		local zoom = math.clamp((cam.CFrame.Position - cam.Focus.Position).Magnitude, 8, 35)
		local to = locked.Position - root.Position
		if to.Magnitude > 1 then
			local dir = to.Unit
			local camPos = root.Position - dir * zoom + Vector3.new(0, zoom * 0.3, 0)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(camPos, locked.Position), lockBlend)
		end
	end
end)
