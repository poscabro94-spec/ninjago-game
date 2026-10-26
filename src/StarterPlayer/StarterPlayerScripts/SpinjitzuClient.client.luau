-- SpinjitzuClient v11.0  (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Q toggles Spinjitzu, X Shatterspin, E switches element, R does the Dragon (spin -> rise -> 6s of
-- flight -> landing). Flying, you keep going where the camera looks (A/D drift, Space up, Ctrl down,
-- Shift faster); lock onto a Shatterspinner and the camera keeps them in front of you.
-- Renders the tornado / dragon for every player (and NPCs tagged "SpinjitzuNPC"),
-- drives the character spin, limb poses, and your own dragon flight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
		local pitch = math.clamp(math.asin(math.clamp(camLook.Y, -1, 1)), -1.1, 1.1)
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
		-- plunge to the floor (keeping a little of your speed), upright, then slam into it
		flight.landT = (flight.landT or 0) + dt
		local feet = flight.humanoid.RigType == Enum.HumanoidRigType.R6 and flight.root.Size.Y * 0.5 + 2
			or flight.humanoid.HipHeight + flight.root.Size.Y * 0.5
		local fall = math.min(150, 50 + flight.landT * 220)
		local horiz = Vector3.new(flight.vel.X, 0, flight.vel.Z) * math.exp(-dt * 2.5)
		flight.vel = horiz + Vector3.new(0, -fall, 0)
		flight.lv.VectorVelocity = flight.vel
		flight.ao.CFrame = CFrame.lookAt(Vector3.zero, flight.heading)
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
-- dragon HUD: a bar showing how long you've got left in the air; lock-on (a reticle closing in
-- on whoever you're locking onto, then locked; the camera swings round to keep them in front of
-- you so you fly straight at them)
----------------------------------------------------------------------------------------

local RED = Color3.fromRGB(255, 45, 55)
local hud = Instance.new("ScreenGui")
hud.Name = "DragonHUD"
hud.ResetOnSpawn = false
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

-- the reticle: four corner brackets + a diamond in the middle, over the target
local reticle = Instance.new("BillboardGui")
reticle.Name = "DragonLockReticle"
reticle.AlwaysOnTop = true
reticle.Size = UDim2.fromOffset(110, 110)
reticle.Enabled = false
reticle.Parent = hud
local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundTransparency = 1
frame.Parent = reticle
local corners = {}
for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
	for _, horiz in ipairs({ true, false }) do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(c[1], c[2])
		f.Position = UDim2.fromScale(c[1], c[2])
		f.Size = horiz and UDim2.new(0.3, 0, 0, 4) or UDim2.new(0, 4, 0.3, 0)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = RED
		f.Parent = frame
		table.insert(corners, f)
	end
end
local diamond = Instance.new("Frame")
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.fromScale(0.5, 0.5)
diamond.Size = UDim2.fromOffset(14, 14)
diamond.Rotation = 45
diamond.BackgroundTransparency = 1
diamond.Parent = frame
local stroke = Instance.new("UIStroke")
stroke.Color = RED
stroke.Thickness = 2
stroke.Parent = diamond
local lockText = Instance.new("TextLabel")
lockText.BackgroundTransparency = 1
lockText.AnchorPoint = Vector2.new(0.5, 0)
lockText.Position = UDim2.new(0.5, 0, 1, 4)
lockText.Size = UDim2.fromOffset(140, 18)
lockText.Font = Enum.Font.GothamBlack
lockText.TextSize = 14
lockText.TextColor3 = RED
lockText.TextStrokeTransparency = 0.4
lockText.Parent = reticle
reticle.ClipsDescendants = false

local function setReticleColour(col)
	for _, f in ipairs(corners) do f.BackgroundColor3 = col end
	stroke.Color, lockText.TextColor3 = col, col
end

local function rootOfValue(character, name)
	local v = character and character:FindFirstChild(name)
	local target = v and v:IsA("ObjectValue") and v.Value
	return target and target.Parent and target:FindFirstChild("HumanoidRootPart") or nil
end

RunService:BindToRenderStep("DragonHUD", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local character = localPlayer.Character
	local phase = character and character:GetAttribute("DragonPhase")
	local onDragon = phase == "rise" or phase == "fly" or phase == "land"
	hud.Enabled = onDragon
	if not onDragon then
		lockBlend = 0
		reticle.Adornee, reticle.Enabled = nil, false
		return
	end
	-- time left
	local ends = character:GetAttribute("DragonEnds")
	local col = character:GetAttribute("SpinjitzuColor") or Config.Color
	if phase == "fly" and typeof(ends) == "number" then
		local left = math.max(0, ends - workspace:GetServerTimeNow())
		barFill.Size = UDim2.fromScale(math.clamp(left / (Config.DragonFlyTime or 6), 0, 1), 1)
		barFill.BackgroundColor3 = left < 1.5 and RED or col
		barText.Text = ("%.1f"):format(left)
	elseif phase == "rise" then
		barFill.Size = UDim2.fromScale(1, 1)
		barFill.BackgroundColor3 = col
		barText.Text = "RISING"
	else
		barFill.Size = UDim2.fromScale(0, 1)
		barText.Text = "LANDING"
	end
	-- lock-on
	local locked = lockTarget(character)
	local locking = not locked and rootOfValue(character, "DragonLocking")
	local target = locked or locking
	reticle.Adornee, reticle.Enabled = target, target ~= nil
	if locked then
		local pulse = 1 + math.sin(os.clock() * 12) * 0.06
		frame.Size = UDim2.fromScale(0.55 * pulse, 0.55 * pulse)
		frame.Rotation = 0
		setReticleColour(RED)
		lockText.Text = "LOCKED - RAM THEM"
	elseif locking then
		local p = character:GetAttribute("LockProgress") or 0
		frame.Size = UDim2.fromScale(1 - 0.45 * p, 1 - 0.45 * p)
		frame.Rotation = (1 - p) * 90
		setReticleColour(Color3.new(1, 1, 1):Lerp(RED, p))
		lockText.Text = ("LOCKING %d%%"):format(math.floor(p * 100))
	end
	-- the camera swings round behind you to face them
	local want = (locked and phase ~= "land") and 1 or 0
	lockBlend += (want - lockBlend) * (1 - math.exp(-dt * 6))
	local root = character:FindFirstChild("HumanoidRootPart")
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
