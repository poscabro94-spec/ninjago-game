-- TimeBladesServer v1.0  (Script in ServerScriptService)
-- The Time Blades' powers (F while holding one; GoldenWeaponsClient sends "TimeBladePower" with
-- where you aim). So far:
--   Pause: a red dome of stopped time in front of you. Everyone inside is frozen in place and
--          mid-pose, shots inside hang in the air; after a few seconds time snaps back.
-- Settings are on the blade (GoldenWeapons.PauseBlade.Pause).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local TimeEffects = require(script.Parent:WaitForChild("TimeEffects"))

local remote = ReplicatedStorage:FindFirstChild("TimeBladePower")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TimeBladePower"
	remote.Parent = ReplicatedStorage
end

-- flying shots that stopped time can catch
local SHOTS = {
	LightningBall = true, Fireball = true, WaterBall = true, EnergyBall = true, IceShard = true, Rock = true,
	ThrownShuriken = true,
}

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

local function pause(player, character, root, blade, aim)
	local S = blade.Pause
	local color = blade.EnergyColor
	-- the dome goes where you aim, up to Reach studs in front of you
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	if flat.Magnitude < 0.5 then flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	local center = root.Position + flat.Unit * math.min(flat.Magnitude, S.Reach)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local down = workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
	local ground = down and down.Position or center - Vector3.new(0, 3, 0)

	-- the dome, a ring on the ground and two clock hands turning backwards
	local dome = Instance.new("Part")
	dome.Name = "TimeStop"
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.ForceField
	dome.Color = color
	dome.Anchored, dome.CanCollide, dome.CanQuery, dome.CanTouch, dome.CastShadow = true, false, false, false, false
	dome.Size = Vector3.one * 2
	dome.CFrame = CFrame.new(ground)
	dome.Parent = workspace
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

	-- freeze what's inside: everyone (but you), and every shot, including ones that fly in later
	local stopAt = os.clock() + S.Time
	local held = {}
	local function catch()
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { character }
		for _, part in ipairs(workspace:GetPartBoundsInRadius(ground, S.Radius, overlap)) do
			local model = part:FindFirstAncestorOfClass("Model")
			local hum = model and model:FindFirstChildOfClass("Humanoid")
			if hum and not held[model] and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC") then
				held[model] = true
				TimeEffects.lock(model, stopAt - os.clock(), color)
			end
		end
		for _, child in ipairs(workspace:GetChildren()) do
			if SHOTS[child.Name] and child:IsA("BasePart") and not held[child] and (child.Position - ground).Magnitude <= S.Radius then
				held[child] = true
				TimeEffects.holdPart(child, stopAt - os.clock())
			end
		end
	end

	local t0 = os.clock()
	while os.clock() < stopAt do
		catch()
		-- clock hands spin backwards
		local a = -(os.clock() - t0) * 1.5
		long.CFrame = CFrame.new(hub) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -S.Radius * 0.42)
		short.CFrame = CFrame.new(hub) * CFrame.Angles(0, a / 6, 0) * CFrame.new(0, 0, -S.Radius * 0.27)
		task.wait(0.05)
	end

	-- time snaps back
	sound(dome, blade.Sounds.Final, 0.8, 1.4)
	for thing in pairs(held) do
		local pos = thing:IsA("Model") and thing:GetPivot().Position or (thing.Parent and thing.Position)
		if pos then TimeEffects.burst(pos, color) end
	end
	TweenService:Create(dome, TweenInfo.new(0.25), { Size = Vector3.one * 0.5, Transparency = 1 }):Play()
	for _, p in ipairs({ ring, long, short }) do
		TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end
	Debris:AddItem(dome, 0.3)
	for _, p in ipairs({ ring, long, short }) do Debris:AddItem(p, 0.3) end
end

local readyAt = {} -- [player] = os.clock() when the power can be used again

remote.OnServerEvent:Connect(function(player, aim)
	if typeof(aim) ~= "Vector3" or aim.X ~= aim.X or aim.Y ~= aim.Y or aim.Z ~= aim.Z then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local tool = character and character:FindFirstChildOfClass("Tool")
	local power = tool and tool:GetAttribute("TimePower")
	if not root or not hum or hum.Health <= 0 or not power then return end
	if character:GetAttribute("TimeStopped") then return end -- can't stop time while you're stopped
	local now = os.clock()
	if now < (readyAt[player] or 0) then
		notify(player, ("%s ready in %ds"):format(power, math.ceil(readyAt[player] - now)))
		return
	end
	if power == "Pause" then
		local blade = GoldenWeapons.PauseBlade
		readyAt[player] = now + blade.Pause.Cooldown
		task.spawn(pause, player, character, root, blade, aim)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	readyAt[player] = nil
end)
