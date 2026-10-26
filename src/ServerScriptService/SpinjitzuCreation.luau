-- SpinjitzuCreation v1.3  (ModuleScript in ServerScriptService)
-- Tornado of Creation: 4 ninja (Fire, Earth, Lightning, Ice) start Spinjitzu one after
-- another, their tornadoes come together, and merge into one huge tornado. One of the players in
-- it (picked at random) steers it, slowly (walk to move it: their client sends where they're
-- walking, see steer), and it wrecks whoever it touches (and breaks Shatterspin). Used by
-- SpinjitzuServer (players pressing T) and SpinjitzuBot (the demo bots: nobody steers those,
-- and they don't hurt anyone).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local Status = require(script.Parent:WaitForChild("StatusEffects"))
local HitEffects = require(script.Parent:WaitForChild("HitEffects"))

local Creation = {}
Creation.busy = {} -- [character] = true while part of a Creation
local piloting = {} -- [pilot character] = { move = Vector3 }

local HIT = { -- how its hits look (HitEffects)
	HitColor = Color3.fromRGB(170, 230, 255), HitTextColor = Color3.fromRGB(200, 240, 255),
	Sounds = {
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675",
	},
}

-- the pilot's client: where they're walking (Humanoid.MoveDirection), a few times a second
function Creation.steer(character, v)
	local st = piloting[character]
	if st and typeof(v) == "Vector3" then
		local flat = Vector3.new(v.X, 0, v.Z)
		st.move = flat.Magnitude > 1 and flat.Unit or flat
	end
end

local function notify(player, text)
	local remote = ReplicatedStorage:FindFirstChild("SpinjitzuToggle")
	if remote and player then remote:FireClient(player, "notify", text) end
end

local TAU = math.pi * 2

local function groundBelow(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	local fx = workspace:FindFirstChild("SpinjitzuFX")
	if fx then table.insert(list, fx) end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(pos + Vector3.new(0, 50, 0), Vector3.new(0, -300, 0), params)
	return hit and hit.Position.Y or pos.Y - 3
end

-- invisible giant "character" the big tornado is drawn on (every client renders it)
local function makeAnchor(center, groundY)
	local m = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	m.Name = "TornadoOfCreation"
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local animate = m:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency, d.Anchored = 1, true
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
		elseif d:IsA("Decal") then
			d:Destroy()
		end
	end
	m:ScaleTo(Config.CreationScale or 4)
	local root = m:WaitForChild("HumanoidRootPart")
	local y = groundY + hum.HipHeight + root.Size.Y / 2
	m:PivotTo(CFrame.new(center.X, y, center.Z))
	local preset = Config.Presets.Creation
	m:SetAttribute("SpinjitzuElement", "Creation")
	m:SetAttribute("SpinjitzuColor", preset.Color)
	m:SetAttribute("SpinjitzuHighlight", preset.Highlight)
	CollectionService:AddTag(m, "SpinjitzuNPC")
	m.Parent = workspace
	return m
end

-- slide spinning ninja to target spots (server-anchored so everyone sees the same path)
local function spinTo(roots, targets, dur)
	local from = {}
	for i in pairs(targets) do
		local root = roots[i]
		if root and root.Parent then
			root.Anchored = true
			from[i] = root.Position
		end
	end
	local t0 = os.clock()
	while true do
		local f = math.min((os.clock() - t0) / dur, 1)
		local e = f * f * (3 - 2 * f)
		for i, p0 in pairs(from) do
			local root = roots[i]
			if root.Parent then root.CFrame = CFrame.new(p0:Lerp(targets[i], e)) * root.CFrame.Rotation end
		end
		if f >= 1 then break end
		RunService.Heartbeat:Wait()
	end
end

-- members: characters in spin order (Fire, Earth, Lightning, Ice)
function Creation.run(members)
	for _, ch in ipairs(members) do Creation.busy[ch] = true end
	local roots, saved = {}, {}
	local sum = Vector3.zero
	for i, ch in ipairs(members) do
		local root = ch:FindFirstChild("HumanoidRootPart")
		roots[i] = root
		saved[i] = { cf = root.CFrame, anchored = root.Anchored, bot = CollectionService:HasTag(ch, "SpinjitzuNPC") }
		sum += root.Position
		-- fresh start, so everyone's tornado appears in turn
		if ch:GetAttribute("SpinjitzuActive") then ch:SetAttribute("SpinjitzuActive", false) end
	end
	local center = sum / #members
	local groundY = groundBelow(center, members)
	task.wait(0.3)

	-- 1) Spinjitzu one after another: Fire, Earth, Lightning, Ice
	for i, ch in ipairs(members) do
		local el = Config.CreationElements[i]
		local preset = Config.Presets[el] or {}
		ch:SetAttribute("SpinjitzuElement", el)
		ch:SetAttribute("SpinjitzuColor", preset.Color)
		ch:SetAttribute("SpinjitzuHighlight", preset.Highlight)
		ch:SetAttribute("CreationPhase", "spin")
		ch:SetAttribute("SpinjitzuActive", true)
		task.wait(Config.CreationStagger or 0.8)
	end
	task.wait(0.5)

	-- 2) the four tornadoes spiral into each other, hopping up as they meet
	local gather = Config.CreationGatherTime or 1.2
	local startOff = {}
	for i, root in ipairs(roots) do
		if root.Parent then
			root.Anchored = true
			local off = root.Position - center
			startOff[i] = { a = math.atan2(off.Z, off.X), r = Vector3.new(off.X, 0, off.Z).Magnitude, y = root.Position.Y }
		end
	end
	local t0 = os.clock()
	while true do
		local f = math.min((os.clock() - t0) / gather, 1)
		local e = f * f * (3 - 2 * f)
		for i, root in ipairs(roots) do
			local o = startOff[i]
			if o and root.Parent then
				local a = o.a + e * math.pi * 1.5
				local r = o.r * (1 - e)
				local y = o.y + math.sin(math.pi * f) * 4
				root.CFrame = CFrame.new(center.X + math.cos(a) * r, y, center.Z + math.sin(a) * r) * root.CFrame.Rotation
			end
		end
		if f >= 1 then break end
		RunService.Heartbeat:Wait()
	end

	-- 3) merge into one huge tornado (the ninja are hidden inside)
	local anchor = makeAnchor(center, groundY)
	for _, ch in ipairs(members) do
		ch:SetAttribute("CreationPhase", "inside")
		ch:SetAttribute("SpinjitzuActive", false)
	end
	task.wait(0.1)
	anchor:SetAttribute("SpinjitzuActive", true)

	-- a random player in it steers it (slowly); it hurts + throws whoever it touches
	local pilots = {}
	for _, ch in ipairs(members) do
		local p = Players:GetPlayerFromCharacter(ch)
		if p then table.insert(pilots, p) end
	end
	local pilot = #pilots > 0 and pilots[math.random(#pilots)] or nil
	local st = { move = Vector3.zero }
	if pilot then
		piloting[pilot.Character] = st
		anchor:SetAttribute("Pilot", pilot.UserId)
		for _, p in ipairs(pilots) do
			notify(p, p == pilot and "You're steering the Tornado of Creation: walk to move it"
				or (pilot.DisplayName .. " is steering the Tornado of Creation"))
		end
	end
	local ignore = table.clone(members)
	table.insert(ignore, anchor)
	local aRoot = anchor:FindFirstChild("HumanoidRootPart")
	local anchorUp = aRoot.Position.Y - groundY
	local memberUp = {}
	for i, root in ipairs(roots) do memberUp[i] = root.Position.Y - groundY end
	local t0, hitT = os.clock(), 0
	local hitAt = {}
	while os.clock() - t0 < (Config.CreationTime or 10) do
		local dt = RunService.Heartbeat:Wait()
		if pilot then
			if st.move.Magnitude > 0.05 then
				center += st.move * (Config.CreationMoveSpeed or 7) * dt
				groundY = groundBelow(center, ignore)
				anchor:PivotTo(CFrame.new(center.X, groundY + anchorUp, center.Z) * aRoot.CFrame.Rotation)
				for i, root in ipairs(roots) do
					if root.Parent then root.CFrame = CFrame.new(center.X, groundY + memberUp[i], center.Z) * root.CFrame.Rotation end
				end
			end
			hitT -= dt
			if hitT <= 0 then
				hitT = 0.25
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = ignore
				local now, done = os.clock(), {}
				local pos = Vector3.new(center.X, groundY + 3, center.Z)
				for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, Config.CreationRadius or 14, params)) do
					local model = part:FindFirstAncestorOfClass("Model")
					if model and not done[model] and model:FindFirstChildOfClass("Humanoid") then
						done[model] = true
						if model:GetAttribute("Shatterspin") then
							require(script.Parent:WaitForChild("Shatterspin")).stop(model, true)
						end
						local hum = Status.target(model, members[1])
						local tRoot = model:FindFirstChild("HumanoidRootPart")
						if hum and tRoot and now - (hitAt[model] or 0) >= 0.5 then
							hitAt[model] = now
							local dmg = Config.CreationDamage or 12
							hum:TakeDamage(dmg)
							model:SetAttribute("LastHit", now)
							HitEffects.show(HIT, tRoot, model, dmg, false)
							Status.blast(model, pos, 75)
						end
					end
				end
			end
		end
	end
	if pilot then piloting[pilot.Character] = nil end

	-- 4) it winds down; each ninja Spinjitzus out of it to a spot nearby and stops there
	anchor:SetAttribute("SpinjitzuActive", false)
	local rng = Random.new()
	local targets = {}
	for i, ch in ipairs(members) do
		ch:SetAttribute("CreationPhase", nil)
		ch:SetAttribute("SpinjitzuActive", true)
		local a = (i - 1) / #members * TAU + math.pi / 4 + rng:NextNumber(-0.45, 0.45)
		local r = rng:NextNumber(13, 20)
		targets[i] = Vector3.new(center.X + math.cos(a) * r, groundY + memberUp[i], center.Z + math.sin(a) * r)
	end
	task.wait(0.45)
	spinTo(roots, targets, 1.4)
	for i, ch in ipairs(members) do
		ch:SetAttribute("SpinjitzuActive", false)
		local root, s = roots[i], saved[i]
		if root.Parent and not s.bot then root.Anchored = s.anchored end
	end
	task.delay(3, function() anchor:Destroy() end)

	-- demo bots Spinjitzu back to where they started, ready for the next loop
	local back = {}
	for i, s in ipairs(saved) do
		if s.bot then back[i] = s.cf.Position end
	end
	if next(back) then
		task.wait(2.5)
		for i in pairs(back) do members[i]:SetAttribute("SpinjitzuActive", true) end
		task.wait(0.45)
		spinTo(roots, back, 1.2)
		for i in pairs(back) do
			members[i]:SetAttribute("SpinjitzuActive", false)
			if roots[i].Parent then roots[i].CFrame = saved[i].cf end
		end
	end
	for _, ch in ipairs(members) do Creation.busy[ch] = nil end
end

return Creation
