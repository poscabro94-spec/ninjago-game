-- HitEffects v1.0  (ModuleScript in ServerScriptService)
-- What a hit looks like: sounds, a flash in the attacker's colour, sparks and a floating damage
-- number. Used by the Golden Weapons and the elemental powers.

local Debris = game:GetService("Debris")

local HitEffects = {}

local function sound(parent, id, vol)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.6
	s.RollOffMaxDistance = 80
	s.Parent = parent
	return s
end

-- W: settings with HitColor, HitTextColor, Sounds { Hit = {...}, Final, Zap? } and optional
-- BurnTime + FlameColor (the final hit sets them on fire)
function HitEffects.show(W, targetRoot, model, dmg, final)
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

return HitEffects
