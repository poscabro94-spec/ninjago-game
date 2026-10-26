-- GoldenWeaponsServer v5.0  (Script in ServerScriptService)
-- Gives every player the Golden Weapon of their element on spawn (slot 1) and swaps it when
-- they switch element: Lightning = Nunchucks of Lightning, Fire = Sword of Fire.
-- When not equipped, the weapon sits on your back. Click = 4-hit combo.
-- The server picks the swing, plays the sounds and does the hit check
-- (damage + knockback + hit flash in the weapon's colour). Also spawns a Training Dummy to fight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local N = GoldenWeapons.Nunchucks
local S = GoldenWeapons.Sword

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

local function hitFx(W, targetRoot, model, dmg, final)
	if W.Sounds.Zap then
		local zap = sound(targetRoot, W.Sounds.Zap, 0.25)
		zap.PlaybackSpeed = 1 + math.random() * 0.25
		zap:Play()
		Debris:AddItem(zap, 3)
	end
	local thud = sound(targetRoot, final and W.Sounds.Final or W.Sounds.Hit[math.random(1, #W.Sounds.Hit)], 0.8)
	thud:Play()
	Debris:AddItem(thud, 4)
	if final and W.BurnTime then
		local fire = Instance.new("Fire")
		fire.Heat, fire.Size = 8, 4
		fire.Color, fire.SecondaryColor = W.HitColor, W.FlameColor
		fire.Parent = targetRoot
		Debris:AddItem(fire, W.BurnTime)
	end

	local hl = Instance.new("Highlight")
	hl.FillColor = W.HitColor
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.35
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model
	Debris:AddItem(hl, 0.15)

	local a = Instance.new("Attachment")
	a.Parent = targetRoot
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(W.HitColor, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.15, 0.35)
	pe.Speed = NumberRange.new(10, 22)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 5
	pe.Rate = 160
	pe.Parent = a
	local light = Instance.new("PointLight")
	light.Color = W.HitColor
	light.Brightness = 4
	light.Range = 10
	light.Parent = a
	task.delay(0.12, function() pe.Enabled = false light.Enabled = false end)
	Debris:AddItem(a, 1)

	-- floating damage number
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(80, 36)
	gui.StudsOffset = Vector3.new(math.random() * 2 - 1, 2.5, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = tostring(dmg)
	label.TextColor3 = W.HitTextColor
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = targetRoot
	task.spawn(function()
		for i = 1, 12 do
			gui.StudsOffset += Vector3.new(0, 0.12, 0)
			label.TextTransparency = i / 12
			label.TextStrokeTransparency = 0.2 + i / 15
			task.wait(0.04)
		end
		gui:Destroy()
	end)
end

local function doHit(W, character, swing)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local center = swing.around and root.Position or (root.Position + root.CFrame.LookVector * (swing.name == "twirl" and 1.5 or 3))
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(center, swing.range, params)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and not done[model] and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC") then
			done[model] = true
			local tRoot = model:FindFirstChild("HumanoidRootPart") or part
			hum:TakeDamage(swing.damage)
			model:SetAttribute("LastHit", os.clock())
			if not tRoot.Anchored then
				local away = tRoot.Position - root.Position
				away = Vector3.new(away.X, 0, away.Z)
				away = away.Magnitude > 0.1 and away.Unit or root.CFrame.LookVector
				tRoot.AssemblyLinearVelocity = away * swing.knock + Vector3.new(0, swing.up or 8, 0)
			end
			hitFx(W, tRoot, model, swing.damage, swing.final)
		end
	end
end

----------------------------------------------------------------------------------------
-- tools
----------------------------------------------------------------------------------------

-- fire burst around you (Sword of Fire's spin slash)
local function fireBurst(root)
	local a = Instance.new("Attachment")
	a.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/fire_main.dds"
	pe.Color = ColorSequence.new(S.FlameColor, S.FlameColor2)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(0.3, 0.55)
	pe.Speed = NumberRange.new(16, 26)
	pe.SpreadAngle = Vector2.new(180, 8)
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Drag = 5
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(70)
	local light = Instance.new("PointLight")
	light.Color = S.HitColor
	light.Brightness = 5
	light.Range = 16
	light.Parent = a
	task.delay(0.2, function() light.Enabled = false end)
	Debris:AddItem(a, 1.5)
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
			doHit(W, character, swing)
			local root = character:FindFirstChild("HumanoidRootPart")
			if swing.burst and root then fireBurst(root) end
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

-- maps an imported sword mesh onto sword space: longest side -> +Y (tip), thinnest -> X
local function swordAxis(size)
	local dims = { size.X, size.Y, size.Z }
	local order = { 1, 2, 3 }
	table.sort(order, function(a, b) return dims[a] > dims[b] end)
	local long, mid, thin = order[1], order[2], order[3]
	local img = {}
	img[long] = S.FlipModel and -Vector3.yAxis or Vector3.yAxis
	img[thin] = Vector3.xAxis
	-- the middle axis follows from the other two (keeps it right-handed)
	if mid == 1 then img[1] = img[2]:Cross(img[3])
	elseif mid == 2 then img[2] = img[3]:Cross(img[1]) end
	return CFrame.fromMatrix(Vector3.zero, img[1], img[2])
end

-- the sword itself: the imported "SwordOfFire" mesh, or a placeholder made of parts.
-- returns the main part (everything else is welded to it), its axis and points along the blade
-- (sword-space Y): grip = where the hand holds it, base = where the blade starts, tip
local function makeSword(template, name)
	local main, R, grip, base, tip
	if template then
		main = template:Clone()
		for _, c in ipairs(main:GetChildren()) do c:Destroy() end
		local sz = main.Size
		main.Size = sz * (S.Length / math.max(sz.X, sz.Y, sz.Z))
		main.TextureID = ""
		main.Color, main.Material, main.Reflectance = S.Color, S.Material, S.Reflectance
		R = swordAxis(main.Size)
		local half = S.Length / 2
		grip, base, tip = -half + S.GripFromEnd, -half + S.HiltLength, half
	else
		local bl, bw, bt, gl = S.BladeLength, S.BladeWidth, S.BladeThickness, S.GripLength
		main = Instance.new("Part")
		main.Size = Vector3.new(bt, bl, bw)
		main.Color, main.Material, main.Reflectance = S.Color, S.Material, S.Reflectance
		R = CFrame.identity
		local function piece(pname, size, cf, color, material, shape)
			local p = Instance.new("Part")
			p.Name = pname
			p.Size = size
			if shape then p.Shape = shape end
			bare(p)
			p.Color = color or S.Color
			p.Material = material or S.Material
			p.Reflectance = material and 0 or S.Reflectance
			p.CFrame = main.CFrame * cf
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = main, p
			w.Parent = p
			p.Parent = main
		end
		local guardY = -bl / 2 - 0.11
		piece("Point", Vector3.new(bt, bw * 0.71, bw * 0.71), CFrame.new(0, bl / 2, 0) * CFrame.Angles(math.pi / 4, 0, 0))
		piece("Core", Vector3.new(bt + 0.02, bl * 0.85, 0.08), CFrame.new(0, -bl * 0.05, 0), S.CoreColor, Enum.Material.Neon)
		piece("Guard", Vector3.new(0.26, 0.22, 1.1), CFrame.new(0, guardY, 0))
		piece("Grip", Vector3.new(gl, 0.22, 0.22), CFrame.new(0, guardY - 0.11 - gl / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			S.GripColor, Enum.Material.Fabric, Enum.PartType.Cylinder)
		piece("Pommel", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, guardY - 0.11 - gl - 0.1, 0), nil, nil, Enum.PartType.Ball)
		grip, base, tip = guardY - 0.11 - gl / 2, -bl / 2, bl / 2 + bw * 0.35
	end
	main.Name = name
	bare(main)
	return main, R, grip, base, tip
end

local function buildSword(template)
	local tool = Instance.new("Tool")
	tool.Name = S.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click to swing (4-hit combo)"

	local handle, R, grip, base, tip = makeSword(template, "Handle")
	handle.Parent = tool
	local tipAt = att(handle, "Tip", Vector3.new(0, tip, 0), R)
	local baseAt = att(handle, "BladeBase", Vector3.new(0, base, 0), R)
	goldTrail(handle, baseAt, tipAt).Color = ColorSequence.new(S.TrailColor, S.TrailColor2)

	-- flames along the blade: an invisible part covering it carries the emitter + light
	local zone = Instance.new("Part")
	zone.Name = "FlameZone"
	zone.Size = Vector3.new(0.15, (tip - base) * 0.9, S.BladeWidth * 0.8)
	bare(zone)
	zone.Transparency = 1
	zone.CFrame = handle.CFrame * R:Inverse() * CFrame.new(0, (tip + base) / 2, 0)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = handle, zone
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

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Rate = 0
	sparks.Color = ColorSequence.new(S.FlameColor, S.FlameColor2)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Parent = tipAt

	hookCombo(tool, S, handle)
	local hold = GoldenWeapons.SwordHold(R, grip)
	tool.Equipped:Connect(function()
		local character = tool.Parent
		local hand = character and character:FindFirstChild("RightHand")
		local ga = hand and hand:FindFirstChild("RightGripAttachment")
		if ga then tool.Grip = hold:Inverse() * ga.CFrame end
	end)
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
	-- leather strap across the back that holds them
	local strapColor = Color3.fromRGB(70, 45, 30)
	local function strap(name, size, cf)
		local s = Instance.new("Part")
		s.Name = name
		s.Size = size
		bare(s)
		s.Color = strapColor
		s.Material = Enum.Material.Leather
		s.CFrame = torso.CFrame * cf
		local w = Instance.new("Weld")
		w.Part0, w.Part1 = torso, s
		w.C0 = cf
		w.Parent = s
		s.Parent = folder
	end
	strap("Strap", Vector3.new(0.2, 2.3, 0.06), CFrame.new(0, 0, 0.56) * CFrame.Angles(0, 0, 0.62))
	strap("Band", Vector3.new(0.9, 0.14, 0.55), CFrame.new(0, -0.15, 0.72))
	folder.Parent = character
	return folder
end

-- sword across your back: hilt up over the right shoulder, tip down by the left hip
local function buildSwordHolster(character, template)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not torso then return nil end
	local old = character:FindFirstChild(S.HolsterName)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = S.HolsterName
	local p, R, grip = makeSword(template, "BackSword")
	local swordCF = CFrame.new(0.55, 1.05, 0.65) * CFrame.Angles(0, 0, math.pi - 0.6) * CFrame.Angles(0, math.pi / 2, 0)
		* CFrame.new(0, -grip, 0)
	p.CFrame = torso.CFrame * swordCF * R
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = torso, p
	w.C0 = swordCF * R
	w.Parent = p
	p.Parent = folder
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

-- each player gets their own build (the combo state lives in its connections)
local function give(player)
	local token = (giveToken[player] or 0) + 1
	giveToken[player] = token
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
	local char = player.Character
	if not backpack or not char or giveToken[player] ~= token then return end
	local kind = GoldenWeapons.ByElement[elementOf(player)]
	local W = kind and GoldenWeapons.Weapons[kind]
	if W and (backpack:FindFirstChild(W.ToolName) or char:FindFirstChild(W.ToolName)) then return end
	clearWeapons(player, backpack, char)
	if not W then return end

	local tool, holster
	if W == N then
		local stickT = findMesh({ N.ModelName, N.MeshName })
		if not stickT then warn("[GoldenWeapons] nunchuck mesh not found, using plain sticks") end
		tool = buildNunchucks(stickT)
		holster = buildNunchuckHolster(char, stickT)
	else
		local swordT = findMesh({ S.ModelName })
		tool = buildSword(swordT)
		holster = buildSwordHolster(char, swordT)
	end
	if giveToken[player] ~= token or player.Character ~= char then -- switched again while building
		tool:Destroy()
		if holster then holster:Destroy() end
		return
	end
	tool.Equipped:Connect(function()
		-- hide it off your back right when the draw animation grabs it
		task.delay(W.Draw.time * W.Draw.grabAt, function()
			if tool.Parent == char then
				showHolster(holster, false)
				-- whoosh as they come off your back
				local hs = tool.Handle:FindFirstChildOfClass("Sound")
				if hs then hs.PlaybackSpeed = 1.25 hs:Play() end
			end
		end)
	end)
	tool.Unequipped:Connect(function() showHolster(holster, true) end)
	tool.Parent = backpack
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function() task.wait(0.2) give(player) end)
	-- switching element (E) swaps the weapon
	player:GetAttributeChangedSignal("SpinjitzuElement"):Connect(function() give(player) end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then task.spawn(give, player) end
	onPlayer(player)
end

----------------------------------------------------------------------------------------
-- training dummy: 200 HP, heals after 4s without being hit, respawns 3s after it dies
----------------------------------------------------------------------------------------

local DUMMY_SPOT = CFrame.lookAt(Vector3.new(-45, 4, -20), Vector3.new(0, 4, 0)) -- out of the way of the bots

local function spawnDummy()
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = Color3.fromRGB(190, 160, 110)
	desc.TorsoColor = Color3.fromRGB(150, 110, 70)
	desc.LeftArmColor, desc.RightArmColor = desc.HeadColor, desc.HeadColor
	desc.LeftLegColor, desc.RightLegColor = desc.TorsoColor, desc.TorsoColor
	local ok, dummy = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not dummy then warn("[GoldenWeapons] dummy failed:", dummy) return end
	dummy.Name = "Training Dummy"
	local hum = dummy:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth, hum.Health = 200, 200
	hum.DisplayName = "Training Dummy"
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.WalkSpeed, hum.JumpPower = 0, 0
	hum.BreakJointsOnDeath = false
	local animate = dummy:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	dummy:PivotTo(DUMMY_SPOT)
	dummy.Parent = workspace
	local root = dummy:FindFirstChild("HumanoidRootPart")
	if root then pcall(function() root:SetNetworkOwner(nil) end) end

	task.spawn(function()
		while dummy.Parent and hum.Health > 0 do
			task.wait(0.5)
			local last = dummy:GetAttribute("LastHit") or 0
			if os.clock() - last > 4 and hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
			if root and (root.Position - DUMMY_SPOT.Position).Magnitude > 40 then dummy:PivotTo(DUMMY_SPOT) end
		end
	end)
	hum.Died:Connect(function()
		task.wait(3)
		dummy:Destroy()
		spawnDummy()
	end)
end

local old = workspace:FindFirstChild("Training Dummy")
if old then old:Destroy() end
spawnDummy()
