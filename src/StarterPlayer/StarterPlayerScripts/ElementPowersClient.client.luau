-- ElementPowersClient v1.0  (LocalScript in StarterPlayerScripts)
-- Your elemental power buttons (Lightning, empty hands): left click = lightning ball combo,
-- hold right click = lightning beam. Turns you toward where you aim, and draws everyone's
-- beam as a crackling arc from the hand to whatever it hits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Powers = require(ReplicatedStorage:WaitForChild("ElementPowers"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local remote = ReplicatedStorage:WaitForChild("ElementPower")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local L = Powers.Lightning
local rng = Random.new()

local function canUse()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or character:FindFirstChildOfClass("Tool") then return false end
	if character:GetAttribute("SpinjitzuActive") or character:GetAttribute("DragonPhase") or character:GetAttribute("CreationPhase") then
		return false
	end
	return (player:GetAttribute("SpinjitzuElement") or Config.Element) == "Lightning"
end

-- turn to face the aim (only sideways), so the throw / beam goes where you point
local function face(aim)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local flat = Vector3.new(aim.X, root.Position.Y, aim.Z)
	if (flat - root.Position).Magnitude > 1 then root.CFrame = CFrame.lookAt(root.Position, flat) end
end

local beaming = false
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and canUse() then
		face(mouse.Hit.Position)
		remote:FireServer("ball", mouse.Hit.Position)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and canUse() then
		beaming = true
		remote:FireServer("beam", mouse.Hit.Position)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and beaming then
		beaming = false
		remote:FireServer("beam", false)
	end
end)

-- while the beam is on: keep facing the aim and tell the server where it points
local sendT = 0
RunService.RenderStepped:Connect(function(dt)
	if not beaming then return end
	if not canUse() then
		beaming = false
		remote:FireServer("beam", false)
		return
	end
	face(mouse.Hit.Position)
	sendT -= dt
	if sendT <= 0 then
		sendT = 1 / 15
		remote:FireServer("aim", mouse.Hit.Position)
	end
end)

----------------------------------------------------------------------------------------
-- beam look (every character with PowerBeam on)
----------------------------------------------------------------------------------------

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LightningBeams"
fxFolder.Parent = workspace
mouse.TargetFilter = fxFolder -- aim through the beam itself
local drawn = {} -- [character] = beam parts

local function point(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = fxFolder
	return p
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
	b.Segments = segments or 10
	b.Parent = a0.Parent
	return b
end

local function makeBeam()
	local from, to = point("From"), point("To")
	local d = { from = from, to = to, arcs = {} }
	d.a0 = Instance.new("Attachment")
	d.a0.Parent = from
	d.a1 = Instance.new("Attachment")
	d.a1.Parent = to
	beam(d.a0, d.a1, 1.0, L.Color, 0.55, 2)       -- glow
	beam(d.a0, d.a1, 0.28, L.CoreColor, 0, 2)      -- white-hot core
	-- crackling arcs around it: new random bends every few frames
	for i = 1, 3 do
		local s, e = Instance.new("Attachment"), Instance.new("Attachment")
		s.Parent, e.Parent = from, to
		d.arcs[i] = { s = s, e = e, b = beam(s, e, 0.09, L.CoreColor, 0.1, 12) }
	end
	local glowFrom = Instance.new("PointLight")
	glowFrom.Color, glowFrom.Brightness, glowFrom.Range = L.Color, 2.5, 8
	glowFrom.Parent = from
	local glowTo = glowFrom:Clone()
	glowTo.Range = 12
	glowTo.Parent = to
	d.sparks = Instance.new("ParticleEmitter")
	d.sparks.Color = ColorSequence.new(L.Color, Color3.new(1, 1, 1))
	d.sparks.LightEmission = 1
	d.sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	d.sparks.Lifetime = NumberRange.new(0.1, 0.3)
	d.sparks.Speed = NumberRange.new(6, 16)
	d.sparks.SpreadAngle = Vector2.new(180, 180)
	d.sparks.Rate = 60
	d.sparks.Parent = to
	return d
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local jitter = 0

RunService.RenderStepped:Connect(function(dt)
	jitter -= dt
	local rebend = jitter <= 0
	if rebend then jitter = 0.04 end
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local on = character and character:GetAttribute("PowerBeam")
		local hand = character and character:FindFirstChild("RightHand")
		local aim = character and character:GetAttribute("PowerAim")
		if p == player and beaming then aim = mouse.Hit.Position end -- your own: no delay
		if on and hand and typeof(aim) == "Vector3" then
			local d = drawn[character]
			if not d then
				d = makeBeam()
				drawn[character] = d
			end
			local start = hand.Position + hand.CFrame.UpVector * -0.3
			local dir = aim - start
			local range = Powers.Lightning.BeamRange
			dir = dir.Magnitude > 0.1 and dir.Unit or character:GetPivot().LookVector
			rayParams.FilterDescendantsInstances = { character, fxFolder }
			local hit = workspace:Raycast(start, dir * range, rayParams)
			local stop = hit and hit.Position or start + dir * range
			d.from.CFrame = CFrame.lookAt(start, stop)
			d.to.CFrame = CFrame.lookAt(stop, start)
			d.sparks.Enabled = hit ~= nil
			if rebend then
				local len = (stop - start).Magnitude
				for _, arc in ipairs(d.arcs) do
					arc.s.CFrame = CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
					arc.e.CFrame = CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
					arc.b.CurveSize0 = rng:NextNumber(-1, 1) * math.min(len * 0.15, 2.5)
					arc.b.CurveSize1 = rng:NextNumber(-1, 1) * math.min(len * 0.15, 2.5)
					arc.b.Transparency = NumberSequence.new(rng:NextNumber() < 0.25 and 1 or rng:NextNumber(0, 0.4))
				end
			end
		end
	end
	for character, d in pairs(drawn) do
		if not character.Parent or not character:GetAttribute("PowerBeam") then
			d.from:Destroy()
			d.to:Destroy()
			drawn[character] = nil
		end
	end
end)
