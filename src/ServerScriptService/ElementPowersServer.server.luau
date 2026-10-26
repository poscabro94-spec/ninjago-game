-- ElementPowersServer v1.1  (Script in ServerScriptService)
-- The elemental powers (settings in ElementPowers). The client (ElementPowersClient) sends:
--   "ball", aim         tap left click: next lightning ball of the combo
--   "beam", aim / false hold left click: beam on / let go: off
--   "aim", aim          where the beam points (a few times a second while it's on)
-- Only with empty hands, and not during Spinjitzu / dragon / Tornado of Creation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Powers = require(ReplicatedStorage:WaitForChild("ElementPowers"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local HitEffects = require(script.Parent:WaitForChild("HitEffects"))
local L = Powers.Lightning

local remote = ReplicatedStorage:FindFirstChild("ElementPower")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ElementPower"
	remote.Parent = ReplicatedStorage
end

local function elementOf(player)
	local e = player:GetAttribute("SpinjitzuElement")
	if e and Config.Presets[e] then return e end
	return Config.Element
end

-- character, root, humanoid if the player can use a power right now
local function ready(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return nil end
	if elementOf(player) ~= "Lightning" then return nil end
	if character:FindFirstChildOfClass("Tool") then return nil end
	if character:GetAttribute("SpinjitzuActive") or character:GetAttribute("DragonPhase") or character:GetAttribute("CreationPhase") then
		return nil
	end
	return character, root, hum
end

local function validAim(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function canHit(model, character)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return hum and model ~= character and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC") and hum or nil
end

local function damage(model, hum, amount, final, push)
	hum:TakeDamage(amount)
	model:SetAttribute("LastHit", os.clock())
	local tRoot = model:FindFirstChild("HumanoidRootPart")
	if tRoot and push and not tRoot.Anchored then tRoot.AssemblyLinearVelocity = push end
	if tRoot then HitEffects.show(L, tRoot, model, amount, final) end
end

local function fxSpot(pos, life)
	local p = Instance.new("Part")
	p.Name = "PowerFx"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	Debris:AddItem(p, life)
	return p
end

local function playSound(parent, id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed, s.RollOffMaxDistance = id, volume, pitch or 1, 120
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
	return s
end

-- a bright ball that swells and fades
local function flash(pos, from, to, time)
	local f = Instance.new("Part")
	f.Shape = Enum.PartType.Ball
	f.Material = Enum.Material.Neon
	f.Color = L.CoreColor
	f.Anchored, f.CanCollide, f.CanQuery, f.CanTouch, f.CastShadow = true, false, false, false, false
	f.Transparency = 0.15
	f.Size = Vector3.one * from
	f.CFrame = CFrame.new(pos)
	f.Parent = workspace
	TweenService:Create(f, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * to, Transparency = 1, Color = L.Color }):Play()
	Debris:AddItem(f, time + 0.05)
end

local function sparks(parent, count, speed, size)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(L.Color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.3), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.15, 0.4)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.Rate = 0
	pe.Parent = parent
	if count > 0 then pe:Emit(count) end
	return pe
end

----------------------------------------------------------------------------------------
-- lightning balls
----------------------------------------------------------------------------------------

-- the big one: everyone around the impact gets hit and thrown back
local function blast(character, pos, ball)
	local spot = fxSpot(pos, 1.5)
	sparks(spot, 60, 30, 0.6)
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = L.Color, 6, 22
	light.Parent = spot
	playSound(spot, L.Sounds.Final, 1)
	playSound(spot, L.Sounds.Zap, 0.9, 0.55)
	playSound(spot, L.Sounds.Zap, 0.6, 1.3)
	flash(pos, 1, 5, 0.18)
	-- a ring rushing out along the ground
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local down = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = L.Color
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new((down and down.Position or pos) + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, ball.blast * 3.2, ball.blast * 3.2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.Neon
	shell.Color = L.Color
	shell.Anchored, shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.CastShadow = true, false, false, false, false
	shell.Transparency = 0.3
	shell.Size = Vector3.new(2, 2, 2)
	shell.CFrame = CFrame.new(pos)
	shell.Parent = workspace
	TweenService:Create(shell, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * ball.blast * 2, Transparency = 1 }):Play()
	Debris:AddItem(shell, 0.4)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, ball.blast, params)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = canHit(model, character)
		if hum and not done[model] then
			done[model] = true
			local away = part.Position - pos
			away = Vector3.new(away.X, 0, away.Z)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)
			damage(model, hum, ball.damage, true, away * 40 + Vector3.new(0, 22, 0))
		end
	end
end

local function launchBall(character, origin, dir, ball)
	local p = Instance.new("Part")
	p.Name = "LightningBall"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * ball.size
	p.Material = Enum.Material.Neon
	p.Color = L.Color
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	p.CFrame = CFrame.new(origin)
	-- white-hot core, glow, crackle, tail
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one * ball.size * 0.55
	core.Material = Enum.Material.Neon
	core.Color = L.CoreColor
	core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow, core.Massless = false, false, false, false, true
	core.CFrame = p.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = p, core
	weld.Parent = core
	core.Parent = p
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = L.Color, 3, ball.size * 8
	light.Parent = p
	local crackle = sparks(p, 0, 8, ball.size * 0.25)
	crackle.Rate = 40
	local a = Instance.new("Attachment")
	a.Parent = p
	local t0, t1 = Instance.new("Attachment"), Instance.new("Attachment")
	t0.Position, t1.Position = Vector3.new(0, ball.size * 0.4, 0), Vector3.new(0, -ball.size * 0.4, 0)
	t0.Parent, t1.Parent = p, p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = t0, t1
	trail.Lifetime = 0.2
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(L.CoreColor, L.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = p
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = a
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = dir * L.BallSpeed
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = p
	p.Parent = workspace
	pcall(function() p:SetNetworkOwner(nil) end)
	p.AssemblyLinearVelocity = dir * L.BallSpeed

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, p }
	local last, travelled, born = origin, 0, os.clock()
	local conn
	local function finish(at, model, hum)
		conn:Disconnect()
		p:Destroy()
		if ball.blast then
			blast(character, at, ball)
		else
			if hum then damage(model, hum, ball.damage, false, dir * 18 + Vector3.new(0, 8, 0)) end
			local spot = fxSpot(at, 1)
			sparks(spot, 28, 22, 0.35)
			flash(at, ball.size, ball.size * 3.5, 0.2)
			local l = Instance.new("PointLight")
			l.Color, l.Brightness, l.Range = L.Color, 5, 12
			l.Parent = spot
			task.delay(0.1, function() l.Enabled = false end)
			playSound(spot, L.Sounds.Zap, 0.6, 1 + math.random() * 0.4)
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		if not p.Parent then
			conn:Disconnect()
			return
		end
		local now = p.Position
		local step = now - last
		if step.Magnitude > 1e-3 then
			local hit = workspace:Spherecast(last, ball.size / 2, step, params)
			if hit then
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				finish(hit.Position, model, canHit(model, character))
				return
			end
			travelled += step.Magnitude
			last = now
		end
		if travelled > L.BallRange or os.clock() - born > 3 then finish(now) end
	end)
end

local combos = {} -- [player] = { step, start, len }

local function throw(player, aim)
	local character, root = ready(player)
	if not character or character:GetAttribute("PowerBeam") then return end
	local c = combos[player]
	if not c then
		c = { step = 0, start = 0, len = 0 }
		combos[player] = c
	end
	local now = os.clock()
	if now - c.start < c.len * 0.8 then return end -- still mid-throw
	if now - (c.start + c.len) > L.ComboWindow then c.step = 0 end
	c.step = c.step % #L.Balls + 1
	local ball = L.Balls[c.step]
	c.start, c.len = now, ball.time
	character:SetAttribute("PowerMove", ball.name)
	character:SetAttribute("PowerId", (character:GetAttribute("PowerId") or 0) + 1)
	local whoosh = Instance.new("Sound")
	whoosh.SoundId, whoosh.Volume, whoosh.PlaybackSpeed = L.Sounds.Throw, 0.5, 1.2 + math.random() * 0.2
	whoosh.Parent = root
	whoosh:Play()
	Debris:AddItem(whoosh, 2)
	if ball.hands == "B" then playSound(root, L.Sounds.Zap, 0.5, 0.7) end -- the big one charges up

	task.delay(ball.time * ball.release, function()
		if player.Character ~= character or not root.Parent then return end
		-- the server doesn't see the arm animation: let go about where the palm is
		local x = ball.hands == "R" and 1.0 or (ball.hands == "L" and -1.0 or 0)
		local origin = root.CFrame:PointToWorldSpace(Vector3.new(x, 1.0, -1.8))
		local dir = aim - origin
		if dir.Magnitude < 3 or dir.Unit:Dot(root.CFrame.LookVector) < -0.2 then dir = root.CFrame.LookVector end
		launchBall(character, origin, dir.Unit, ball)
	end)
end

----------------------------------------------------------------------------------------
-- lightning beam: damage ticks along the line from the hand to the aim
----------------------------------------------------------------------------------------

local beams = {} -- [player] = { character, last, total, ticks }

local function stopBeam(player)
	local b = beams[player]
	beams[player] = nil
	if b and b.character.Parent then b.character:SetAttribute("PowerBeam", nil) end
end

local function startBeam(player, aim)
	if beams[player] then return end
	local character = ready(player)
	if not character then return end
	if validAim(aim) then character:SetAttribute("PowerAim", aim) end
	character:SetAttribute("PowerBeam", true)
	beams[player] = { character = character, last = 0, total = {}, ticks = 0 }
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, b in pairs(beams) do
		local character, root = ready(player)
		if character ~= b.character then
			stopBeam(player)
		elseif now - b.last >= L.BeamTick then
			b.last = now
			b.ticks += 1
			local aim = character:GetAttribute("PowerAim")
			if typeof(aim) == "Vector3" then
				local origin = root.CFrame:PointToWorldSpace(Vector3.new(0, 1.1, -2.4)) -- where the two hand beams meet
				local dir = aim - origin
				if dir.Magnitude > 0.5 then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { character }
					local hit = workspace:Spherecast(origin, L.BeamRadius, dir.Unit * L.BeamRange, params)
					local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
					local hum = hit and canHit(model, character)
					if hum then
						hum:TakeDamage(L.BeamDamage)
						model:SetAttribute("LastHit", now)
						-- show the damage every few ticks, added up, so the numbers stay readable
						b.total[model] = (b.total[model] or 0) + L.BeamDamage
						if b.ticks % 3 == 0 then
							local tRoot = model:FindFirstChild("HumanoidRootPart")
							if tRoot then HitEffects.show(L, tRoot, model, b.total[model], false) end
							b.total[model] = 0
						end
					end
				end
			end
		end
	end
end)

remote.OnServerEvent:Connect(function(player, action, value)
	if action == "ball" then
		if validAim(value) then throw(player, value) end
	elseif action == "beam" then
		if value == false then stopBeam(player) else startBeam(player, value) end
	elseif action == "aim" then
		local b = beams[player]
		if b and validAim(value) then b.character:SetAttribute("PowerAim", value) end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	beams[player] = nil
	combos[player] = nil
end)
