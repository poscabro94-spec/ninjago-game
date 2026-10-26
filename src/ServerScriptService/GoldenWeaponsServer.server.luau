-- GoldenWeaponsServer v7.3  (Script in ServerScriptService)
-- Gives every player the Golden Weapon of their element on spawn (slot 1) and swaps it when
-- they switch element: Lightning = Nunchucks of Lightning, Fire = Sword of Fire,
-- Earth = Scythe of Quakes, Ice = Shurikens of Ice. The menu can hand out several at once (player
-- attribute GoldenWeapons: "Sword,Scythe" / "None"). Your element's weapon (else the first) sits
-- on your back when not equipped.
-- Melee weapons: click = 4-hit combo; the server picks the swing, plays the sounds and does the
-- hit check (damage + knockback + hit flash in the weapon's colour). Scythe finisher = quake.
-- Shurikens: the client sends where you aim (ShurikenThrow), the server throws them, they
-- freeze whoever they hit. Also spawns a Training Dummy to fight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local HitEffects = require(script.Parent:WaitForChild("HitEffects"))
local TrainingDummy = require(script.Parent:WaitForChild("TrainingDummy"))
local Status = require(script.Parent:WaitForChild("StatusEffects"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local N = GoldenWeapons.Nunchucks
local S = GoldenWeapons.Sword
local SC = GoldenWeapons.Scythe
local K = GoldenWeapons.Shurikens
local TAU = math.pi * 2

local throwRemote = ReplicatedStorage:FindFirstChild("ShurikenThrow")
if not throwRemote then
	throwRemote = Instance.new("RemoteEvent")
	throwRemote.Name = "ShurikenThrow"
	throwRemote.Parent = ReplicatedStorage
end

----------------------------------------------------------------------------------------
-- mesh + stick building
----------------------------------------------------------------------------------------

local function findMesh(names)
	for _, name in ipairs(names) do
		for _, where in ipairs({ ReplicatedStorage, workspace, game:GetService("ServerStorage") }) do
			local obj = where:FindFirstChild(name, true)
			if obj then
				if obj:IsA("MeshPart") then return obj end
				local mp = obj:FindFirstChildWhichIsA("MeshPart", true)
				if mp then return mp end
			end
		end
	end
	return nil
end

-- R: part CFrame = stick CFrame * R   (stick space: long axis Y, chain end at -Y)
local function axisFor(size)
	local R
	if size.X >= size.Y and size.X >= size.Z then
		R = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, -Vector3.xAxis)
	elseif size.Z >= size.Y then
		R = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, -Vector3.zAxis)
	else
		R = CFrame.identity
	end
	if not N.HeadAtNegative then R = CFrame.Angles(math.pi, 0, 0) * R end
	return R
end

local function bare(p)
	p.Anchored = false
	p.Massless = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
end

local function makeStick(template, name)
	local p, scale = nil, 1
	if template then
		p = template:Clone()
		local s = p.Size
		scale = N.StickLength / math.max(s.X, s.Y, s.Z)
		p.Size = s * scale
		p.TextureID = ""
		for _, c in ipairs(p:GetChildren()) do c:Destroy() end
	else
		p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(N.StickLength, 0.42, 0.42)
	end
	p.Name = name
	bare(p)
	p.Color = N.Color
	p.Material = N.Material
	p.Reflectance = N.Reflectance
	if template then
		-- blue gem eyes + dots
		for i, gem in ipairs(N.Gems) do
			local g = Instance.new("Part")
			g.Name = "Gem" .. i
			g.Size = gem.size * scale
			if gem.disc then g.Shape = Enum.PartType.Cylinder end
			bare(g)
			g.CastShadow = false
			g.Color = N.GemColor
			g.Material = Enum.Material.SmoothPlastic
			g.Reflectance = 0.35
			g.CFrame = p.CFrame * CFrame.new(gem.pos * scale)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = p, g
			w.Parent = g
			g.Parent = p
		end
	end
	return p
end

local function att(parent, name, stickPos, R)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = R:Inverse() * CFrame.new(stickPos)
	a.Parent = parent
	return a
end

local function sound(parent, id, vol)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.6
	s.RollOffMaxDistance = 80
	s.Parent = parent
	return s
end

local function goldTrail(parent, a0, a1)
	local t = Instance.new("Trail")
	t.Name = "GoldTrail"
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.25
	t.LightEmission = 0.8
	t.Color = ColorSequence.new(N.TrailColor, N.TrailColor2)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.3) })
	t.FaceCamera = true
	t.Enabled = false
	t.Parent = parent
	return t
end

local function beam(parent, name, a0, a1, width, color, transp, segments)
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0, b.Attachment1 = a0, a1
	b.Segments = segments or 16
	b.Width0, b.Width1 = width, width
	b.Color = ColorSequence.new(color)
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = 2.5
	b.FaceCamera = true
	b.Transparency = NumberSequence.new(transp or 0)
	b.Parent = parent
	return b
end

----------------------------------------------------------------------------------------
-- hits
----------------------------------------------------------------------------------------

local hitFx = HitEffects.show

-- damage everyone (but you) within range of center, knocked away from `from`
local function hitArea(W, character, swing, center, range, from)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(center, range, params)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and not done[model] and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC") then
			done[model] = true
			local tRoot = model:FindFirstChild("HumanoidRootPart") or part
			hum:TakeDamage(swing.damage)
			model:SetAttribute("LastHit", os.clock())
			if not tRoot.Anchored then
				local away = tRoot.Position - from
				away = Vector3.new(away.X, 0, away.Z)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)
				tRoot.AssemblyLinearVelocity = away * swing.knock + Vector3.new(0, swing.up or 8, 0)
			end
			hitFx(W, tRoot, model, swing.damage, swing.final)
		end
	end
end

local function doHit(W, character, swing)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local center = swing.around and root.Position
		or (root.Position + root.CFrame.LookVector * (swing.reach or (swing.name == "twirl" and 1.5 or 3)))
	hitArea(W, character, swing, center, swing.range, root.Position)
end

-- invisible anchored spot for effects
local function fxAnchor(pos, life)
	local a = Instance.new("Part")
	a.Name = "WeaponFx"
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.new(0.2, 0.2, 0.2)
	a.CFrame = CFrame.new(pos)
	a.Parent = workspace
	Debris:AddItem(a, life)
	return a
end

-- ice bits flying apart
local function shatter(pos)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(K.IceColor, Color3.new(1, 1, 1))
	pe.LightEmission = 0.6
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.3, 0.6)
	pe.Speed = NumberRange.new(8, 16)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -30, 0)
	pe.Rate = 0
	pe.Parent = fxAnchor(pos, 1)
	pe:Emit(24)
end

-- frozen: can't move, ice grows up to the neck (StatusEffects). Hitting again restarts the time.
local function freeze(model, hum, seconds)
	Status.freeze({ Color = K.IceColor, CoreColor = Color3.new(1, 1, 1) }, model, hum, seconds)
end

-- Scythe of Quakes' slam: shockwave along the ground + rocks bursting out, hits everyone nearby
local function quake(character, swing)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local center = root.Position + root.CFrame.LookVector * (swing.reach or 5)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local down = workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), params)
	local ground = down and down.Position or (center - Vector3.new(0, 3, 0))
	hitArea(SC, character, swing, ground, SC.QuakeRadius, ground)

	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = SC.QuakeColor
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.25, 2, 2)
	ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.25, SC.QuakeRadius * 2, SC.QuakeRadius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)

	for i = 1, 12 do
		local a = i / 12 * TAU + math.random() * 0.4
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local s = 0.6 + math.random() * 0.9
		local rock = Instance.new("Part")
		rock.Name = "QuakeRock"
		rock.Size = Vector3.new(s, s * (0.7 + math.random() * 0.5), s)
		rock.Material = Enum.Material.Slate
		rock.Color = SC.RockColor
		rock.CanQuery, rock.CanTouch = false, false
		rock.CFrame = CFrame.new(ground + out * (1.5 + math.random() * 2) + Vector3.new(0, 0.6, 0))
			* CFrame.Angles(math.random() * TAU, math.random() * TAU, 0)
		rock.Parent = workspace
		rock.AssemblyLinearVelocity = out * (8 + math.random() * 10) + Vector3.new(0, 26 + math.random() * 16, 0)
		rock.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		Debris:AddItem(rock, 2.5)
	end

	local spot = fxAnchor(ground, 2)
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(SC.QuakeColor, SC.RockColor)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3.5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1)
	dust.Speed = NumberRange.new(8, 16)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Drag = 3
	dust.Rate = 0
	dust.Parent = spot
	dust:Emit(40)
	sound(spot, SC.Sounds.Final, 1):Play()
end

-- click = next hit of the combo (W = weapon settings)
local function hookCombo(tool, W, handle)
	tool:SetAttribute("Swing", 1)
	tool:SetAttribute("SwingId", 0)
	local swingSounds = {}
	for i, id in ipairs(W.Sounds.Swing) do swingSounds[i] = sound(handle, id, 0.5) end
	local combo = { step = 0, start = 0, len = 0 }

	tool.Activated:Connect(function()
		local character = tool.Parent
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local now = os.clock()
		if now - combo.start < combo.len * 0.8 then return end -- still mid-swing
		if now - (combo.start + combo.len) > W.ComboWindow then combo.step = 0 end
		combo.step = combo.step % #W.Swings + 1
		local swing = W.Swings[combo.step]
		combo.start, combo.len = now, swing.time
		tool:SetAttribute("Swing", combo.step)
		tool:SetAttribute("SwingId", (tool:GetAttribute("SwingId") or 0) + 1)

		local s = swingSounds[math.random(1, #swingSounds)]
		s.PlaybackSpeed = 0.9 + math.random() * 0.25
		s:Play()
		if swing.name == "spin" or swing.name == "spinSlash" then
			task.delay(swing.time * 0.35, function()
				s.PlaybackSpeed = 1.15
				s:Play()
			end)
		end
		task.delay(swing.time * swing.hitAt, function()
			if tool.Parent ~= character then return end
			if swing.quake then quake(character, swing) else doHit(W, character, swing) end
			local root = character:FindFirstChild("HumanoidRootPart")
			if swing.burst and root then
				fireBurst(swing.around and root.Position or root.Position + root.CFrame.LookVector * (swing.reach or 3))
			end
		end)
	end)
end

local function buildNunchucks(stickT)
	local tool = Instance.new("Tool")
	tool.Name = N.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click to swing (4-hit combo)"

	local half = N.StickLength / 2
	local handle = makeStick(stickT, "Handle")
	local R = axisFor(handle.Size)
	handle.Parent = tool
	local headTip = att(handle, "HeadTip", Vector3.new(0, -half, 0), R)
	local hTail = att(handle, "HTail", Vector3.new(0, half, 0), R)

	-- second stick: placed every frame by GoldenWeapons.Step (on every client)
	local stickB = makeStick(stickT, "StickB")
	stickB:SetAttribute("StickAxis", R)
	stickB.Parent = tool
	local chainEnd = att(stickB, "ChainEnd", Vector3.new(0, -half, 0), R)
	local tail = att(stickB, "Tail", Vector3.new(0, half, 0), R)
	local joint = Instance.new("Motor6D")
	joint.Name = "ChainJoint"
	joint.Part0, joint.Part1 = handle, stickB
	joint.Parent = stickB

	-- the chain: a glowing lightning arc between the dragon heads + crackling side arcs
	local a0 = att(handle, "BoltA0", Vector3.new(0, -half, 0), R)
	local a1 = att(stickB, "BoltA1", Vector3.new(0, -half, 0), R)
	beam(stickB, "BoltGlow", a0, a1, 0.16, N.BoltColor, 0.65, 20)
	beam(stickB, "BoltCore", a0, a1, 0.07, Color3.fromRGB(235, 250, 255), 0, 20)
	for i = 1, 2 do
		local j0 = att(handle, "Jit0_" .. i, Vector3.new(0, -half, 0), R)
		local j1 = att(stickB, "Jit1_" .. i, Vector3.new(0, -half, 0), R)
		beam(stickB, "BoltJit" .. i, j0, j1, 0.02, Color3.fromRGB(200, 240, 255), 0.4, 8)
	end
	for _, at in ipairs({ headTip, chainEnd }) do
		local glow = Instance.new("PointLight")
		glow.Color = N.BoltColor
		glow.Brightness = 1.6
		glow.Range = 6
		glow.Parent = at
		local fizz = Instance.new("ParticleEmitter")
		fizz.Name = "Fizz"
		fizz.Color = ColorSequence.new(N.BoltColor, Color3.new(1, 1, 1))
		fizz.LightEmission = 1
		fizz.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) })
		fizz.Lifetime = NumberRange.new(0.1, 0.25)
		fizz.Speed = NumberRange.new(2, 5)
		fizz.SpreadAngle = Vector2.new(180, 180)
		fizz.Rate = 12
		fizz.Parent = at
	end

	-- golden swing trails (Step turns them on during swings)
	goldTrail(stickB, chainEnd, tail)
	goldTrail(handle, headTip, hTail)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Rate = 0
	sparks.Color = ColorSequence.new(N.TrailColor, N.TrailColor2)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Parent = tail

	hookCombo(tool, N, handle)
	local hold = GoldenWeapons.HoldOffset(R)
	tool.Equipped:Connect(function()
		local character = tool.Parent
		local hand = character and character:FindFirstChild("RightHand")
		local ga = hand and hand:FindFirstChild("RightGripAttachment")
		if ga then tool.Grip = hold:Inverse() * ga.CFrame end
	end)

	return tool
end

-- R for an imported mesh: its longest side -> long, thinnest -> thin (weapon space);
-- the middle side follows from those two
local function fitAxes(size, long, thin)
	local dims = { size.X, size.Y, size.Z }
	local order = { 1, 2, 3 }
	table.sort(order, function(a, b) return dims[a] > dims[b] end)
	local img = {}
	img[order[1]], img[order[3]] = long, thin
	local mid = order[2]
	if mid == 1 then img[1] = img[2]:Cross(img[3])
	elseif mid == 2 then img[2] = img[3]:Cross(img[1]) end
	return CFrame.fromMatrix(Vector3.zero, img[1], img[2])
end

-- an imported weapon model (e.g. "SwordOfFire"): its biggest part is the weapon, any other parts
-- in it (like red eye dots you add in Studio) come along in their own colours. nil = not imported
local function findModel(name)
	for _, where in ipairs({ ReplicatedStorage, workspace, game:GetService("ServerStorage") }) do
		local obj = where:FindFirstChild(name, true)
		if obj then
			local parts = obj:IsA("BasePart") and { obj } or {}
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(parts, d) end
			end
			if #parts > 0 then
				table.sort(parts, function(a, b) return a.Size.Magnitude > b.Size.Magnitude end)
				return parts
			end
		end
	end
	return nil
end

-- copy of an imported model scaled so its longest side is `length`, recoloured gold
local function cloneModel(template, length, W)
	local src = template[1]
	local main = src:Clone()
	for _, c in ipairs(main:GetChildren()) do c:Destroy() end
	local sz = main.Size
	local k = length / math.max(sz.X, sz.Y, sz.Z)
	main.Size = sz * k
	if main:IsA("MeshPart") then main.TextureID = "" end
	main.Color, main.Material, main.Reflectance = W.Color, W.Material, W.Reflectance
	-- extra parts keep their place on it (scaled with it)
	for i = 2, #template do
		local x = template[i]:Clone()
		for _, d in ipairs(x:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
		end
		local off = src.CFrame:ToObjectSpace(template[i].CFrame)
		x.Size *= k
		bare(x)
		x.CFrame = main.CFrame * CFrame.new(off.Position * k) * off.Rotation
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = main, x
		w.Parent = x
		x.Parent = main
	end
	return main
end

-- placeholder piece welded onto main (main still at the origin)
local function piece(main, name, size, cf, W, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if shape then p.Shape = shape end
	bare(p)
	p.Color = color or W.Color
	p.Material = material or W.Material
	p.Reflectance = material and 0 or W.Reflectance
	p.CFrame = main.CFrame * cf
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = main, p
	w.Parent = p
	p.Parent = main
end

-- Sword / Scythe: the imported model or a placeholder. Returns the main part (everything else
-- welded to it), its axis R (part CFrame = weapon CFrame * R) and, in weapon space relative to
-- the part's centre: where the right hand holds it + the two ends of the swing trail
local function makeWeapon(W, template, name)
	local main, R, hiltEnd, trailA, trailB
	if template then
		main = cloneModel(template, W.Length, W)
		R = fitAxes(main.Size, W.FlipModel and -Vector3.yAxis or Vector3.yAxis, Vector3.xAxis)
		local half = W.Length / 2
		hiltEnd = -half
		if W == SC then
			trailA, trailB = Vector3.new(0, half, 0), Vector3.new(0, half - 0.3, W.Length * 0.35)
		else
			trailA, trailB = Vector3.new(0, -half + W.HiltLength, 0), Vector3.new(0, half, 0)
		end
	elseif W == SC then
		-- shaft block with a blade block sticking forward off the top (+ a hooked tip)
		local L, th, bl, bw = W.Length, W.ShaftThickness, W.BladeLength, W.BladeWidth
		main = Instance.new("Part")
		main.Size = Vector3.new(th, L, th)
		main.Color, main.Material, main.Reflectance = W.Color, W.Material, W.Reflectance
		R = CFrame.identity
		piece(main, "Blade", Vector3.new(W.BladeThickness, bw, bl), CFrame.new(0, L / 2 - bw / 2, bl / 2 + th / 2), W)
		piece(main, "Hook", Vector3.new(W.BladeThickness, bw * 0.8, bl * 0.35),
			CFrame.new(0, L / 2 - bw * 1.1, bl + th / 2 - bl * 0.12) * CFrame.Angles(-0.6, 0, 0), W)
		hiltEnd = -L / 2
		trailA, trailB = Vector3.new(0, L / 2, 0), Vector3.new(0, L / 2 - bw / 2, bl)
	else
		-- sword: blade + pointed tip + glowing core + guard + grip + pommel
		local bl, bw, bt, gl = W.BladeLength, W.BladeWidth, W.BladeThickness, W.GripLength
		main = Instance.new("Part")
		main.Size = Vector3.new(bt, bl, bw)
		main.Color, main.Material, main.Reflectance = W.Color, W.Material, W.Reflectance
		R = CFrame.identity
		local guardY = -bl / 2 - 0.11
		piece(main, "Point", Vector3.new(bt, bw * 0.71, bw * 0.71), CFrame.new(0, bl / 2, 0) * CFrame.Angles(math.pi / 4, 0, 0), W)
		piece(main, "Core", Vector3.new(bt + 0.02, bl * 0.85, 0.08), CFrame.new(0, -bl * 0.05, 0), W, W.CoreColor, Enum.Material.Neon)
		piece(main, "Guard", Vector3.new(0.26, 0.22, 1.1), CFrame.new(0, guardY, 0), W)
		piece(main, "Grip", Vector3.new(gl, 0.22, 0.22), CFrame.new(0, guardY - 0.11 - gl / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			W, W.GripColor, Enum.Material.Fabric, Enum.PartType.Cylinder)
		piece(main, "Pommel", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, guardY - 0.11 - gl - 0.1, 0), W, nil, nil, Enum.PartType.Ball)
		hiltEnd = guardY - 0.11 - gl - 0.25
		trailA, trailB = Vector3.new(0, -bl / 2, 0), Vector3.new(0, bl / 2 + bw * 0.35, 0)
	end
	if W.FlipEdge then R = CFrame.Angles(0, math.pi, 0) * R end
	main.Name = name
	bare(main)
	return main, R, hiltEnd + W.GripFromEnd, trailA, trailB
end

-- Sword / Scythe tool: the hand holds an invisible handle, the weapon hangs off it on a joint
-- that every client turns (GoldenWeapons.Step) so both hands can hold it
local function buildMelee(W, template)
	local tool = Instance.new("Tool")
	tool.Name = W.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click to swing (4-hit combo)"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	bare(handle)
	handle.Parent = tool
	local weapon, R, grip, trailA, trailB = makeWeapon(W, template, "Weapon")
	local C1 = (CFrame.new(0, -grip, 0) * R):Inverse()
	weapon.CFrame = handle.CFrame * GoldenWeapons.DefaultHold * C1:Inverse()
	weapon.Parent = tool
	local joint = Instance.new("Motor6D")
	joint.Name = "WeaponJoint"
	joint.Part0, joint.Part1 = handle, weapon
	joint.C0, joint.C1 = GoldenWeapons.DefaultHold, C1
	joint.Parent = weapon

	local a0 = att(weapon, "TrailA", trailA, R)
	local a1 = att(weapon, "TrailB", trailB, R)
	goldTrail(weapon, a0, a1).Color = ColorSequence.new(W.TrailColor, W.TrailColor2)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Rate = 0
	sparks.Color = ColorSequence.new(W.TrailColor, W.TrailColor2)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Parent = a1

	if W == S then
		-- flames along the blade: an invisible part covering it carries the emitter + light
		local base, tip = trailA.Y, trailB.Y
		local zone = Instance.new("Part")
		zone.Name = "FlameZone"
		zone.Size = Vector3.new(0.15, (tip - base) * 0.9, S.BladeWidth * 0.8)
		bare(zone)
		zone.Transparency = 1
		zone.CFrame = weapon.CFrame * R:Inverse() * CFrame.new(0, (tip + base) / 2, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = weapon, zone
		w.Parent = zone
		zone.Parent = tool
		local flames = Instance.new("ParticleEmitter")
		flames.Name = "Flames"
		flames.Texture = "rbxasset://textures/particles/fire_main.dds"
		flames.Color = ColorSequence.new(S.FlameColor, S.FlameColor2)
		flames.LightEmission = 1
		flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		flames.Lifetime = NumberRange.new(0.25, 0.45)
		flames.Speed = NumberRange.new(0.5, 1.5)
		flames.Acceleration = Vector3.new(0, 6, 0)
		flames.RotSpeed = NumberRange.new(-90, 90)
		flames.Rotation = NumberRange.new(0, 360)
		flames.Rate = S.FlameRate
		flames.Parent = zone
		local glow = Instance.new("PointLight")
		glow.Color = S.HitColor
		glow.Brightness = 1.5
		glow.Range = 7
		glow.Parent = zone
	end

	hookCombo(tool, W, handle)
	tool.Equipped:Connect(function()
		local character = tool.Parent
		local hand = character and character:FindFirstChild("RightHand")
		local ga = hand and hand:FindFirstChild("RightGripAttachment")
		if ga then tool.Grip = GoldenWeapons.Palm:Inverse() * ga.CFrame end
	end)
	return tool
end

-- one shuriken: the imported model or a placeholder (flat gold diamond with an icy centre).
-- Returns the part and its axis R (shuriken space: Y = the flat side)
local function makeShuriken(template, name)
	local main, R
	if template then
		main = cloneModel(template, K.Size, K)
		R = fitAxes(main.Size, Vector3.xAxis, Vector3.yAxis)
	else
		local s = K.Size * 0.7
		main = Instance.new("Part")
		main.Size = Vector3.new(s, K.Thickness, s)
		main.Color, main.Material, main.Reflectance = K.Color, K.Material, K.Reflectance
		R = CFrame.Angles(0, math.pi / 4, 0)
		piece(main, "Core", Vector3.new(K.Thickness + 0.04, 0.35, 0.35), CFrame.Angles(0, 0, math.pi / 2), K,
			K.IceColor, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
	main.Name = name
	bare(main)
	local frost = Instance.new("ParticleEmitter")
	frost.Name = "Frost"
	frost.Color = ColorSequence.new(K.IceColor, Color3.new(1, 1, 1))
	frost.LightEmission = 1
	frost.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
	frost.Lifetime = NumberRange.new(0.3, 0.6)
	frost.Speed = NumberRange.new(0.5, 1.5)
	frost.SpreadAngle = Vector2.new(180, 180)
	frost.Rate = 5
	frost.Parent = main
	return main, R
end

local function setShown(part, on)
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("BasePart") then d.Transparency = on and 0 or 1 end
	end
	part.Transparency = on and 0 or 1
end

-- a thrown shuriken: flies straight, spinning; freezes the first person it hits
local function launchShuriken(character, origin, dir, template, swing)
	local p, R = makeShuriken(template, "ThrownShuriken")
	p.CFrame = CFrame.lookAt(origin, origin + dir) * R
	local a = Instance.new("Attachment")
	a.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0 = att(p, "T0", Vector3.new(0, 0.25, 0), R)
	trail.Attachment1 = att(p, "T1", Vector3.new(0, -0.25, 0), R)
	trail.Lifetime = 0.25
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(K.TrailColor, K.TrailColor2)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = p
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = a
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = dir * K.Speed
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = p
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = a
	av.AngularVelocity = Vector3.new(0, 30, 0)
	av.MaxTorque = math.huge
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = p
	p.Parent = workspace
	pcall(function() p:SetNetworkOwner(nil) end)
	p.AssemblyLinearVelocity = dir * K.Speed

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, p }
	local last, travelled, born = origin, 0, os.clock()
	local conn
	local function finish(at)
		if conn then conn:Disconnect() end
		conn = nil
		shatter(at)
		p:Destroy()
	end
	conn = RunService.Heartbeat:Connect(function()
		if not p.Parent then
			conn:Disconnect()
			return
		end
		local now = p.Position
		local step = now - last
		if step.Magnitude > 1e-3 then
			local hit = workspace:Spherecast(last, K.HitRadius, step, params)
			if hit then
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				local hum = model and model:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC") then
					local tRoot = model:FindFirstChild("HumanoidRootPart") or hit.Instance
					hum:TakeDamage(swing.damage)
					model:SetAttribute("LastHit", os.clock())
					if not tRoot.Anchored then tRoot.AssemblyLinearVelocity = dir * 14 + Vector3.new(0, 6, 0) end
					hitFx(K, tRoot, model, swing.damage, swing.final)
					freeze(model, hum, swing.final and K.FinalFreezeTime or K.FreezeTime)
				end
				finish(hit.Position)
				return
			end
			travelled += step.Magnitude
			last = now
		end
		if travelled > K.Range or os.clock() - born > 3 then finish(now) end
	end)
end

local throwers = setmetatable({}, { __mode = "k" }) -- [tool] = function(aim), called by ShurikenThrow

local function buildShurikens(template)
	local tool = Instance.new("Tool")
	tool.Name = K.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click to throw where you aim"
	tool:SetAttribute("Swing", 1)
	tool:SetAttribute("SwingId", 0)

	local right, R = makeShuriken(template, "Handle")
	right.Parent = tool
	local left = makeShuriken(template, "ShurikenL")
	left.CFrame = right.CFrame
	-- stays with the tool in the backpack; held in the left hand while equipped
	local stow = Instance.new("WeldConstraint")
	stow.Name = "Stow"
	stow.Part0, stow.Part1 = right, left
	stow.Parent = left
	left.Parent = tool
	local hold = GoldenWeapons.ShurikenHold * R

	tool.Equipped:Connect(function()
		local character = tool.Parent
		local hand = character and character:FindFirstChild("RightHand")
		local ga = hand and hand:FindFirstChild("RightGripAttachment")
		if ga then tool.Grip = hold:Inverse() * ga.CFrame end
		local lh = character and character:FindFirstChild("LeftHand")
		if lh then
			stow.Enabled = false
			local w = Instance.new("Weld")
			w.Name = "HandWeld"
			w.Part0, w.Part1 = lh, left
			w.C0 = hold
			w.Parent = left
		end
	end)
	tool.Unequipped:Connect(function()
		local w = left:FindFirstChild("HandWeld")
		if w then w:Destroy() end
		left.CFrame = right.CFrame
		stow.Enabled = true
	end)

	local swingSounds = {}
	for i, id in ipairs(K.Sounds.Swing) do swingSounds[i] = sound(right, id, 0.5) end
	local combo = { step = 0, start = 0, len = 0 }
	local reloads = {}
	-- the thrown one is gone from your hand until a new one forms
	local function reload(part)
		local token = (reloads[part] or 0) + 1
		reloads[part] = token
		setShown(part, false)
		task.delay(K.Reload, function()
			if reloads[part] ~= token then return end
			setShown(part, true)
			local frost = part:FindFirstChild("Frost")
			if frost then frost:Emit(10) end
		end)
	end

	throwers[tool] = function(aim)
		local character = tool.Parent
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or not root then return end
		local now = os.clock()
		if now - combo.start < combo.len * 0.8 then return end -- still mid-throw
		if now - (combo.start + combo.len) > K.ComboWindow then combo.step = 0 end
		combo.step = combo.step % #K.Swings + 1
		local swing = K.Swings[combo.step]
		combo.start, combo.len = now, swing.time
		tool:SetAttribute("Swing", combo.step)
		tool:SetAttribute("SwingId", (tool:GetAttribute("SwingId") or 0) + 1)
		local s = swingSounds[math.random(1, #swingSounds)]
		s.PlaybackSpeed = 1.1 + math.random() * 0.25
		s:Play()

		task.delay(swing.time * swing.release, function()
			if tool.Parent ~= character then return end
			for _, h in ipairs(swing.hands) do
				local side = h == "R" and 1 or -1
				-- the server doesn't see the arm animation: let go about where the hand is
				local origin = root.CFrame:PointToWorldSpace(Vector3.new(side * 1.0, 1.3, -1.5))
				local dir = aim - origin
				if dir.Magnitude < 3 or dir.Unit:Dot(root.CFrame.LookVector) < -0.2 then dir = root.CFrame.LookVector end
				launchShuriken(character, origin, dir.Unit, template, swing)
				reload(h == "R" and right or left)
			end
		end)
	end
	return tool
end

-- both sticks crossed on your back while the tool isn't out
local function buildNunchuckHolster(character, stickT)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not torso then return nil end
	local old = character:FindFirstChild(N.HolsterName)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = N.HolsterName
	for i, side in ipairs({ -1, 1 }) do
		local p = makeStick(stickT, "Back" .. i)
		local R = axisFor(p.Size)
		local stickCF = CFrame.new(side * 0.26, -0.1, 0.7) * CFrame.Angles(0, 0, -side * 0.13) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, side * 0.35, 0)
		p.CFrame = torso.CFrame * stickCF * R
		local w = Instance.new("Weld")
		w.Part0, w.Part1 = torso, p
		w.C0 = stickCF * R
		w.Parent = p
		p.Parent = folder
	end
	folder.Parent = character
	return folder
end

-- sword / scythe across your back (BackGrip / BackAngle in the weapon's settings)
local function buildBackHolster(character, W, template)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not torso then return nil end
	local old = character:FindFirstChild(W.HolsterName)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = W.HolsterName
	local p, R, grip = makeWeapon(W, template, "OnBack")
	local cf = CFrame.new(W.BackGrip) * CFrame.Angles(0, 0, W.BackAngle) * CFrame.Angles(0, math.pi / 2, 0)
		* CFrame.new(0, -grip, 0)
	p.CFrame = torso.CFrame * cf * R
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = torso, p
	w.C0 = cf * R
	w.Parent = p
	p.Parent = folder
	folder.Parent = character
	return folder
end

-- two shurikens flat against your back
local function buildShurikenHolster(character, template)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not torso then return nil end
	local old = character:FindFirstChild(K.HolsterName)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = K.HolsterName
	for i, side in ipairs({ -1, 1 }) do
		local p, R = makeShuriken(template, "OnBack" .. i)
		p.Frost:Destroy()
		local cf = CFrame.new(side * 0.4, 0.15, 0.58) * CFrame.Angles(math.pi / 2, 0, 0)
		p.CFrame = torso.CFrame * cf * R
		local w = Instance.new("Weld")
		w.Part0, w.Part1 = torso, p
		w.C0 = cf * R
		w.Parent = p
		p.Parent = folder
	end
	folder.Parent = character
	return folder
end

local function showHolster(folder, on)
	if not folder then return end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Strap" then d.Transparency = on and 0 or 1 end
	end
end

local function elementOf(player)
	local e = player:GetAttribute("SpinjitzuElement")
	if e and Config.Presets[e] then return e end
	return Config.Element
end

-- remove every Golden Weapon (and the one on your back) from the player
local function clearWeapons(player, backpack, char)
	for _, W in pairs(GoldenWeapons.Weapons) do
		for _, where in ipairs({ backpack, char }) do
			local t = where:FindFirstChild(W.ToolName)
			if t then t:Destroy() end
		end
		local h = char:FindFirstChild(W.HolsterName)
		if h then h:Destroy() end
	end
end

local giveToken = setmetatable({}, { __mode = "k" }) -- newest give() per player wins

-- which weapons the player should have, the one for their back first
local function wantedWeapons(player)
	local own = GoldenWeapons.ByElement[elementOf(player)]
	local attr = player:GetAttribute("GoldenWeapons") -- set from the menu
	local list = {}
	if attr == nil then
		if own then table.insert(list, own) end
	elseif attr ~= "None" then
		for kind in attr:gmatch("[^,]+") do
			if GoldenWeapons.Weapons[kind] and not table.find(list, kind) then table.insert(list, kind) end
		end
		local i = table.find(list, own)
		if i and i > 1 then table.insert(list, 1, table.remove(list, i)) end
	end
	return list
end

local function buildWeapon(W, char, withHolster)
	if W == N then
		local stickT = findMesh({ N.ModelName, N.MeshName })
		if not stickT then warn("[GoldenWeapons] nunchuck mesh not found, using plain sticks") end
		return buildNunchucks(stickT), withHolster and buildNunchuckHolster(char, stickT) or nil
	elseif W == K then
		local model = findModel(K.ModelName)
		return buildShurikens(model), withHolster and buildShurikenHolster(char, model) or nil
	end
	local model = findModel(W.ModelName)
	return buildMelee(W, model), withHolster and buildBackHolster(char, W, model) or nil
end

-- each player gets their own build (the combo state lives in its connections)
local function give(player)
	local token = (giveToken[player] or 0) + 1
	giveToken[player] = token
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
	local char = player.Character
	if not backpack or not char or giveToken[player] ~= token then return end
	local list = wantedWeapons(player)

	-- already exactly these (and the right one on the back)? leave them alone
	local same = true
	for kind, W in pairs(GoldenWeapons.Weapons) do
		local has = backpack:FindFirstChild(W.ToolName) or char:FindFirstChild(W.ToolName)
		if (has ~= nil) ~= (table.find(list, kind) ~= nil) then same = false end
	end
	if same and list[1] and not char:FindFirstChild(GoldenWeapons.Weapons[list[1]].HolsterName) then same = false end
	if same then return end
	clearWeapons(player, backpack, char)

	local built = {}
	for i, kind in ipairs(list) do
		local W = GoldenWeapons.Weapons[kind]
		local tool, holster = buildWeapon(W, char, i == 1)
		table.insert(built, { W = W, tool = tool, holster = holster })
	end
	if giveToken[player] ~= token or player.Character ~= char then -- switched again while building
		for _, b in ipairs(built) do
			b.tool:Destroy()
			if b.holster then b.holster:Destroy() end
		end
		return
	end
	for _, b in ipairs(built) do
		local tool, holster, W = b.tool, b.holster, b.W
		tool.Equipped:Connect(function()
			-- hide it off your back right when the draw animation grabs it
			task.delay(W.Draw.time * W.Draw.grabAt, function()
				if tool.Parent == char then
					showHolster(holster, false)
					-- whoosh as it comes off your back
					local hs = tool.Handle:FindFirstChildOfClass("Sound")
					if hs then hs.PlaybackSpeed = 1.25 hs:Play() end
				end
			end)
		end)
		tool.Unequipped:Connect(function() showHolster(holster, true) end)
		tool.Parent = backpack -- in this order, so they take hotbar slots 1, 2, 3...
	end
end

throwRemote.OnServerEvent:Connect(function(player, aim)
	if typeof(aim) ~= "Vector3" or aim.X ~= aim.X or aim.Y ~= aim.Y or aim.Z ~= aim.Z then return end
	local char = player.Character
	local tool = char and char:FindFirstChild(K.ToolName)
	local throw = tool and throwers[tool]
	if throw then throw(aim) end
end)

local function onPlayer(player)
	player.CharacterAdded:Connect(function() task.wait(0.2) give(player) end)
	-- switching element (E) swaps the weapon
	player:GetAttributeChangedSignal("SpinjitzuElement"):Connect(function() give(player) end)
	player:GetAttributeChangedSignal("GoldenWeapons"):Connect(function() give(player) end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then task.spawn(give, player) end
	onPlayer(player)
end

-- the training dummy out of the way of the bots (200 HP, heals, respawns)
local old = workspace:FindFirstChild("Training Dummy")
if old then old:Destroy() end
TrainingDummy.spawn(Vector3.new(-45, 0, -20), Vector3.new(0, 0, 0))
