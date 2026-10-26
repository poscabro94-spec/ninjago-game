-- StatusEffects v1.2  (ModuleScript in ServerScriptService)
-- What the elemental powers leave behind on whoever they hit:
--   burn(W, model, hum, seconds, damage)   on fire: `damage` every second
--   shock(W, model, hum, seconds, damage)  electrocuted: flickering glow + `damage` every second
--   freeze(W, model, hum, seconds)         can't move; ice grows up from the floor to the neck
--   slow(W, model, hum, seconds)           soaked: half speed, dripping
--   launch(model, up) / blast(model, from, power)   thrown up / thrown away from `from`
-- Hitting again while it's on restarts the time. W = the power's settings (colours, sounds).

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local HitEffects = require(script.Parent:WaitForChild("HitEffects"))

local Status = {}

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart")
end

-- `damage` once a second for `seconds` (the newest call for this effect wins)
local function overTime(W, model, hum, name, seconds, damage, each)
	local token = (model:GetAttribute(name) or 0) + 1
	model:SetAttribute(name, token)
	task.spawn(function()
		for _ = 1, math.floor(seconds + 0.5) do
			task.wait(1)
			if model:GetAttribute(name) ~= token or not hum.Parent or hum.Health <= 0 then return end
			hum:TakeDamage(damage)
			model:SetAttribute("LastHit", os.clock())
			local root = rootOf(model)
			if root then HitEffects.show(W, root, model, damage, false, true) end
			if each then each() end
		end
	end)
	return token
end

function Status.burn(W, model, hum, seconds, damage)
	local root = rootOf(model)
	if not root then return end
	local old = root:FindFirstChild("Burning")
	if old then old:Destroy() end
	local fire = Instance.new("Fire")
	fire.Name = "Burning"
	fire.Heat, fire.Size = 9, 5
	fire.Color, fire.SecondaryColor = W.Color, W.CoreColor
	fire.Parent = root
	Debris:AddItem(fire, seconds + 0.2)
	overTime(W, model, hum, "BurnToken", seconds, damage)
end

function Status.shock(W, model, hum, seconds, damage)
	local root = rootOf(model)
	if not root then return end
	local old = model:FindFirstChild("Shocked")
	if old then old:Destroy() end
	local hl = Instance.new("Highlight")
	hl.Name = "Shocked"
	hl.FillColor, hl.OutlineColor = W.Color, W.CoreColor
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model
	local a = Instance.new("Attachment")
	a.Name = "ShockSparks"
	a.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(W.Color, W.CoreColor)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.08, 0.2)
	pe.Speed = NumberRange.new(6, 14)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 70
	pe.Parent = a
	Debris:AddItem(hl, seconds + 0.1)
	Debris:AddItem(a, seconds + 0.1)
	-- the glow flickers while it lasts
	task.spawn(function()
		local stop = os.clock() + seconds
		while hl.Parent and os.clock() < stop do
			hl.FillTransparency = 0.2 + math.random() * 0.7
			task.wait(0.05)
		end
	end)
	overTime(W, model, hum, "ShockToken", seconds, damage, function()
		if W.Sounds.Zap then
			local s = Instance.new("Sound")
			s.SoundId, s.Volume, s.PlaybackSpeed = W.Sounds.Zap, 0.35, 0.9 + math.random() * 0.5
			s.Parent = root
			s:Play()
			Debris:AddItem(s, 2)
		end
	end)
end

local function shatter(W, pos)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(W.Color, Color3.new(1, 1, 1))
	pe.LightEmission = 0.6
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.3, 0.7)
	pe.Speed = NumberRange.new(8, 18)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -35, 0)
	pe.Rate = 0
	pe.Parent = p
	pe:Emit(35)
	Debris:AddItem(p, 1.5)
end

function Status.freeze(W, model, hum, seconds)
	local root = rootOf(model)
	if not root then return end
	local token = (model:GetAttribute("FreezeToken") or 0) + 1
	model:SetAttribute("FreezeToken", token)
	if model:GetAttribute("FrozenSpeed") == nil then
		model:SetAttribute("FrozenSpeed", hum.WalkSpeed)
		model:SetAttribute("FrozenJump", hum.UseJumpPower and hum.JumpPower or hum.JumpHeight)
	end
	hum.WalkSpeed = 0
	if hum.UseJumpPower then hum.JumpPower = 0 else hum.JumpHeight = 0 end

	-- a block of ice that grows up from the floor until only the head sticks out. Sized from the
	-- body (not the model's bounding box: weapons on the back or other attachments can be huge)
	local old = model:FindFirstChild("IceBlock")
	local fresh = old == nil
	local head = model:FindFirstChild("Head")
	local bottom = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	local top = head and (head.Position.Y - head.Size.Y / 2 + 0.1) or (root.Position.Y + root.Size.Y)
	local full = math.clamp(top - bottom, 0.5, 12)
	local size = Vector3.new(root.Size.X * 1.6, 0, root.Size.Z * 2.2)
	local ice = old or Instance.new("Part")
	ice.Name = "IceBlock"
	ice.Material = Enum.Material.Ice
	ice.Color = W.Color
	ice.Transparency = 0.35
	ice.Anchored, ice.CanCollide, ice.CanQuery, ice.CanTouch, ice.Massless = false, false, false, false, true
	local weld = ice:FindFirstChild("IceWeld") or Instance.new("Weld")
	weld.Name = "IceWeld"
	weld.Part0, weld.Part1 = root, ice
	weld.Parent = ice
	local width = Vector3.new(size.X + 0.8, 0, size.Z + 0.8)
	local function setHeight(h)
		ice.Size = Vector3.new(width.X, h, width.Z)
		local center = Vector3.new(root.Position.X, bottom + h / 2, root.Position.Z)
		weld.C0 = root.CFrame:ToObjectSpace(CFrame.new(center) * root.CFrame.Rotation)
	end
	if fresh then
		setHeight(0.1)
		ice.Parent = model
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local f = math.min((os.clock() - t0) / 0.7, 1)
			if not ice.Parent or not root.Parent then
				conn:Disconnect()
				return
			end
			setHeight(0.1 + (full - 0.1) * (1 - (1 - f) ^ 2))
			if f >= 1 then conn:Disconnect() end
		end)
	end

	task.delay(seconds, function()
		if model:GetAttribute("FreezeToken") ~= token then return end
		if ice.Parent then
			shatter(W, ice.Position)
			ice:Destroy()
		end
		if hum.Parent then
			hum.WalkSpeed = model:GetAttribute("FrozenSpeed") or 16
			local jump = model:GetAttribute("FrozenJump")
			if jump then
				if hum.UseJumpPower then hum.JumpPower = jump else hum.JumpHeight = jump end
			end
		end
		model:SetAttribute("FrozenSpeed", nil)
		model:SetAttribute("FrozenJump", nil)
	end)
end

function Status.slow(W, model, hum, seconds)
	local root = rootOf(model)
	if not root then return end
	local token = (model:GetAttribute("SlowToken") or 0) + 1
	model:SetAttribute("SlowToken", token)
	if model:GetAttribute("SlowedFrom") == nil then model:SetAttribute("SlowedFrom", hum.WalkSpeed) end
	local base = model:GetAttribute("SlowedFrom")
	if not model:GetAttribute("FrozenSpeed") then hum.WalkSpeed = base * 0.5 end
	local old = root:FindFirstChild("Soaked")
	if old then old:Destroy() end
	local a = Instance.new("Attachment")
	a.Name = "Soaked"
	a.Parent = root
	local drips = Instance.new("ParticleEmitter")
	drips.Color = ColorSequence.new(W.CoreColor, W.Color)
	drips.LightEmission = 0.3
	drips.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.1) })
	drips.Lifetime = NumberRange.new(0.4, 0.7)
	drips.Speed = NumberRange.new(0, 1)
	drips.SpreadAngle = Vector2.new(180, 180)
	drips.Acceleration = Vector3.new(0, -30, 0)
	drips.Rate = 25
	drips.Parent = a
	Debris:AddItem(a, seconds)
	task.delay(seconds, function()
		if model:GetAttribute("SlowToken") ~= token then return end
		if hum.Parent and not model:GetAttribute("FrozenSpeed") then hum.WalkSpeed = base end
		model:SetAttribute("SlowedFrom", nil)
	end)
end

local function throwRoot(model, velocity)
	local root = rootOf(model)
	if root and not root.Anchored and not model:GetAttribute("FrozenSpeed") then root.AssemblyLinearVelocity = velocity end
end

function Status.launch(model, up)
	throwRoot(model, Vector3.new(0, up or 60, 0))
end

function Status.blast(model, from, power)
	local root = rootOf(model)
	if not root then return end
	local away = root.Position - from
	away = Vector3.new(away.X, 0, away.Z)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)
	throwRoot(model, away * (power or 70) + Vector3.new(0, 25, 0))
end

-- can this power hit that model? (not yourself, not the demo / Spinjitzu bots)
function Status.target(model, attacker)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if hum and model ~= attacker and hum.Health > 0 and not CollectionService:HasTag(model, "SpinjitzuNPC") then
		return hum
	end
	return nil
end

return Status
