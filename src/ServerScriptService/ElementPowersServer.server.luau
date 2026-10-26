-- ElementPowersServer v2.1  (Script in ServerScriptService)
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

-- an element's effect on someone (the third shot's extra, or a lost clash). from = where it came from
local function applyStatus(P, model, hum, status, from)
	if status == "shock" then
		Status.shock(P, model, hum, P.StatusTime or 3, P.StatusDamage or 5)
	elseif status == "burn" then
		Status.burn(P, model, hum, P.StatusTime or 3, P.StatusDamage or 5)
	elseif status == "freeze" then
		Status.freeze(P, model, hum, P.FreezeTime or 2.5)
	elseif status == "slow" then
		Status.slow(P, model, hum, P.SlowTime or 3)
	elseif status == "launch" then
		Status.launch(model, 60)
	elseif status == "blast" then
		Status.blast(model, from or model:GetPivot().Position, 70)
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
			applyStatus(P, model, hum, ball.status, pos)
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
	if P.Shot == "energy" then
		-- rays of light shooting out of the burst
		for _ = 1, 10 do
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
			dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.yAxis
			local ray = Instance.new("Part")
			ray.Material = Enum.Material.Neon
			ray.Color = P.CoreColor
			ray.Anchored, ray.CanCollide, ray.CanQuery, ray.CanTouch, ray.CastShadow = true, false, false, false, false
			ray.Size = Vector3.new(0.25, 0.25, 1)
			ray.CFrame = CFrame.lookAt(pos, pos + dir)
			ray.Parent = workspace
			local len = ball.blast * (1.2 + math.random())
			TweenService:Create(ray, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.05, 0.05, len), CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -len / 2), Transparency = 1 }):Play()
			Debris:AddItem(ray, 0.35)
		end
	elseif P.Shot == "water" then
		local splash = sparks(P, spot, 0, 30, 0.6)
		splash.LightEmission = 0.3
		splash.Acceleration = Vector3.new(0, -60, 0)
		splash.Lifetime = NumberRange.new(0.5, 0.9)
		splash.SpreadAngle = Vector2.new(70, 70)
		splash.EmissionDirection = Enum.NormalId.Top
		splash:Emit(70)
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
		-- (the client adds crackling arcs / swirling wisps to LightningBall and EnergyBall)
		p.Name = ({ fire = "Fireball", lightning = "LightningBall", water = "WaterBall", energy = "EnergyBall" })[P.Shot]
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * s
		p.Material = P.Shot == "water" and Enum.Material.Glass or Enum.Material.Neon
		p.Transparency = P.Shot == "water" and 0.3 or (P.Shot == "energy" and 0.35 or 0)
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
	elseif P.Shot == "water" then
		local drops = sparks(P, p, 0, 3, s * 0.2)
		drops.LightEmission = 0.3
		drops.Acceleration = Vector3.new(0, -40, 0)
		drops.Rate = 40
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
			applyStatus(P, model, hum, ball.status, at - dir * 3)
		end
		local spot = fxSpot(at, 1)
		if P.Shot == "rock" then dust(P, spot, 1.2):Emit(10) end
		sparks(P, spot, 28, 22, 0.35)
		if P.Shot ~= "rock" then flash(P, at, ball.size, ball.size * 3.5, 0.2) end
		local l = light(P, spot, 5, 12)
		task.delay(0.1, function() l.Enabled = false end)
		playSound(spot, P.Sounds.Zap or P.Sounds.Hit[1], 0.6, 1 + math.random() * 0.4)
	end
	conn = RunService.Heartbeat:Connect(function(dt)
		if not p.Parent then
			conn:Disconnect()
			return
		end
		if p:GetAttribute("TimeStopped") then -- hanging in stopped time (Pause Time Blade)
			born += dt
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

-- npc = the bot's controller (its damageScale weakens its shots)
local function throw(key, check, aim, npc)
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
	if npc and npc.damageScale then ball = setmetatable({ damage = ball.damage * npc.damageScale }, { __index = ball }) end
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

local beams = {}   -- [key] = { character, check, P, npc, last, total, ticks, exposure, seen, burnAt, clash }
local clashes = {} -- { a, b (keys), t (0 = clash point at a's hands, 1 = at b's), born, point }

local function meetPoint(root)
	return root.CFrame:PointToWorldSpace(Vector3.new(0, 1.1, -2.4)) -- where the two hand beams meet
end

local function stopBeam(key, force)
	local b = beams[key]
	if not b or (b.clash and not force) then return end -- a clash only ends when someone wins
	beams[key] = nil
	if b.character.Parent then b.character:SetAttribute("PowerBeam", nil) end
end

-- npc = the bot's controller (its mashRate is how fast it mashes in a clash)
local function startBeam(key, check, aim, npc)
	if beams[key] then return end
	local character, _, P = check()
	if not character then return end
	if validAim(aim) then character:SetAttribute("PowerAim", aim) end
	character:SetAttribute("PowerElement", elementName(P))
	character:SetAttribute("PowerBeam", true)
	beams[key] = { character = character, check = check, P = P, npc = npc, last = 0, total = {}, ticks = 0,
		exposure = {}, seen = {}, burnAt = {} }
end

local function beamHit(b, P, model, hum, now, dir)
	local amount = P.BeamDamage * (b.npc and b.npc.damageScale or 1)
	hum:TakeDamage(amount)
	model:SetAttribute("LastHit", now)
	-- show the damage every few ticks, added up, so the numbers stay readable
	b.total[model] = (b.total[model] or 0) + amount
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
	elseif P.BeamStatus == "push" or P.BeamStatus == "soak" then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if tRoot and not tRoot.Anchored and not model:GetAttribute("FrozenSpeed") and flat.Magnitude > 0.1 then
			tRoot.AssemblyLinearVelocity = flat.Unit * (P.BeamStatus == "soak" and 34 or 28) + Vector3.new(0, 6, 0)
		end
		if P.BeamStatus == "soak" and now - (b.burnAt[model] or 0) > 1 then
			b.burnAt[model] = now -- (same once-a-second timer as burning)
			Status.slow(P, model, hum, P.SlowTime or 3)
		end
	end
	b.seen[model] = now
end

----------------------------------------------------------------------------------------
-- clashes: two beams pointed at each other lock together. Every F press pushes the clash point
-- toward the other one; when it reaches someone they lose: a big hit + the winner's element's
-- effect + their own element's effect backfiring
----------------------------------------------------------------------------------------

-- shortest distance between the segments p1-q1 and p2-q2
local function segmentGap(p1, q1, p2, q2)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, u
	if a <= 1e-6 and e <= 1e-6 then return r.Magnitude end
	if a <= 1e-6 then
		s, u = 0, math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= 1e-6 then
			s, u = math.clamp(-c / a, 0, 1), 0
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			s = denom ~= 0 and math.clamp((b * f - c * e) / denom, 0, 1) or 0
			u = (b * s + f) / e
			if u < 0 then
				s, u = math.clamp(-c / a, 0, 1), 0
			elseif u > 1 then
				s, u = math.clamp((b - c) / a, 0, 1), 1
			end
		end
	end
	return ((p1 + d1 * s) - (p2 + d2 * u)).Magnitude
end

-- the line a beam covers (from the hands toward the aim, as far as it reaches)
local function beamLine(b)
	local character, root, P = b.check()
	local aim = character and character:GetAttribute("PowerAim")
	if not root or typeof(aim) ~= "Vector3" then return nil end
	local from = meetPoint(root)
	local dir = aim - from
	if dir.Magnitude < 0.5 then return nil end
	return from, from + dir.Unit * P.BeamRange, dir.Unit
end

local function nameOf(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then return player.DisplayName end
	local hum = character:FindFirstChildOfClass("Humanoid")
	return hum and hum.DisplayName or character.Name
end

-- can't walk away from a clash
local function lockMovement(character, on)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if on and character:GetAttribute("ClashSpeed") == nil then
		character:SetAttribute("ClashSpeed", hum.WalkSpeed)
		hum.WalkSpeed = 0
	elseif not on and character:GetAttribute("ClashSpeed") ~= nil then
		hum.WalkSpeed = character:GetAttribute("ClashSpeed")
		character:SetAttribute("ClashSpeed", nil)
	end
end

local function startClash(ka, kb)
	local A, B = beams[ka], beams[kb]
	local c = { a = ka, b = kb, t = 0.5, born = os.clock() }
	A.clash, B.clash = c, c
	table.insert(clashes, c)
	for _, pair in ipairs({ { A, B }, { B, A } }) do
		local me, other = pair[1], pair[2]
		me.character:SetAttribute("Clash", true)
		me.character:SetAttribute("ClashWith", nameOf(other.character))
		me.character:SetAttribute("ClashElement", elementName(other.P))
		lockMovement(me.character, true)
	end
	local _, rootA = A.check()
	if rootA then playSound(rootA, A.P.Sounds.Final, 0.8, 0.7) end
end

local function endClash(c, winner)
	local i = table.find(clashes, c)
	if i then table.remove(clashes, i) end
	local A, B = beams[c.a], beams[c.b]
	for _, s in ipairs({ A, B }) do
		if s and s.clash == c then
			s.clash = nil
			for _, name in ipairs({ "Clash", "ClashT", "ClashPoint", "ClashWith", "ClashElement" }) do
				s.character:SetAttribute(name, nil)
			end
			lockMovement(s.character, false)
		end
	end
	local point = c.point
	if winner and A and B then
		local W, Lo = winner == c.a and A or B, winner == c.a and B or A
		local lm = Lo.character
		local hum = lm:FindFirstChildOfClass("Humanoid")
		local lRoot = lm:FindFirstChild("HumanoidRootPart")
		local wRoot = W.character:FindFirstChild("HumanoidRootPart")
		if hum and lRoot and hum.Health > 0 then
			local from = wRoot and wRoot.Position or lRoot.Position
			damage(W.P, lm, hum, Powers.ClashDamage, true, nil)
			applyStatus(W.P, lm, hum, W.P.Effect, from)
			-- their own power backfires on them too
			if Lo.P ~= W.P then applyStatus(Lo.P, lm, hum, Lo.P.Effect, from) end
			flash(W.P, lRoot.Position, 2, 10, 0.3)
			groundRing(W.P, lRoot.Position, 14, W.character)
			sparks(W.P, fxSpot(lRoot.Position, 1.5), 50, 30, 0.6)
			playSound(lRoot, W.P.Sounds.Final, 1)
		end
	elseif point then
		-- nobody won: the clash point blows up and throws both back
		for _, s in ipairs({ A, B }) do
			if s then Status.blast(s.character, point, 50) end
		end
		local P = (A and A.P) or (B and B.P)
		if P then flash(P, point, 2, 12, 0.3) end
	end
	stopBeam(c.a, true)
	stopBeam(c.b, true)
end

-- a press from a player: push their side
local lastMash = {}
local function mash(key)
	local b = beams[key]
	local c = b and b.clash
	if not c then return end
	local now = os.clock()
	if now - (lastMash[key] or 0) < 0.035 then return end -- (no faster than a human can press)
	lastMash[key] = now
	c.t += (c.a == key and 1 or -1) * Powers.ClashPush
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	-- beams whose caster can't use it anymore
	for key, b in pairs(beams) do
		local character, _, P = b.check()
		if character ~= b.character or P ~= b.P then
			if b.clash then
				endClash(b.clash, b.clash.a == key and b.clash.b or b.clash.a) -- the other one wins
			else
				stopBeam(key, true)
			end
		end
	end

	-- new clashes: two beams pointing at each other whose lines meet
	local free = {}
	for key, b in pairs(beams) do
		if not b.clash then table.insert(free, key) end
	end
	for i = 1, #free do
		for j = i + 1, #free do
			local A, B = beams[free[i]], beams[free[j]]
			if A and B and not A.clash and not B.clash then
				local a0, a1, da = beamLine(A)
				local b0, b1, db = beamLine(B)
				if a0 and b0 and da:Dot(db) < -0.4 and segmentGap(a0, a1, b0, b1) < 2.5 then startClash(free[i], free[j]) end
			end
		end
	end

	-- running clashes: bots mash at their own speed, the clash point slides
	for i = #clashes, 1, -1 do
		local c = clashes[i]
		local A, B = beams[c.a], beams[c.b]
		local rootA, rootB
		if A then _, rootA = A.check() end
		if B then _, rootB = B.check() end
		if not rootA or not rootB then
			endClash(c, rootA and c.a or (rootB and c.b) or nil)
		else
			local rateA = A.npc and A.npc.mashRate or 0
			local rateB = B.npc and B.npc.mashRate or 0
			c.t += (rateA - rateB) * dt * Powers.ClashPush
			c.point = meetPoint(rootA):Lerp(meetPoint(rootB), c.t)
			for _, s in ipairs({ { A, c.t }, { B, 1 - c.t } }) do
				s[1].character:SetAttribute("PowerAim", c.point)
				s[1].character:SetAttribute("ClashPoint", c.point)
				s[1].character:SetAttribute("ClashT", s[2]) -- 1 = you win
			end
			-- bots turn to face each other (players' own clients turn them)
			for _, pair in ipairs({ { A, rootA, rootB }, { B, rootB, rootA } }) do
				if pair[1].npc then
					local r, other = pair[2], pair[3].Position
					r.CFrame = CFrame.lookAt(r.Position, Vector3.new(other.X, r.Position.Y, other.Z))
				end
			end
			if c.t >= 0.95 then
				endClash(c, c.a)
			elseif c.t <= 0.05 then
				endClash(c, c.b)
			elseif now - c.born > Powers.ClashMaxTime then
				endClash(c, nil)
			end
		end
	end

	-- damage ticks (not while clashing: the beams are pushing against each other)
	for _, b in pairs(beams) do
		local character, root, P = b.check()
		if character and not b.clash and now - b.last >= P.BeamTick then
			b.last = now
			b.ticks += 1
			local aim = character:GetAttribute("PowerAim")
			if typeof(aim) == "Vector3" then
				local origin = meetPoint(root)
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
		if b and not b.clash and validAim(value) then b.character:SetAttribute("PowerAim", value) end
	elseif action == "mash" then
		mash(player)
	end
end)

----------------------------------------------------------------------------------------
-- NPC casters: the demo bots, duels (NPC vs NPC) and opponents to fight
----------------------------------------------------------------------------------------

-- opts: display, health (nil = can't die), hittable (players' powers hurt it), owner, kind
local function makeCaster(element, pos, lookAt, name, opts)
	local bot = Bots.make(element, pos, name, lookAt)
	CollectionService:AddTag(bot, "AnimatedNPC") -- clients animate its arms like a player's
	if opts.hittable then CollectionService:RemoveTag(bot, "SpinjitzuNPC") end
	local hum = bot:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth = opts.health or math.huge
	hum.Health = hum.MaxHealth
	hum.DisplayName = opts.display or (element .. " Power Bot")
	if opts.health then hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn end
	if opts.owner then
		bot:SetAttribute("PowerNPCOwner", opts.owner)
		bot:SetAttribute("PowerNPCKind", opts.kind)
		CollectionService:AddTag(bot, "PowerNPC")
	end
	local root = bot:WaitForChild("HumanoidRootPart")
	local P = Powers.ByElement[element]
	local caster = { bot = bot, root = root, P = P, hum = hum, mashRate = opts.mashRate or 6 }
	caster.check = function()
		if bot.Parent and root.Parent and hum.Health > 0 then return bot, root, P end
		return nil
	end
	return caster
end

local function faceTo(caster, pos)
	local r = caster.root
	local flat = Vector3.new(pos.X, r.Position.Y, pos.Z)
	if (flat - r.Position).Magnitude > 0.5 then r.CFrame = CFrame.lookAt(r.Position, flat) end
end

-- throw the whole combo at whatever aim() says
local function comboAt(caster, aim)
	for i, ball in ipairs(caster.P.Balls) do
		if not caster.check() then return end
		throw(caster.bot, caster.check, aim(), caster)
		task.wait(ball.time + (i == #caster.P.Balls and 0 or 0.3))
	end
end

local function removeNpcs(player, kind)
	for _, bot in ipairs(CollectionService:GetTagged("PowerNPC")) do
		if bot:GetAttribute("PowerNPCOwner") == player.UserId and (not kind or bot:GetAttribute("PowerNPCKind") == kind) then
			local b = beams[bot]
			if b and b.clash then endClash(b.clash, nil) end
			stopBeam(bot, true)
			bot:Destroy()
		end
	end
end

local function inFront(player, distance)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	return root.Position + look * distance, look, root
end

-- two NPCs beam each other and clash; winner = "a", "b" or "random". Repeats until removed.
local function spawnDuel(player, a, b, winner)
	removeNpcs(player, "duel")
	local center, look = inFront(player, 24)
	if not center then return end
	local right = look:Cross(Vector3.yAxis)
	local posA, posB = center - right * 16, center + right * 16
	local A = makeCaster(a, posA, posB, "Duel_" .. a, { owner = player.UserId, kind = "duel", display = a .. " (duel)" })
	local B = makeCaster(b, posB, posA, "Duel_" .. b, { owner = player.UserId, kind = "duel", display = b .. " (duel)" })
	task.spawn(function()
		task.wait(1)
		while A.bot.Parent and B.bot.Parent do
			-- how fast each side mashes: the winner clearly faster, random = about even, changing
			if winner == "a" then
				A.mashRate, B.mashRate = 9, 6
			elseif winner == "b" then
				A.mashRate, B.mashRate = 6, 9
			end
			startBeam(A.bot, A.check, B.root.Position + Vector3.new(0, 1, 0), A)
			startBeam(B.bot, B.check, A.root.Position + Vector3.new(0, 1, 0), B)
			local stop = os.clock() + Powers.ClashMaxTime + 5
			while (beams[A.bot] or beams[B.bot]) and os.clock() < stop and A.bot.Parent and B.bot.Parent do
				if winner == "random" then
					A.mashRate, B.mashRate = 7.5 + math.random() * 6 - 3, 7.5 + math.random() * 6 - 3
				end
				task.wait(0.4)
			end
			stopBeam(A.bot, true)
			stopBeam(B.bot, true)
			task.wait(4)
			for _, c in ipairs({ A, B }) do
				if c.bot.Parent then c.hum.Health = c.hum.MaxHealth end
			end
		end
	end)
end

-- an NPC that fights you: shots and beams at you; beam it back to clash
local function spawnFight(player, element)
	removeNpcs(player, "fight")
	local pos, _, root = inFront(player, 30)
	if not pos then return end
	local F = Powers.FightNPC
	local C = makeCaster(element, pos, root.Position, "Fight_" .. element, {
		owner = player.UserId, kind = "fight", display = element .. " ninja", health = F.Health, hittable = true, mashRate = F.MashRate,
	})
	C.damageScale = F.DamageScale
	local function pause() return F.Pause[1] + math.random() * (F.Pause[2] - F.Pause[1]) end
	C.hum.Died:Connect(function()
		task.wait(3)
		if C.bot.Parent then C.bot:Destroy() end
	end)
	task.spawn(function()
		local nextMove, beamUntil = os.clock() + 2, 0
		while C.check() do
			local character = player.Character
			local target = character and character:FindFirstChild("HumanoidRootPart")
			if target then
				local aimAt = function() return target.Position + Vector3.new(0, 1, 0) end
				local b = beams[C.bot]
				if not (b and b.clash) then faceTo(C, target.Position) end
				local theirAim = character:GetAttribute("PowerAim")
				local beamingAtMe = character:GetAttribute("PowerBeam") and typeof(theirAim) == "Vector3"
					and (theirAim - C.root.Position).Magnitude < 8
				if b then
					if not b.clash then
						C.bot:SetAttribute("PowerAim", aimAt())
						if os.clock() > beamUntil then
							stopBeam(C.bot)
							nextMove = os.clock() + pause()
						end
					end
				elseif beamingAtMe then
					-- you're beaming at it: it beams right back (that's a clash)
					startBeam(C.bot, C.check, aimAt(), C)
					beamUntil = os.clock() + 3
				elseif os.clock() >= nextMove then
					if math.random() < 0.5 then
						task.spawn(comboAt, C, aimAt)
						nextMove = os.clock() + 2 + pause()
					else
						startBeam(C.bot, C.check, aimAt(), C)
						beamUntil = os.clock() + F.BeamTime
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

-- the menu's Duels page
local menu = ReplicatedStorage:WaitForChild("NinjaMenu", 10)
if menu then
	menu.OnServerEvent:Connect(function(player, action, value)
		if typeof(value) ~= "string" then return end
		if action == "duel" then
			local a, b, winner = value:match("^(%a+)|(%a+)|(%a+)$")
			if Powers.ByElement[a or ""] and Powers.ByElement[b or ""] and (winner == "a" or winner == "b" or winner == "random") then
				spawnDuel(player, a, b, winner)
			end
		elseif action == "fight" then
			if Powers.ByElement[value] then spawnFight(player, value) end
		elseif action == "bots" and value == "remove" then
			removeNpcs(player)
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local b = beams[player]
	if b and b.clash then endClash(b.clash, b.clash.a == player and b.clash.b or b.clash.a) end
	beams[player] = nil
	combos[player] = nil
	removeNpcs(player)
end)

----------------------------------------------------------------------------------------
-- demo bots: one per element, 50 studs behind its Spinjitzu bot, each with an infinite dummy
-- to aim at: the combo, 3 seconds of beam, on repeat
----------------------------------------------------------------------------------------

if Powers.DemoBot then
	for i, element in ipairs(Config.TestBotElements or {}) do
		if Powers.ByElement[element] then
			task.spawn(function()
				local spinBot = workspace:WaitForChild("SpinjitzuBot_" .. element, 15)
				local base = spinBot and spinBot:GetPivot().Position or Vector3.new((i - 3.5) * 16, 0, 20)
				local spot = Vector3.new(base.X, 0, base.Z + 50)
				local target = spot + Vector3.new(0, 0, 22)
				local dummy = TrainingDummy.spawn(target, spot, { infinite = true })
				local C = makeCaster(element, spot, target, "PowerBot_" .. element, {})
				local function aim()
					local dRoot = dummy and dummy.Parent and dummy:FindFirstChild("HumanoidRootPart")
					return dRoot and dRoot.Position or target + Vector3.new(0, 3, 0)
				end
				task.wait(3 + i * 0.4)
				while C.bot.Parent do
					comboAt(C, aim)
					task.wait(0.5)
					startBeam(C.bot, C.check, aim(), C)
					task.wait(3)
					stopBeam(C.bot)
					while beams[C.bot] do task.wait(0.2) end -- (still clashing with someone)
					if C.bot.Parent then faceTo(C, target) end
					task.wait(1.5)
				end
			end)
		end
	end
end
