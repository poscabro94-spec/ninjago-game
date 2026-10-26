-- GoldenWeaponsServer v4.6  (Script in ServerScriptService)
-- Builds the Nunchucks of Lightning tool and gives one to every player on spawn (slot 1).
-- When not equipped, both sticks sit crossed on your back. Click = 4-hit combo.
-- The server picks the swing, plays the sounds and does the hit check
-- (damage + knockback + blue hit flash). Also spawns a Training Dummy to fight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local N = GoldenWeapons.Nunchucks

----------------------------------------------------------------------------------------
-- mesh + stick building
----------------------------------------------------------------------------------------

local function findMesh()
	for _, name in ipairs({ N.ModelName, N.MeshName }) do
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

local function hitFx(targetRoot, model, dmg, final)
	local zap = sound(targetRoot, N.Sounds.Zap, 0.25)
	zap.PlaybackSpeed = 1 + math.random() * 0.25
	zap:Play()
	local thud = sound(targetRoot, final and N.Sounds.Final or N.Sounds.Hit[math.random(1, #N.Sounds.Hit)], 0.8)
	thud:Play()
	Debris:AddItem(zap, 3)
	Debris:AddItem(thud, 4)

	local hl = Instance.new("Highlight")
	hl.FillColor = N.BoltColor
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.35
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model
	Debris:AddItem(hl, 0.15)

	local a = Instance.new("Attachment")
	a.Parent = targetRoot
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(N.BoltColor, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.15, 0.35)
	pe.Speed = NumberRange.new(10, 22)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 5
	pe.Rate = 160
	pe.Parent = a
	local light = Instance.new("PointLight")
	light.Color = N.BoltColor
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
	label.TextColor3 = Color3.fromRGB(150, 215, 255)
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

local function doHit(character, swing)
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
			hitFx(tRoot, model, swing.damage, swing.final)
		end
	end
end

----------------------------------------------------------------------------------------
-- tool
----------------------------------------------------------------------------------------

local function buildTool(stickT)
	local tool = Instance.new("Tool")
	tool.Name = N.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click to swing (4-hit combo)"
	tool:SetAttribute("Swing", 1)
	tool:SetAttribute("SwingId", 0)

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

	local swingSounds = {}
	for i, id in ipairs(N.Sounds.Swing) do swingSounds[i] = sound(handle, id, 0.5) end

	local hold = GoldenWeapons.HoldOffset(R)
	local combo = { step = 0, start = 0, len = 0 }

	tool.Equipped:Connect(function()
		local character = tool.Parent
		local hand = character and character:FindFirstChild("RightHand")
		local ga = hand and hand:FindFirstChild("RightGripAttachment")
		if ga then tool.Grip = hold:Inverse() * ga.CFrame end
	end)

	tool.Activated:Connect(function()
		local character = tool.Parent
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local now = os.clock()
		if now - combo.start < combo.len * 0.8 then return end -- still mid-swing
		if now - (combo.start + combo.len) > N.ComboWindow then combo.step = 0 end
		combo.step = combo.step % #N.Swings + 1
		local swing = N.Swings[combo.step]
		combo.start, combo.len = now, swing.time
		tool:SetAttribute("Swing", combo.step)
		tool:SetAttribute("SwingId", (tool:GetAttribute("SwingId") or 0) + 1)

		local s = swingSounds[math.random(1, #swingSounds)]
		s.PlaybackSpeed = 0.9 + math.random() * 0.25
		s:Play()
		if swing.name == "spin" then
			task.delay(swing.time * 0.35, function()
				s.PlaybackSpeed = 1.15
				s:Play()
			end)
		end
		task.delay(swing.time * swing.hitAt, function()
			if tool.Parent == character then doHit(character, swing) end
		end)
	end)

	return tool
end

-- both sticks crossed on your back while the tool isn't out
local function buildHolster(character, stickT)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not torso then return nil end
	local old = character:FindFirstChild("NunchuckHolster")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "NunchuckHolster"
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

local function showHolster(folder, on)
	if not folder then return end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Strap" then d.Transparency = on and 0 or 1 end
	end
end

-- each player gets their own build (the combo state lives in its connections)
local function give(player)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
	local char = player.Character
	if not backpack or not char then return end
	if backpack:FindFirstChild(N.ToolName) or char:FindFirstChild(N.ToolName) then return end
	local stickT = findMesh()
	if not stickT then warn("[GoldenWeapons] nunchuck mesh not found, using plain sticks") end
	local tool = buildTool(stickT)
	local holster = buildHolster(char, stickT)
	tool.Equipped:Connect(function()
		-- hide them off your back right when the draw animation grabs them
		task.delay(N.Draw.time * N.Draw.grabAt, function()
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

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function() task.wait(0.2) give(player) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then task.spawn(give, player) end
	player.CharacterAdded:Connect(function() task.wait(0.2) give(player) end)
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
