-- ElementPowersServer v2.0  (Script in ServerScriptService)
-- The elemental powers (settings in ElementPowers): Lightning, Fire, Ice, Earth.
-- The client (ElementPowersClient) sends:
--   "ball", aim         tap left click: next shot of the combo
--   "beam", aim / false hold left click: beam on / let go: off
--   "aim", aim          where the beam points (a few times a second while it's on)
-- Only with empty hands, and not during Spinjitzu / dragon / Tornado of Creation.
-- Also runs the Lightning demo bot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Powers = require(ReplicatedStorage:WaitForChild("ElementPowers"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local HitEffects = require(script.Parent:WaitForChild("HitEffects"))
local Status = require(script.Parent:WaitForChild("StatusEffects"))
local Bots = require(script.Parent:WaitForChild("SpinjitzuBots"))
local TrainingDummy = require(script.Parent:WaitForChild("TrainingDummy"))
local TAU = math.pi * 2

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

local function elementName(P)
	for element, settings in pairs(Powers.ByElement) do
		if settings == P then return element end
	end
	return nil
end

-- character, root, power settings if the player can use their element's power right now
local function ready(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return nil end
	local P = Powers.ByElement[elementOf(player)]
	if not P then return nil end
	if character:FindFirstChildOfClass("Tool") then return nil end
	if character:GetAttribute("SpinjitzuActive") or character:GetAttribute("DragonPhase") or character:GetAttribute("CreationPhase") then
		return nil
	end
	return character, root, P
end

local function validAim(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

----------------------------------------------------------------------------------------
-- effects
----------------------------------------------------------------------------------------

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
	if not id then return nil end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed, s.RollOffMaxDistance = id, volume, pitch or 1, 120
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
	return s
end

-- a bright ball that swells and fades
local function flash(P, pos, from, to, time)
	local f = Instance.new("Part")
	f.Shape = Enum.PartType.Ball
	f.Material = Enum.Material.Neon
	f.Color = P.CoreColor
	f.Anchored, f.CanCollide, f.CanQuery, f.CanTouch, f.CastShadow = true, false, false, false, false
	f.Transparency = 0.15
	f.Size = Vector3.one * from
	f.CFrame = CFrame.new(pos)
	f.Parent = workspace
	TweenService:Create(f, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * to, Transparency = 1, Color = P.Color }):Play()
	Debris:AddItem(f, time + 0.05)
end

local function sparks(P, parent, count, speed, size)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(P.Color, P.CoreColor)
	pe.LightEmission = P.Shot == "rock" and 0 or 1
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

local function light(P, parent, brightness, range)
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range = P.Color, brightness, range
	l.Parent = parent
	return l
end

local function dust(P, parent, size)
	local pe = sparks(P, parent, 0, 10, size)
	pe.LightEmission = 0
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	return pe
end

-- a ring rushing out along the ground
local function groundRing(P, pos, radius, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local down = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = P.Color
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new((down and down.Position or pos) + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
end

----------------------------------------------------------------------------------------
-- hits
----------------------------------------------------------------------------------------

-- the third shot's extra: shock / burn / freeze
local function applyStatus(P, model, hum, status)
	if status == "shock" then
		Status.shock(P, model, hum, P.StatusTime or 3, P.StatusDamage or 5)
	elseif status == "burn" then
		Status.burn(P, model, hum, P.StatusTime or 3, P.StatusDamage or 5)
	elseif status == "freeze" then
		Status.freeze(P, model, hum, P.FreezeTime or 2.5)
	end
end

local function damage(P, model, hum, amount, final, push)
	hum:TakeDamage(amount)
	model:SetAttribute("LastHit", os.clock())
	local tRoot = model:FindFirstChild("HumanoidRootPart")
	if tRoot and push and not tRoot.Anchored and not model:GetAttribute("FrozenSpeed") then tRoot.AssemblyLinearVelocity = push end
	if tRoot then HitEffects.show(P, tRoot, model, amount, final) end
end

-- everyone within radius of pos (not the attacker) gets `ball`'s damage + status, thrown away
local function hitAround(P, character, pos, radius, ball, knock, up)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, params)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = Status.target(model, character)
		if hum and not done[model] then
			done[model] = true
			local away = part.Position - pos
			away = Vector3.new(away.X, 0, away.Z)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)
			damage(P, model, hum, ball.damage, ball.final, away * knock + Vector3.new(0, up, 0))
			applyStatus(P, model, hum, ball.status)
		end
	end
end

-- the big ones (Lightning, Fire): explosion around the impact
local function blast(P, character, pos, ball)
	local spot = fxSpot(pos, 1.5)
	sparks(P, spot, 60, 30, 0.6)
	light(P, spot, 6, 22)
	playSound(spot, P.Sounds.Final, 1)
	if P.Sounds.Zap then
		playSound(spot, P.Sounds.Zap, 0.9, 0.55)
		playSound(spot, P.Sounds.Zap, 0.6, 1.3)
	end
	flash(P, pos, 1, 5, 0.18)
	groundRing(P, pos, ball.blast * 1.6, character)
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.Neon
	shell.Color = P.Color
	shell.Anchored, shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.CastShadow = true, false, false, false, false
	shell.Transparency = 0.3
	shell.Size = Vector3.new(2, 2, 2)
	shell.CFrame = CFrame.new(pos)
	shell.Parent = workspace
	TweenService:Create(shell, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * ball.blast * 2, Transparency = 1 }):Play()
	Debris:AddItem(shell, 0.4)
	if P.Shot == "fire" then
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(P.CoreColor, P.Color)
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0.5) })
		fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		fire.Lifetime = NumberRange.new(0.4, 0.8)
		fire.Speed = NumberRange.new(10, 22)
		fire.SpreadAngle = Vector2.new(180, 180)
		fire.Drag = 4
		fire.Rate = 0
		fire.Parent = spot
		fire:Emit(60)
	end
	hitAround(P, character, pos, ball.blast, ball, 40, 22)
end

-- Earth's third: rocks burst out of the ground in a line toward the aim, throwing everyone up
local function earthWave(P, character, root, aim, ball)
	local wave = ball.wave
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local dir = flat.Magnitude > 0.5 and flat.Unit or look.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	local hit = {}
	local start = root.Position
	playSound(root, P.Sounds.Final, 0.9, 0.8)
	task.spawn(function()
		for i = 1, math.floor(wave.length / wave.step) do
			local at = start + dir * (2 + i * wave.step)
			local down = workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
			local ground = down and down.Position or (at - Vector3.new(0, 3, 0))
			-- a few rocks shoot up out of the ground, then sink back
			for _ = 1, 3 do
				local s = 1 + math.random() * 1.6
				local rock = Instance.new("Part")
				rock.Name = "WaveRock"
				rock.Size = Vector3.new(s, s * (0.8 + math.random() * 0.8), s)
				rock.Material = Enum.Material.Slate
				rock.Color = P.RockColor
				rock.Anchored, rock.CanCollide, rock.CanQuery, rock.CanTouch = true, false, false, false
				local side = dir:Cross(Vector3.yAxis) * (math.random() * 2.4 - 1.2)
				local tilt = CFrame.Angles(math.random() * 0.8 - 0.4, math.random() * TAU, math.random() * 0.8 - 0.4)
				local under = CFrame.new(ground + side - Vector3.new(0, s, 0)) * tilt
				rock.CFrame = under
				rock.Parent = workspace
				TweenService:Create(rock, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ CFrame = under + Vector3.new(0, s * 1.1, 0) }):Play()
				task.delay(0.9, function()
					TweenService:Create(rock, TweenInfo.new(0.4), { CFrame = under, Transparency = 0.5 }):Play()
				end)
				Debris:AddItem(rock, 1.4)
			end
			dust(P, fxSpot(ground, 1.5), 1.6):Emit(6)
			-- everyone near this point gets thrown up (once per wave)
			for _, part in ipairs(workspace:GetPartBoundsInRadius(ground, wave.radius, overlap)) do
				local model = part:FindFirstAncestorOfClass("Model")
				local hum = Status.target(model, character)
				if hum and not hit[model] then
					hit[model] = true
					damage(P, model, hum, ball.damage, true, dir * 20 + Vector3.new(0, wave.up, 0))
				end
			end
			task.wait(0.04)
		end
	end)
end

----------------------------------------------------------------------------------------
-- shots
----------------------------------------------------------------------------------------

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
end

-- the flying part: a lightning ball, a fireball, an ice shard or a rock
local function makeShot(P, ball, origin, dir)
	local s = ball.size
	local p = Instance.new("Part")
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	if P.Shot == "ice" then
		p.Name = "IceShard"
		p.Size = Vector3.new(0.45, 0.45, 1.8) * s
		p.Material = Enum.Material.Glass
		p.Color = P.Color
		p.Transparency = 0.2
		p.CFrame = CFrame.lookAt(origin, origin + dir)
		local tip = Instance.new("WedgePart")
		tip.Size = Vector3.new(0.45, 0.45, 0.7) * s
		tip.Material, tip.Color, tip.Transparency = Enum.Material.Glass, P.CoreColor, 0.1
		tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.Massless = false, false, false, true
		tip.CFrame = p.CFrame * CFrame.new(0, 0, -1.25 * s) * CFrame.Angles(0, math.pi, 0)
		weld(p, tip)
		tip.Parent = p
	elseif P.Shot == "rock" then
		p.Name = "Rock"
		p.Size = Vector3.new(1, 0.85, 1) * s
		p.Material = Enum.Material.Slate
		p.Color = P.RockColor
		p.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * TAU, math.random() * TAU, 0)
	else
		p.Name = P.Shot == "fire" and "Fireball" or "LightningBall" -- (the client decorates LightningBall)
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * s
		p.Material = Enum.Material.Neon
		p.Color = P.Color
		p.CFrame = CFrame.new(origin)
		local core = Instance.new("Part")
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.one * s * 0.55
		core.Material = Enum.Material.Neon
		core.Color = P.CoreColor
		core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow, core.Massless = false, false, false, false, true
		core.CFrame = p.CFrame
		weld(p, core)
		core.Parent = p
		light(P, p, 3, s * 8)
	end
	if P.Shot == "fire" then
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(P.CoreColor, P.Color)
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.9), NumberSequenceKeypoint.new(1, s * 0.2) })
		fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		fire.Lifetime = NumberRange.new(0.2, 0.4)
		fire.Speed = NumberRange.new(1, 3)
		fire.SpreadAngle = Vector2.new(180, 180)
		fire.Rate = 70
		fire.Parent = p
	elseif P.Shot == "rock" then
		dust(P, p, s * 0.6).Rate = 30
	else
		sparks(P, p, 0, P.Shot == "ice" and 3 or 8, s * 0.25).Rate = 40
	end
	-- tail
	local t0, t1 = Instance.new("Attachment"), Instance.new("Attachment")
	t0.Position, t1.Position = Vector3.new(0, s * 0.4, 0), Vector3.new(0, -s * 0.4, 0)
	t0.Parent, t1.Parent = p, p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = t0, t1
	trail.Lifetime = 0.2
	trail.LightEmission = P.Shot == "rock" and 0 or 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(P.CoreColor, P.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, P.Shot == "rock" and 0.5 or 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = p
	return p
end

local function launchShot(P, character, origin, dir, ball)
	local p = makeShot(P, ball, origin, dir)
	local a = Instance.new("Attachment")
	a.Parent = p
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = a
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = dir * P.BallSpeed
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = p
	if P.Shot == "rock" then
		local av = Instance.new("AngularVelocity")
		av.Attachment0 = a
		av.AngularVelocity = Vector3.new(8, 3, 0)
		av.MaxTorque = math.huge
		av.RelativeTo = Enum.ActuatorRelativeTo.World
		av.Parent = p
	end
	p.Parent = workspace
	pcall(function() p:SetNetworkOwner(nil) end)
	p.AssemblyLinearVelocity = dir * P.BallSpeed

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, p }
	local last, travelled, born = origin, 0, os.clock()
	local radius = math.max(p.Size.X, p.Size.Y) / 2
	local conn
	local function finish(at, model, hum)
		conn:Disconnect()
		p:Destroy()
		if ball.blast then
			blast(P, character, at, ball)
			return
		end
		if hum then
			damage(P, model, hum, ball.damage, ball.final, dir * 18 + Vector3.new(0, 8, 0))
			applyStatus(P, model, hum, ball.status)
		end
		local spot = fxSpot(at, 1)
		if P.Shot == "rock" then dust(P, spot, 1.2):Emit(10) end
		sparks(P, spot, 28, 22, 0.35)
		if P.Shot ~= "rock" then flash(P, at, ball.size, ball.size * 3.5, 0.2) end
		local l = light(P, spot, 5, 12)
		task.delay(0.1, function() l.Enabled = false end)
		playSound(spot, P.Sounds.Zap or P.Sounds.Hit[1], 0.6, 1 + math.random() * 0.4)
	end
	conn = RunService.Heartbeat:Connect(function()
		if not p.Parent then
			conn:Disconnect()
			return
		end
		local now = p.Position
		local step = now - last
		if step.Magnitude > 1e-3 then
			local hit = workspace:Spherecast(last, radius, step, params)
			if hit then
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				finish(hit.Position, model, Status.target(model, character))
				return
			end
			travelled += step.Magnitude
			last = now
		end
		if travelled > P.BallRange or os.clock() - born > 3 then finish(now) end
	end)
end

-- A caster is a player or a bot (the demo bot): `key` identifies it, check() returns its
-- character, root and power settings while it can use the power, nil when it can't (anymore).
local function playerCheck(player)
	return function() return ready(player) end
end

local combos = {} -- [key] = { step, start, len, P }

local function throw(key, check, aim)
	local character, root, P = check()
	if not character or character:GetAttribute("PowerBeam") then return end
	local c = combos[key]
	if not c or c.P ~= P then
		c = { step = 0, start = 0, len = 0, P = P }
		combos[key] = c
	end
	local now = os.clock()
	if now - c.start < c.len * 0.8 then return end -- still mid-throw
	if now - (c.start + c.len) > P.ComboWindow then c.step = 0 end
	c.step = c.step % #P.Balls + 1
	local ball = P.Balls[c.step]
	c.start, c.len = now, ball.time
	character:SetAttribute("PowerAim", aim)
	character:SetAttribute("PowerElement", elementName(P))
	character:SetAttribute("PowerMove", ball.name)
	character:SetAttribute("PowerId", (character:GetAttribute("PowerId") or 0) + 1)
	playSound(root, P.Sounds.Throw, 0.5, 1.2 + math.random() * 0.2)
	if ball.hands == "B" and P.Sounds.Zap then playSound(root, P.Sounds.Zap, 0.5, 0.7) end -- the big one charges up

	task.delay(ball.time * ball.release, function()
		if not character.Parent or not root.Parent then return end
		if ball.wave then
			earthWave(P, character, root, aim, ball)
			return
		end
		-- the server doesn't see the arm animation: let go about where the palm is
		local x = ball.hands == "R" and 1.0 or (ball.hands == "L" and -1.0 or 0)
		local origin = root.CFrame:PointToWorldSpace(Vector3.new(x, 1.0, -1.8))
		local dir = aim - origin
		if dir.Magnitude < 3 or dir.Unit:Dot(root.CFrame.LookVector) < -0.2 then dir = root.CFrame.LookVector end
		launchShot(P, character, origin, dir.Unit, ball)
	end)
end

----------------------------------------------------------------------------------------
-- beams: damage ticks along the line from the hands to the aim
----------------------------------------------------------------------------------------

local beams = {} -- [key] = { character, check, P, last, total, ticks, exposure, seen }

local function stopBeam(key)
	local b = beams[key]
	beams[key] = nil
	if b and b.character.Parent then b.character:SetAttribute("PowerBeam", nil) end
end

local function startBeam(key, check, aim)
	if beams[key] then return end
	local character, _, P = check()
	if not character then return end
	if validAim(aim) then character:SetAttribute("PowerAim", aim) end
	character:SetAttribute("PowerElement", elementName(P))
	character:SetAttribute("PowerBeam", true)
	beams[key] = { character = character, check = check, P = P, last = 0, total = {}, ticks = 0, exposure = {}, seen = {}, burnAt = {} }
end

local function beamHit(b, P, model, hum, now, dir)
	hum:TakeDamage(P.BeamDamage)
	model:SetAttribute("LastHit", now)
	-- show the damage every few ticks, added up, so the numbers stay readable
	b.total[model] = (b.total[model] or 0) + P.BeamDamage
	local tRoot = model:FindFirstChild("HumanoidRootPart")
	if b.ticks % 3 == 0 then
		if tRoot then HitEffects.show(P, tRoot, model, b.total[model], false) end
		b.total[model] = 0
	end
	if P.BeamStatus == "burn" then
		-- keeps them burning while it's on them (restarts the burn once a second)
		if now - (b.burnAt[model] or 0) > 1 then
			b.burnAt[model] = now
			Status.burn(P, model, hum, P.StatusTime or 3, P.StatusDamage or 5)
		end
	elseif P.BeamStatus == "freeze" then
		-- has to stay on them for FreezeAfter seconds, then they freeze
		if b.seen[model] and now - b.seen[model] > 0.5 then b.exposure[model] = 0 end
		b.exposure[model] = (b.exposure[model] or 0) + P.BeamTick
		if b.exposure[model] >= (P.FreezeAfter or 5) then
			b.exposure[model] = 0
			Status.freeze(P, model, hum, P.FreezeTime or 2.5)
		end
	elseif P.BeamStatus == "push" then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if tRoot and not tRoot.Anchored and not model:GetAttribute("FrozenSpeed") and flat.Magnitude > 0.1 then
			tRoot.AssemblyLinearVelocity = flat.Unit * 28 + Vector3.new(0, 6, 0)
		end
	end
	b.seen[model] = now
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for key, b in pairs(beams) do
		local character, root, P = b.check()
		if character ~= b.character or P ~= b.P then
			stopBeam(key)
		elseif now - b.last >= P.BeamTick then
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
					local hit = workspace:Spherecast(origin, P.BeamRadius, dir.Unit * P.BeamRange, params)
					local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
					local hum = hit and Status.target(model, character)
					if hum then beamHit(b, P, model, hum, now, dir.Unit) end
				end
			end
		end
	end
end)

remote.OnServerEvent:Connect(function(player, action, value)
	if action == "ball" then
		if validAim(value) then throw(player, playerCheck(player), value) end
	elseif action == "beam" then
		if value == false then stopBeam(player) else startBeam(player, playerCheck(player), value) end
	elseif action == "aim" then
		local b = beams[player]
		if b and validAim(value) then b.character:SetAttribute("PowerAim", value) end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	beams[player] = nil
	combos[player] = nil
end)

----------------------------------------------------------------------------------------
-- demo bot: a Lightning ninja 50 studs behind the Lightning Spinjitzu bot, with an infinite
-- dummy to aim at: ball, ball, big ball, 3 seconds of beam, on repeat
----------------------------------------------------------------------------------------

if Powers.DemoBot then
	task.spawn(function()
		local spinBot = workspace:WaitForChild("SpinjitzuBot_Lightning", 15)
		local base = spinBot and spinBot:GetPivot().Position or Vector3.new(8, 0, 20)
		local spot = Vector3.new(base.X, 0, base.Z + 50)
		local target = spot + Vector3.new(0, 0, 22)
		local dummy = TrainingDummy.spawn(target, spot, { infinite = true })
		local bot = Bots.make("Lightning", spot, "PowerBot_Lightning", target)
		bot:FindFirstChildOfClass("Humanoid").DisplayName = "Lightning Power Bot"
		CollectionService:AddTag(bot, "AnimatedNPC") -- clients animate its arms like a player's
		local root = bot:WaitForChild("HumanoidRootPart")
		local check = function()
			if bot.Parent and root.Parent then return bot, root, Powers.Lightning end
			return nil
		end
		local function aim()
			local dRoot = dummy and dummy.Parent and dummy:FindFirstChild("HumanoidRootPart")
			return dRoot and dRoot.Position or target + Vector3.new(0, 3, 0)
		end
		task.wait(3)
		while bot.Parent do
			for i = 1, #Powers.Lightning.Balls do
				throw(bot, check, aim())
				task.wait(Powers.Lightning.Balls[i].time + 0.3)
			end
			task.wait(0.5)
			startBeam(bot, check, aim())
			task.wait(3)
			stopBeam(bot)
			task.wait(1.5)
		end
	end)
end
