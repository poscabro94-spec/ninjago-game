-- ElementPowersClient v2.0  (LocalScript in StarterPlayerScripts)
-- Your elemental power button (empty hands; Lightning, Fire, Ice or Earth): tap left click =
-- the shot combo, hold left click = beam. Turns you toward where you aim. Draws the effects for
-- everyone (colours + style from the element's BeamStyle in ElementPowers):
--   beam: a beam from each hand meets in a glowing orb in front of you, one big beam goes on
--         from there (grows out over a split second): crackling arcs (Lightning), a stream of
--         flames / frost / sand (the others), sparks + light where it hits
--   shots: crackling arcs + an aura around lightning balls, sparks in the hands while winding up

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Powers = require(ReplicatedStorage:WaitForChild("ElementPowers"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local remote = ReplicatedStorage:WaitForChild("ElementPower")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local rng = Random.new()

local fxFolder = Instance.new("Folder")
fxFolder.Name = "PowerFx"
fxFolder.Parent = workspace
mouse.TargetFilter = fxFolder -- aim through the effects themselves

-- power settings of a character (whatever it used last)
local function powerOf(character)
	return Powers.ByElement[character:GetAttribute("PowerElement") or ""] or Powers.Lightning
end

local function canUse()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or character:FindFirstChildOfClass("Tool") then return false end
	if character:GetAttribute("SpinjitzuActive") or character:GetAttribute("DragonPhase") or character:GetAttribute("CreationPhase") then
		return false
	end
	return Powers.ByElement[player:GetAttribute("SpinjitzuElement") or Config.Element] ~= nil
end

-- turn to face the aim (only sideways), so the shot / beam goes where you point
local function face(aim)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local flat = Vector3.new(aim.X, root.Position.Y, aim.Z)
	if (flat - root.Position).Magnitude > 1 then root.CFrame = CFrame.lookAt(root.Position, flat) end
end

----------------------------------------------------------------------------------------
-- input: tap = shot, hold = beam
----------------------------------------------------------------------------------------

local pressedAt -- os.clock() while left click is down
local beaming = false
local hadAutoRotate

-- while beaming you face the aim, so Roblox mustn't turn you toward where you walk
local function setAutoRotate(on)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if not on then
		hadAutoRotate = hum.AutoRotate
		hum.AutoRotate = false
	elseif hadAutoRotate ~= nil then
		hum.AutoRotate = hadAutoRotate
		hadAutoRotate = nil
	end
end

local function stopBeam()
	if beaming then
		beaming = false
		Powers.LocalAim = nil
		setAutoRotate(true)
		remote:FireServer("beam", false)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if canUse() then pressedAt = os.clock() end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if beaming then
		stopBeam()
	elseif pressedAt and canUse() then
		face(mouse.Hit.Position)
		remote:FireServer("ball", mouse.Hit.Position)
	end
	pressedAt = nil
end)

local sendT = 0
RunService.RenderStepped:Connect(function(dt)
	if pressedAt and not beaming and os.clock() - pressedAt >= Powers.HoldTime then
		if canUse() then
			beaming = true
			setAutoRotate(false)
			face(mouse.Hit.Position)
			remote:FireServer("beam", mouse.Hit.Position)
		else
			pressedAt = nil
		end
	end
	if not beaming then return end
	if not canUse() then
		stopBeam()
		pressedAt = nil
		return
	end
	Powers.LocalAim = mouse.Hit.Position
	face(Powers.LocalAim)
	sendT -= dt
	if sendT <= 0 then
		sendT = 1 / 15
		remote:FireServer("aim", mouse.Hit.Position)
	end
end)

----------------------------------------------------------------------------------------
-- building blocks
----------------------------------------------------------------------------------------

local function anchorPart(name, size, visible)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = visible and 0 or 1
	p.Parent = fxFolder
	return p
end

local function glowBall(name, size, color, transparency)
	local p = anchorPart(name, Vector3.one * size, true)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	return p
end

local function attach(part)
	local a = Instance.new("Attachment")
	a.Parent = part
	return a
end

local function beam(a0, a1, width, color, transparency, segments)
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Width0, b.Width1 = width, width
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(transparency)
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = 3
	b.FaceCamera = true
	b.Segments = segments or 2
	b.Parent = a0.Parent
	return b
end

local function sparks(parent, P, rate, speed, size)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(P.Color, P.CoreColor)
	pe.LightEmission = P.Shot == "rock" and 0 or 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.25), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.1, 0.3)
	pe.Speed = NumberRange.new(speed * 0.4, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 3
	pe.Rate = rate
	pe.Parent = parent
	return pe
end

local function light(parent, P, brightness, range)
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range = P.Color, brightness, range
	l.Parent = parent
	return l
end

local function sound(parent, id, pitch, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = pitch
	s.Volume = volume
	s.RollOffMaxDistance = 90
	s.Parent = parent
	return s
end

-- a crackling arc between two parts that point at each other (aimPart): each arc has its own
-- attachments, turned randomly around the line on every rebend(), so arcs bend every which way
local function arc(fromPart, toPart, width, color)
	local s, e = attach(fromPart), attach(toPart)
	return { s = s, e = e, b = beam(s, e, width, color, 0.1, 12) }
end
local function rebend(a, len)
	local bend = math.min(len * 0.18, 2.5)
	a.s.CFrame = CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
	a.e.CFrame = CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
	a.b.CurveSize0 = rng:NextNumber(-bend, bend)
	a.b.CurveSize1 = rng:NextNumber(-bend, bend)
	a.b.Transparency = NumberSequence.new(rng:NextNumber() < 0.25 and 1 or rng:NextNumber(0, 0.35))
end
local function aimPart(part, from, to)
	if (to - from).Magnitude < 1e-3 then to = from + Vector3.new(0, 0, -0.01) end
	part.CFrame = CFrame.lookAt(from, to)
end

----------------------------------------------------------------------------------------
-- the beam (every character with PowerBeam on)
----------------------------------------------------------------------------------------

local function makeBeam(P)
	local style = P.BeamStyle
	local d = { P = P, started = os.clock(), crackle = 0, arcs = {}, sounds = {} }
	-- hands -> where the two beams meet
	d.palmR, d.endR = anchorPart("PalmR"), anchorPart("EndR")
	d.palmL, d.endL = anchorPart("PalmL"), anchorPart("EndL")
	-- the orb where they meet, and the end of the big beam
	d.orb = glowBall("Orb", 0.9, style.core, 0.05)
	d.aura = glowBall("OrbAura", 2, style.glow, 0.65)
	d.mid = anchorPart("Mid")
	d.tip = anchorPart("Tip")
	local aPR, aER, aPL, aEL = attach(d.palmR), attach(d.endR), attach(d.palmL), attach(d.endL)
	local aM, aT = attach(d.mid), attach(d.tip) -- (the beams' own, straight attachments)

	beam(aPR, aER, 0.55, style.glow, 0.5)
	beam(aPR, aER, 0.16, style.core, 0)
	beam(aPL, aEL, 0.55, style.glow, 0.5)
	beam(aPL, aEL, 0.16, style.core, 0)
	d.haze = beam(aM, aT, 3, style.haze, 0.85)
	d.glow = beam(aM, aT, 1.4, style.glow, 0.45)
	d.core = beam(aM, aT, 0.42, style.core, 0)
	if style.arcs then
		for _ = 1, 4 do
			local a = arc(d.mid, d.tip, 0.08, style.core)
			a.main = true
			table.insert(d.arcs, a)
		end
		table.insert(d.arcs, arc(d.palmR, d.endR, 0.06, style.core))
		table.insert(d.arcs, arc(d.palmL, d.endL, 0.06, style.core))
	end
	-- flames / frost / sand pouring out along the beam (the mid part faces the target, Front = -Z)
	if style.stream then
		local s = style.stream
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = s.texture
		pe.Color = ColorSequence.new(s.from, s.to)
		pe.LightEmission = P.Shot == "rock" and 0 or 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s.size * 0.4), NumberSequenceKeypoint.new(1, s.size) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(0.25, 0.45)
		pe.Speed = NumberRange.new(s.speed * 0.8, s.speed)
		pe.SpreadAngle = Vector2.new(6, 6)
		pe.RotSpeed = NumberRange.new(-120, 120)
		pe.Rotation = NumberRange.new(0, 360)
		pe.EmissionDirection = Enum.NormalId.Front
		pe.Rate = 0
		pe.Parent = d.mid
		d.stream = pe
	end

	light(d.orb, P, 4, 12)
	sparks(d.palmR, P, 30, 6, 0.18)
	sparks(d.palmL, P, 30, 6, 0.18)
	d.hitSparks = sparks(d.tip, P, 90, 22, 0.35)
	d.hitLight = light(d.tip, P, 5, 14)
	d.flash = glowBall("HitFlash", 1.2, style.core, 0.3)

	-- sound: lightning crackles (or loops a hum if one is set); the others whoosh as they start
	if style.crackle and P.Sounds.Zap then
		sound(d.orb, P.Sounds.Zap, 0.6, 0.7):Play()
		if P.Sounds.BeamLoop and P.Sounds.BeamLoop ~= "" then
			local loop = sound(d.orb, P.Sounds.BeamLoop, 1, 0.6)
			loop.Looped = true
			loop:Play()
		else
			for i = 1, 3 do d.sounds[i] = sound(i == 1 and d.orb or d.tip, P.Sounds.Zap, 1, 0.35) end
		end
	else
		sound(d.orb, P.Sounds.Throw, 0.6, 0.7):Play()
	end
	return d
end

local function dropBeam(character, d)
	for _, part in ipairs({ d.palmR, d.endR, d.palmL, d.endL, d.orb, d.aura, d.mid, d.tip, d.flash }) do part:Destroy() end
	if character == player.Character then
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then hum.CameraOffset = Vector3.zero end
	end
end

-- players' characters + bots that use powers (the demo bot)
local function casters()
	local list = CollectionService:GetTagged("AnimatedNPC")
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

local drawn = {} -- [character] = beam
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function palm(hand)
	return hand.Position - hand.CFrame.UpVector * 0.3
end

local function updateBeams(dt, rebendNow)
	local now = os.clock()
	for _, character in ipairs(casters()) do
		local mine = character == player.Character
		local on = character:GetAttribute("PowerBeam")
		local handR = character:FindFirstChild("RightHand")
		local handL = character:FindFirstChild("LeftHand")
		local root = character:FindFirstChild("HumanoidRootPart")
		local aim = character:GetAttribute("PowerAim")
		if mine and beaming then aim = mouse.Hit.Position end -- your own: no delay
		if on and handR and handL and root and typeof(aim) == "Vector3" then
			local P = powerOf(character)
			local d = drawn[character]
			if d and d.P ~= P then -- switched element mid-beam
				dropBeam(character, d)
				d = nil
			end
			if not d then
				d = makeBeam(P)
				drawn[character] = d
			end
			local pR, pL = palm(handR), palm(handL)
			local dir = aim - (pR + pL) / 2
			dir = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector
			local meet = (pR + pL) / 2 + dir * 1.3
			rayParams.FilterDescendantsInstances = { character, fxFolder }
			local hit = workspace:Raycast(meet, dir * P.BeamRange, rayParams)
			local stop = hit and hit.Position or meet + dir * P.BeamRange

			-- grow: the hand beams reach the middle first, then the big beam shoots out
			local age = now - d.started
			local f = math.clamp(age / 0.15, 0, 1)
			local g = math.clamp((age - 0.12) / 0.14, 0, 1)
			local endR, endL = pR:Lerp(meet, f), pL:Lerp(meet, f)
			local tip = meet:Lerp(stop, g)
			aimPart(d.palmR, pR, endR)
			aimPart(d.endR, endR, pR)
			aimPart(d.palmL, pL, endL)
			aimPart(d.endL, endL, pL)
			aimPart(d.mid, meet, tip)
			aimPart(d.tip, tip, meet)

			-- flicker
			local pulse = 0.85 + rng:NextNumber() * 0.35
			local grown = f >= 1
			d.orb.Size = Vector3.one * (grown and 0.9 * pulse or 0.01)
			d.aura.Size = Vector3.one * (grown and 2.1 * pulse or 0.01)
			d.orb.CFrame, d.aura.CFrame = CFrame.new(meet), CFrame.new(meet)
			d.core.Width0, d.core.Width1 = 0.5 * pulse, 0.36 * pulse
			d.glow.Width0, d.glow.Width1 = 1.6 * pulse, 1.2 * pulse
			d.haze.Width0, d.haze.Width1 = 3.2 * pulse, 2.4 * pulse
			for _, b in ipairs({ d.core, d.glow, d.haze }) do b.Enabled = g > 0 end
			if d.stream then
				-- particles fly as far as the beam reaches
				local len = (tip - meet).Magnitude
				d.stream.Rate = g > 0 and 120 or 0
				local life = math.clamp(len / P.BeamStyle.stream.speed, 0.05, 1.2)
				d.stream.Lifetime = NumberRange.new(life * 0.8, life)
			end
			local landed = hit ~= nil and g >= 1
			d.hitSparks.Enabled = landed
			d.hitLight.Brightness = landed and (4 + rng:NextNumber() * 3) or 0
			d.flash.Size = Vector3.one * (landed and rng:NextNumber(1, 1.8) or 0.01)
			d.flash.CFrame = CFrame.new(tip)
			if rebendNow then
				for _, a in ipairs(d.arcs) do
					rebend(a, a.main and (tip - meet).Magnitude or (meet - pR).Magnitude)
					a.b.Enabled = not a.main or g > 0
				end
			end

			-- crackle
			if #d.sounds > 0 then
				d.crackle -= dt
				if d.crackle <= 0 then
					d.crackle = rng:NextNumber(0.07, 0.14)
					local s = d.sounds[rng:NextInteger(1, #d.sounds)]
					s.PlaybackSpeed = rng:NextNumber(0.9, 1.5)
					s:Play()
				end
			end
			-- your own beam shakes the camera a little
			if mine then
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum then hum.CameraOffset = Vector3.new(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.06, 0.06), 0) end
			end
		end
	end
	for character, d in pairs(drawn) do
		if not character.Parent or not character:GetAttribute("PowerBeam") then
			dropBeam(character, d)
			drawn[character] = nil
		end
	end
end

----------------------------------------------------------------------------------------
-- shots: arcs + aura around lightning balls, sparks in the hands while winding up
----------------------------------------------------------------------------------------

local balls = {} -- [ball part] = { center, points, arcs }

local function decorate(ball)
	local P = Powers.Lightning
	local r = ball.Size.X / 2
	local d = { center = attach(ball), points = {}, arcs = {}, r = r }
	local aura = Instance.new("Part")
	aura.Shape = Enum.PartType.Ball
	aura.Material = Enum.Material.Neon
	aura.Color = P.Color
	aura.Transparency = 0.7
	aura.Size = ball.Size * 1.8
	aura.CanCollide, aura.CanQuery, aura.CanTouch, aura.CastShadow, aura.Massless = false, false, false, false, true
	aura.CFrame = ball.CFrame
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = ball, aura
	w.Parent = aura
	aura.Parent = ball
	for i = 1, 4 do
		d.points[i] = attach(ball)
		d.arcs[i] = beam(d.center, d.points[i], 0.06 + r * 0.04, P.CoreColor, 0.1, 10)
	end
	balls[ball] = d
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "LightningBall" and child:IsA("BasePart") then decorate(child) end
end)

local function updateBalls(rebendNow)
	for ball, d in pairs(balls) do
		if not ball.Parent then
			balls[ball] = nil
		elseif rebendNow then
			for i, p in ipairs(d.points) do
				local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
				dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.yAxis
				p.CFrame = CFrame.lookAt(dir * d.r * rng:NextNumber(1.6, 2.6), Vector3.zero)
				local b = d.arcs[i]
				b.CurveSize0, b.CurveSize1 = rng:NextNumber(-d.r, d.r), rng:NextNumber(-d.r, d.r)
				b.Transparency = NumberSequence.new(rng:NextNumber() < 0.3 and 1 or rng:NextNumber(0, 0.3))
			end
		end
	end
end

-- sparks + light in the throwing hand(s) while winding up, a burst when it lets go
local lastPowerId = setmetatable({}, { __mode = "k" })
local function ballFor(P, name)
	for _, b in ipairs(P.Balls) do
		if b.name == name then return b end
	end
	return nil
end

local function windUp(character, P, ball)
	local both = ball.hands == "B"
	local hands = both and { "RightHand", "LeftHand" } or { ball.hands == "R" and "RightHand" or "LeftHand" }
	for _, name in ipairs(hands) do
		local hand = character:FindFirstChild(name)
		if hand then
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(0, -0.3, 0)
			a.Parent = hand
			local sp = sparks(a, P, both and 60 or 35, 5, both and 0.3 or 0.2)
			local l = light(a, P, 2, both and 10 or 6)
			task.delay(ball.time * ball.release, function()
				sp.Speed = NumberRange.new(10, 22)
				sp:Emit(both and 30 or 15)
				sp.Enabled = false
				l.Brightness = 6
				if P.Sounds.Zap then sound(a, P.Sounds.Zap, both and 0.8 or 1.35, both and 0.8 or 0.5):Play() end
				task.delay(0.08, function() l.Enabled = false end)
				task.delay(1, function() a:Destroy() end)
			end)
		end
	end
end

local function updateWindUps()
	for _, character in ipairs(casters()) do
		local id = character:GetAttribute("PowerId") or 0
		if lastPowerId[character] == nil then
			lastPowerId[character] = id
		elseif id ~= lastPowerId[character] then
			lastPowerId[character] = id
			local P = powerOf(character)
			local ball = ballFor(P, character:GetAttribute("PowerMove") or "")
			if ball then windUp(character, P, ball) end
		end
	end
end

local bendT = 0
RunService.RenderStepped:Connect(function(dt)
	bendT -= dt
	local rebendNow = bendT <= 0
	if rebendNow then bendT = 0.04 end
	updateBeams(dt, rebendNow)
	updateBalls(rebendNow)
	updateWindUps()
end)
