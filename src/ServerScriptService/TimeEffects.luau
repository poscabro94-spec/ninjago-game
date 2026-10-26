-- TimeEffects v1.0  (ModuleScript in ServerScriptService)
-- What the Time Blades do to time:
--   lock(model, seconds, color)   time-locked: frozen in place AND mid-pose (NinjaAnimator stops
--                                 animating characters with the TimeStopped attribute), tinted
--   holdPart(part, seconds)       a flying shot hangs in mid-air, then carries on (the shot loops
--                                 pause while the part has the TimeStopped attribute)
-- Locking again while it's on restarts the time.

local Debris = game:GetService("Debris")

local Time = {}

function Time.lock(model, seconds, color)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local token = (model:GetAttribute("TimeToken") or 0) + 1
	model:SetAttribute("TimeToken", token)
	if model:GetAttribute("TimeStopped") == nil then
		model:SetAttribute("TimeWasAnchored", root.Anchored)
	end
	model:SetAttribute("TimeStopped", true)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	local hl = model:FindFirstChild("TimeLock") or Instance.new("Highlight")
	hl.Name = "TimeLock"
	hl.FillColor = color
	hl.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
	hl.FillTransparency = 0.6
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model
	task.delay(seconds, function()
		if model:GetAttribute("TimeToken") ~= token then return end
		if root.Parent then root.Anchored = model:GetAttribute("TimeWasAnchored") == true end
		model:SetAttribute("TimeStopped", nil)
		model:SetAttribute("TimeWasAnchored", nil)
		if hl.Parent then hl:Destroy() end
	end)
end

function Time.holdPart(part, seconds)
	if part:GetAttribute("TimeStopped") then return end
	part:SetAttribute("TimeStopped", true)
	local wasAnchored = part.Anchored
	part.Anchored = true
	task.delay(seconds, function()
		if not part.Parent then return end
		part.Anchored = wasAnchored
		part:SetAttribute("TimeStopped", nil)
	end)
end

-- a little burst of the blade's colour, for when time snaps back
function Time.burst(pos, color)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.2, 0.5)
	pe.Speed = NumberRange.new(6, 14)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = p
	pe:Emit(25)
	Debris:AddItem(p, 1)
end

return Time
