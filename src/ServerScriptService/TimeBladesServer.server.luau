-- TimeBladesServer v2.0  (Script in ServerScriptService)
-- The Time Blades' powers: keys while wearing one (GoldenWeaponsClient sends "TimeBladePower"
-- with the power's id + where you aim). Pause Time Blade (red):
--   F  Time Stop: a dome of stopped time where you aim. Everyone inside freezes mid-pose, shots
--      hang in the air and beams stop at its edge; after a few seconds time snaps back
--   G  Pause Bolt: a red ring of stopped time that locks the first one it hits
--   V  Stop-Step: time stops around you for a moment and you dash straight through them; they
--      all get hit at once when it starts again
--   Z  Stopped World: everything (but you) stops, far around you
-- Settings (keys, cooldowns, sizes) are on the blade (GoldenWeapons.PauseBlade). Cooldowns are
-- player attributes TimeReady<id> (server time it's ready again) for the client's power bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local TimeZones = require(ReplicatedStorage:WaitForChild("TimeZones"))
local TimeEffects = require(script.Parent:WaitForChild("TimeEffects"))
local HitEffects = require(script.Parent:WaitForChild("HitEffects"))

local remote = ReplicatedStorage:FindFirstChild("TimeBladePower")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TimeBladePower"
	remote.Parent = ReplicatedStorage
end
local zones = TimeZones.folder()

-- flying shots that stopped time can catch
local SHOTS = {
	LightningBall = true, Fireball = true, WaterBall = true, EnergyBall = true, IceShard = true, Rock = true,
	ThrownShuriken = true, PauseBolt = true,
}
local ownShots = setmetatable({}, { __mode = "k" }) -- [part] = the character that made it (its time doesn't stop it)

local function notify(player, text)
	local toggle = ReplicatedStorage:FindFirstChild("SpinjitzuToggle")
	if toggle then toggle:FireClient(player, "notify", text) end
end

local function sound(parent, id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed, s.RollOffMaxDistance = id, volume, pitch, 150
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 5)
end

local function neon(name, size, cf, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.Size = size
	p.CFrame = cf
	p.Parent = workspace
	return p
end

-- your screen goes grey for a while (you're the one moving in stopped time)
local function tint(player, seconds)
	remote:FireClient(player, "tint", seconds)
end

-- stop everyone (but the caster) whose middle is within radius of center, and every shot in
-- there, until `untilT`. held = what's already caught (call again to catch newcomers)
local function catchIn(center, radius, untilT, caster, color, held)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { caster, zones }
	for _, part in ipairs(workspace:GetPartBoundsInRadius(center, radius, overlap)) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not held[model] then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC")
				and (root.Position - center).Magnitude <= radius then
				held[model] = true
				TimeEffects.lock(model, untilT - os.clock(), color)
			end
		end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if SHOTS[child.Name] and child:IsA("BasePart") and not held[child] and ownShots[child] ~= caster
			and (child.Position - center).Magnitude <= radius then
			held[child] = true
			TimeEffects.holdPart(child, untilT - os.clock())
		end
	end
end

-- time snaps back: a little burst on everything that was caught
local function release(held, color)
	for thing in pairs(held) do
		local pos = thing:IsA("Model") and thing.Parent and thing:GetPivot().Position or (thing:IsA("BasePart") and thing.Parent and thing.Position)
		if pos then TimeEffects.burst(pos, color) end
	end
end

local function hit(blade, model, damage, final)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return nil end
	hum:TakeDamage(damage)
	model:SetAttribute("LastHit", os.clock())
	HitEffects.show(blade, root, model, damage, final)
	return root
end

----------------------------------------------------------------------------------------
-- F: Time Stop
----------------------------------------------------------------------------------------

local function timeStop(_, character, root, blade, aim)
	local S = blade.Pause
	local color = blade.EnergyColor
	-- the dome goes where you aim, up to Reach studs in front of you
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	if flat.Magnitude < 0.5 then flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	local center = root.Position + flat.Unit * math.min(flat.Magnitude, S.Reach)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, zones }
	local down = workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
	local ground = down and down.Position or center - Vector3.new(0, 3, 0)

	-- the dome (also the zone that stops beams), a ring on the ground, clock hands turning backwards
	local dome = Instance.new("Part")
	dome.Name = "TimeStop"
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.ForceField
	dome.Color = color
	dome.Anchored, dome.CanCollide, dome.CanQuery, dome.CanTouch, dome.CastShadow = true, false, false, false, false
	dome.Size = Vector3.one * 2
	dome.CFrame = CFrame.new(ground)
	dome:SetAttribute("Radius", S.Radius)
	dome.Parent = zones
	TweenService:Create(dome, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.one * S.Radius * 2 }):Play()
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.15, S.Radius * 2, S.Radius * 2)
	ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	local hub = ground + Vector3.new(0, 0.2, 0)
	local long = neon("MinuteHand", Vector3.new(0.4, 0.15, S.Radius * 0.85), CFrame.new(hub), color, 0.1)
	local short = neon("HourHand", Vector3.new(0.5, 0.15, S.Radius * 0.55), CFrame.new(hub), color, 0.1)
	sound(dome, blade.Sounds.Final, 1, 0.45)
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 3, S.Radius * 1.5
	light.Parent = dome

	-- freeze what's inside, including whatever walks or flies in later
	local stopAt = os.clock() + S.Time
	local held = {}
	local t0 = os.clock()
	while os.clock() < stopAt do
		catchIn(ground, S.Radius, stopAt, character, color, held)
		local a = -(os.clock() - t0) * 1.5
		long.CFrame = CFrame.new(hub) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -S.Radius * 0.42)
		short.CFrame = CFrame.new(hub) * CFrame.Angles(0, a / 6, 0) * CFrame.new(0, 0, -S.Radius * 0.27)
		task.wait(0.05)
	end

	-- time snaps back
	dome:SetAttribute("Radius", nil)
	sound(dome, blade.Sounds.Final, 0.8, 1.4)
	release(held, color)
	TweenService:Create(dome, TweenInfo.new(0.25), { Size = Vector3.one * 0.5, Transparency = 1 }):Play()
	for _, p in ipairs({ ring, long, short }) do
		TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(p, 0.3)
	end
	Debris:AddItem(dome, 0.3)
end

----------------------------------------------------------------------------------------
-- G: Pause Bolt
----------------------------------------------------------------------------------------

local function pauseBolt(_, character, root, blade, aim)
	local S = blade.Bolt
	local color = blade.EnergyColor
	local origin = root.CFrame:PointToWorldSpace(Vector3.new(0.6, 0.8, -2.2))
	local dir = aim - origin
	dir = dir.Magnitude > 2 and dir.Unit or root.CFrame.LookVector
	local orb = neon("PauseBolt", Vector3.one * 0.8, CFrame.new(origin), color, 0)
	orb.Shape = Enum.PartType.Ball
	ownShots[orb] = character
	local ring = neon("BoltRing", Vector3.new(0.12, 2.2, 2.2), CFrame.new(origin), color, 0.3)
	ring.Shape = Enum.PartType.Cylinder
	ring.Parent = orb
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 0.35, 0), Vector3.new(0, -0.35, 0)
	a0.Parent, a1.Parent = orb, orb
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = orb
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 2, 8
	light.Parent = orb
	sound(orb, blade.Sounds.Swing[1], 0.7, 0.6)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, orb, zones }
	local travelled = 0
	local conn
	local function finish(pos)
		conn:Disconnect()
		TimeEffects.burst(pos, color)
		orb:Destroy()
	end
	conn = RunService.Heartbeat:Connect(function(dt)
		if not orb.Parent then
			conn:Disconnect()
			return
		end
		if orb:GetAttribute("TimeStopped") then return end -- hanging in someone else's stopped time
		local step = S.Speed * dt
		local cast = workspace:Spherecast(orb.Position, S.Radius * 0.5, dir * step, params)
		if cast then
			local model = cast.Instance:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") and not CollectionService:HasTag(model, "SpinjitzuNPC") then
				if hit(blade, model, S.Damage, true) then TimeEffects.lock(model, S.Lock, color) end
			end
			finish(cast.Position)
			return
		end
		travelled += step
		local pos = orb.Position + dir * step
		orb.CFrame = CFrame.new(pos)
		ring.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.pi / 2, 0)
		if travelled > S.Range then finish(pos) end
	end)
end

----------------------------------------------------------------------------------------
-- V: Stop-Step
----------------------------------------------------------------------------------------

-- a see-through copy of you in the blade's colour, shifted by offset, fading out
local function afterimage(character, offset, color, life)
	for _, p in ipairs(character:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 1 then
			local c = p:Clone()
			if c then
				c:ClearAllChildren()
				c.Name = "Afterimage"
				c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow, c.Massless = true, false, false, false, false, true
				c.Material = Enum.Material.Neon
				c.Color = color
				c.Transparency = 0.55
				c.CFrame = p.CFrame + offset
				c.Parent = workspace
				TweenService:Create(c, TweenInfo.new(life), { Transparency = 1 }):Play()
				Debris:AddItem(c, life)
			end
		end
	end
end

local function stopStep(player, character, root, blade, aim)
	local S = blade.Step
	local color = blade.EnergyColor
	local untilT = os.clock() + S.Freeze
	local held = {}
	catchIn(root.Position, S.Radius, untilT, character, color, held)
	tint(player, S.Freeze)
	sound(root, blade.Sounds.Final, 0.9, 0.5)

	-- dash toward where you aim (a bit past it), stopping short of walls; people don't stop you
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	if flat.Magnitude < 1 then flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	local dir = flat.Unit
	local dist = math.clamp(flat.Magnitude + 5, 10, S.Distance)
	local ignore = { character, zones }
	for thing in pairs(held) do
		if thing:IsA("Model") then table.insert(ignore, thing) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local from = root.Position
	local wall = workspace:Raycast(from, dir * dist, params)
	if wall then dist = math.max(wall.Distance - 2, 0) end
	local to = from + dir * dist
	for i = 0, 3 do afterimage(character, dir * dist * i / 4, color, S.Freeze + 0.4) end
	character:PivotTo(CFrame.lookAt(to, to + dir))

	-- everyone you went through gets hit at once when time starts again
	local victims = {}
	for thing in pairs(held) do
		local r = thing:IsA("Model") and thing:FindFirstChild("HumanoidRootPart")
		if r then
			local rel = r.Position - from
			local gap = rel - dir * math.clamp(rel:Dot(dir), 0, dist)
			if Vector3.new(gap.X, 0, gap.Z).Magnitude <= S.HitWidth then table.insert(victims, thing) end
		end
	end
	task.delay(S.Freeze + 0.05, function()
		for _, model in ipairs(victims) do
			local r = hit(blade, model, S.Damage, true)
			if r and not r.Anchored then r.AssemblyLinearVelocity = dir * S.Knock + Vector3.new(0, 18, 0) end
		end
		if #victims > 0 and root.Parent then sound(root, blade.Sounds.Hit[1], 1, 0.8) end
	end)
end

----------------------------------------------------------------------------------------
-- Z: Stopped World
----------------------------------------------------------------------------------------

local function stoppedWorld(player, character, root, blade)
	local S = blade.World
	local color = blade.EnergyColor
	local center = root.Position
	local zone = Instance.new("Part")
	zone.Name = "StoppedWorld"
	zone.Anchored, zone.CanCollide, zone.CanQuery, zone.CanTouch = true, false, false, false
	zone.Transparency = 1
	zone.Size = Vector3.one
	zone.CFrame = CFrame.new(center)
	zone:SetAttribute("Radius", S.Radius)
	zone.Parent = zones
	-- a wave of stopped time rolls out from you
	local wave = Instance.new("Part")
	wave.Name = "TimeWave"
	wave.Shape = Enum.PartType.Ball
	wave.Material = Enum.Material.ForceField
	wave.Color = color
	wave.Anchored, wave.CanCollide, wave.CanQuery, wave.CanTouch, wave.CastShadow = true, false, false, false, false
	wave.Size = Vector3.one * 2
	wave.CFrame = CFrame.new(center)
	wave.Parent = workspace
	TweenService:Create(wave, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * S.Radius * 2 }):Play()
	task.delay(0.8, function() TweenService:Create(wave, TweenInfo.new(0.5), { Transparency = 1 }):Play() end)
	Debris:AddItem(wave, 1.4)
	sound(root, blade.Sounds.Final, 1.2, 0.35)
	tint(player, S.Time)

	local untilT = os.clock() + S.Time
	local held = {}
	while os.clock() < untilT do
		catchIn(center, S.Radius, untilT, character, color, held)
		task.wait(0.1)
	end
	zone:Destroy()
	if root.Parent then sound(root, blade.Sounds.Final, 1, 1.4) end
	release(held, color)
end

local POWERS = { Stop = timeStop, Bolt = pauseBolt, Step = stopStep, World = stoppedWorld }

local readyAt = {} -- [player] = { [power id] = os.clock() when it can be used again }

remote.OnServerEvent:Connect(function(player, id, aim)
	if typeof(id) ~= "string" or typeof(aim) ~= "Vector3" or aim.X ~= aim.X or aim.Y ~= aim.Y or aim.Z ~= aim.Z then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local tool = character and character:FindFirstChildOfClass("Tool")
	local blade = tool and GoldenWeapons.ForTool(tool.Name)
	if not root or not hum or hum.Health <= 0 or not blade or not blade.Abilities then return end
	if character:GetAttribute("TimeStopped") then return end -- can't use time while yours is stopped
	local ability
	for _, a in ipairs(blade.Abilities) do
		if a.id == id then ability = a end
	end
	local run = ability and POWERS[id]
	if not run then return end
	local mine = readyAt[player] or {}
	readyAt[player] = mine
	local now = os.clock()
	if now < (mine[id] or 0) then
		notify(player, ("%s ready in %ds"):format(ability.name, math.ceil(mine[id] - now)))
		return
	end
	mine[id] = now + ability.cooldown
	player:SetAttribute("TimeReady" .. id, workspace:GetServerTimeNow() + ability.cooldown)
	-- the arm move (every client plays it)
	tool:SetAttribute("CastMove", ability.move)
	tool:SetAttribute("CastTime", ability.moveTime)
	tool:SetAttribute("CastId", (tool:GetAttribute("CastId") or 0) + 1)
	task.spawn(run, player, character, root, blade, aim)
end)

Players.PlayerRemoving:Connect(function(player)
	readyAt[player] = nil
end)
