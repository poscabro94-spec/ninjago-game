-- DragonMergeServer v1.0  (ModuleScript in ServerScriptService)
-- Runs Rising Dragon merges (the shared maths + what a merge is: ReplicatedStorage.DragonMerge).
--   request(character)  the merge key (G) on the dragon: with at least 3 dragons close together
--                       (you + other riders + your dragon crew) you all merge; in a merge, the
--                       key breaks you away (fewer than 3 left = it falls apart)
--   steer(character, v) the leader (whoever started it) steers with their camera
-- It flies on until it crashes into something: a huge blast that hurts everyone round it (and
-- breaks Shatterspin), then everyone lands. Also: the dragon crew (two bots that ride dragons
-- with you, to try merging on your own), spawned from the menu.
-- SpinjitzuServer sets onEnd (land) and onBreakAway (a few more seconds of flight).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local Merge = require(ReplicatedStorage:WaitForChild("DragonMerge"))
local Status = require(script.Parent:WaitForChild("StatusEffects"))
local Shatter = require(script.Parent:WaitForChild("Shatterspin"))
local Bots = require(script.Parent:WaitForChild("SpinjitzuBots"))

local Server = {}
Server.onEnd = nil       -- function(character): a player's merge ended (crashed / ran out): land
Server.onBreakAway = nil -- function(character): a player left the merge: back to flying

local folder = ReplicatedStorage:FindFirstChild("DragonMerges") or Instance.new("Folder")
folder.Name = "DragonMerges"
folder.Parent = ReplicatedStorage

local groups = {} -- [cfg] = { members = { character }, want = Vector3, born = os.clock() }
local inGroup = {} -- [character] = cfg
local nextId = 0

local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function riding(character)
	local phase = character:GetAttribute("DragonPhase")
	return (phase == "rise" or phase == "fly") and not inGroup[character]
end

local function flat(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.05 and f.Unit or fallback
end

-- a flash + rings in the members' colours
local function burst(pos, colors, size)
	local function part(shape, sz, col, alpha)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Material = Enum.Material.Neon
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size, p.Color, p.Transparency = sz, col, alpha
		p.Parent = workspace
		Debris:AddItem(p, 1.2)
		return p
	end
	local ball = part(Enum.PartType.Ball, Vector3.one * 4, Color3.new(1, 1, 1), 0)
	ball.CFrame = CFrame.new(pos)
	TweenService:Create(ball, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1 }):Play()
	for i, col in ipairs(colors) do
		local ring = part(Enum.PartType.Cylinder, Vector3.new(0.4, 4, 4), col, 0.1)
		ring.CFrame = CFrame.new(pos) * CFrame.Angles(i * 1.3, i * 0.7, math.pi / 2)
		TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.4, size * 2.2, size * 2.2), Transparency = 1 }):Play()
	end
end

local function colorsOf(members)
	local list = {}
	for _, m in ipairs(members) do table.insert(list, m:GetAttribute("SpinjitzuColor") or Color3.new(1, 1, 1)) end
	return list
end

local function writeMembers(cfg, g)
	for _, v in ipairs(cfg:GetChildren()) do v:Destroy() end
	for i, m in ipairs(g.members) do
		local v = Instance.new("ObjectValue")
		v.Name = "Member"
		v.Value = m
		v:SetAttribute("Slot", i)
		v.Parent = cfg
		m:SetAttribute("MergeSlot", i)
	end
	cfg:SetAttribute("Count", #g.members)
end

-- take one dragon out of its merge (it keeps flying on its own)
local function release(character, reason)
	local cfg = inGroup[character]
	inGroup[character] = nil
	for _, name in ipairs({ "MergeId", "MergeSlot", "MergeFrom", "MergeAt" }) do character:SetAttribute(name, nil) end
	local root = rootOf(character)
	if root and character.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if not character.Parent or character:GetAttribute("DragonPhase") ~= "merge" then return cfg end
	if Players:GetPlayerFromCharacter(character) then
		if reason == "end" and Server.onEnd then
			Server.onEnd(character)
		elseif Server.onBreakAway then
			Server.onBreakAway(character)
		end
	else
		character:SetAttribute("DragonPhase", "fly") -- (crew bots: back to following you)
		if root then root.Anchored = true end
	end
	return cfg
end

local function disband(cfg, reason)
	local g = groups[cfg]
	if not g then return end
	groups[cfg] = nil
	for _, m in ipairs(g.members) do release(m, reason) end
	cfg:Destroy()
end

local function leaderOf(g)
	for _, m in ipairs(g.members) do
		local p = Players:GetPlayerFromCharacter(m)
		if p then return p end
	end
	return nil
end

local function form(members, leader)
	nextId += 1
	local cfg = Instance.new("Configuration")
	cfg.Name = "Merge" .. nextId
	local center = Vector3.zero
	for _, m in ipairs(members) do center += rootOf(m).Position end
	center /= #members
	local lroot = rootOf(leader.Character)
	local dir = flat(lroot.CFrame.LookVector, Vector3.new(0, 0, -1))
	local now = workspace:GetServerTimeNow()
	cfg:SetAttribute("Center", center)
	cfg:SetAttribute("Dir", dir)
	cfg:SetAttribute("Angle", 0)
	cfg:SetAttribute("Spin", Merge.Spin)
	cfg:SetAttribute("Speed", Config.MergeSpeed or 80)
	cfg:SetAttribute("Stamp", now)
	cfg:SetAttribute("Leader", leader.UserId)
	local g = { members = members, want = dir, born = os.clock() }
	writeMembers(cfg, g)
	for _, m in ipairs(members) do
		local root = rootOf(m)
		inGroup[m] = cfg
		m:SetAttribute("DragonToken", (m:GetAttribute("DragonToken") or 0) + 1) -- (its own flight timer stops)
		m:SetAttribute("DragonEnds", nil)
		m:SetAttribute("MergeId", nextId)
		m:SetAttribute("MergeFrom", root.CFrame)
		m:SetAttribute("MergeAt", now)
		m:SetAttribute("DragonPhase", "merge")
		Shatter.unlock(m)
		root.Anchored = true
	end
	groups[cfg] = g
	cfg.Parent = folder
	burst(center, colorsOf(members), 16)
end

-- the merge key
function Server.request(character)
	local player = Players:GetPlayerFromCharacter(character)
	local cfg = inGroup[character]
	if cfg then
		local g = groups[cfg]
		if not g then return nil end
		table.remove(g.members, table.find(g.members, character) or 0)
		release(character, "away")
		if #g.members < 3 or not leaderOf(g) then
			disband(cfg, "away")
		else
			cfg:SetAttribute("Leader", leaderOf(g).UserId)
			writeMembers(cfg, g)
		end
		return nil
	end
	local root = rootOf(character)
	if not player or not root or not riding(character) then return nil end
	-- everyone on a dragon close by (nearest first), up to 4 with you
	local near = {}
	local function consider(m)
		local r = rootOf(m)
		local hum = m:FindFirstChildOfClass("Humanoid")
		if m ~= character and r and hum and hum.Health > 0 and riding(m)
			and (r.Position - root.Position).Magnitude <= (Config.MergeRange or 60) then
			table.insert(near, { m, (r.Position - root.Position).Magnitude })
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then consider(p.Character) end
	end
	for _, bot in ipairs(CollectionService:GetTagged("DragonCrew")) do consider(bot) end
	table.sort(near, function(a, b) return a[2] < b[2] end)
	if #near < 2 then
		return ("Merge: you need 3 dragons close together (%d here)"):format(#near + 1)
	end
	local members = { character }
	for i = 1, math.min(3, #near) do table.insert(members, near[i][1]) end
	form(members, player)
	return nil
end

function Server.steer(character, v)
	local cfg = inGroup[character]
	local g = cfg and groups[cfg]
	local player = Players:GetPlayerFromCharacter(character)
	if g and player and cfg:GetAttribute("Leader") == player.UserId and typeof(v) == "Vector3" and v.Magnitude > 0.1
		and v.Magnitude < 2 then
		g.want = v.Unit
	end
end

-- crashed into something at pos
local function crash(cfg, g, pos)
	local colors = colorsOf(g.members)
	burst(pos, colors, 34)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = g.members
	local done = {}
	local attacker = g.members[1]
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, Config.MergeBlastRadius or 22, params)) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not done[model] and model:FindFirstChildOfClass("Humanoid") then
			done[model] = true
			if Shatter.isOn(model) then Shatter.stop(model, true) end -- (it breaks Shatterspin too)
			local hum = Status.target(model, attacker)
			if hum then
				hum:TakeDamage(Config.MergeDamage or 70)
				model:SetAttribute("LastHit", os.clock())
				Status.blast(model, pos, 120)
			end
		end
	end
	disband(cfg, "end")
end

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	for cfg, g in pairs(groups) do
		-- anyone gone / dead / off their dragon drops out
		for i = #g.members, 1, -1 do
			local m = g.members[i]
			local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 or m:GetAttribute("DragonPhase") ~= "merge" then
				table.remove(g.members, i)
				release(m, "away")
			end
		end
		if #g.members < 3 or not leaderOf(g) then
			disband(cfg, "away")
		elseif os.clock() - g.born > (Config.MergeTime or 15) then
			burst(cfg:GetAttribute("Center"), colorsOf(g.members), 20)
			disband(cfg, "end")
		else
			-- fly on, turning toward where the leader looks
			local center, dir = cfg:GetAttribute("Center"), cfg:GetAttribute("Dir")
			local speed = cfg:GetAttribute("Speed")
			local angleTo = math.acos(math.clamp(dir:Dot(g.want), -1, 1))
			if angleTo > 1e-3 then
				local step = math.min(1, (Config.MergeTurn or 1.8) * dt / angleTo)
				dir = dir:Lerp(g.want, step).Unit
			end
			-- crashed into something?
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local ignore = table.clone(g.members)
			local fx = workspace:FindFirstChild("SpinjitzuFX")
			if fx then table.insert(ignore, fx) end
			params.FilterDescendantsInstances = ignore
			local hit = os.clock() - g.born > 0.6 -- (not while it's still forming)
				and workspace:Spherecast(center, Merge.Radius * 0.8, dir * (speed * dt + 1.5), params)
			local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
			if hit and (hit.Instance.CanCollide or (model and model:FindFirstChildOfClass("Humanoid"))) then
				crash(cfg, g, hit.Position)
			else
				center += dir * speed * dt
				cfg:SetAttribute("Center", center)
				cfg:SetAttribute("Dir", dir)
				cfg:SetAttribute("Angle", (cfg:GetAttribute("Angle") or 0) + Merge.Spin * dt)
				cfg:SetAttribute("Stamp", now)
				-- the server puts everyone in place too (clients draw it smoothly themselves)
				for i, m in ipairs(g.members) do
					local root = rootOf(m)
					local cf = root and Merge.memberCF(cfg, m, i, #g.members, now)
					if cf then root.CFrame = cf end
				end
			end
		end
	end
end)

----------------------------------------------------------------------------------------
-- the dragon crew: two bots on dragons that fly with you (to merge on your own)
----------------------------------------------------------------------------------------

local CREW_ELEMENTS = { "Fire", "Lightning", "Ice", "Water", "Earth", "Energy" }

function Server.removeCrew(player)
	for _, bot in ipairs(CollectionService:GetTagged("DragonCrew")) do
		if bot:GetAttribute("CrewOwner") == player.UserId then
			if inGroup[bot] then
				local cfg = inGroup[bot]
				local g = groups[cfg]
				if g then table.remove(g.members, table.find(g.members, bot) or 0) end
				release(bot, "away")
			end
			bot:Destroy()
		end
	end
end

function Server.spawnCrew(player)
	local character = player.Character
	local root = rootOf(character)
	if not root then return end
	Server.removeCrew(player)
	local mine = player:GetAttribute("SpinjitzuElement") or Config.Element
	local picks = {}
	for _, el in ipairs(CREW_ELEMENTS) do
		if el ~= mine and #picks < 2 then table.insert(picks, el) end
	end
	for i, el in ipairs(picks) do
		local side = i == 1 and 1 or -1
		local bot = Bots.make(el, root.Position + root.CFrame.RightVector * side * 8 - root.CFrame.LookVector * 4,
			"DragonCrew_" .. el, root.Position + root.CFrame.LookVector * 20)
		bot:FindFirstChildOfClass("Humanoid").DisplayName = el .. " (dragon crew)"
		bot:SetAttribute("CrewOwner", player.UserId)
		bot:SetAttribute("CrewSide", side)
		bot:SetAttribute("ServerFlight", true) -- (clients don't fly it round its demo loop)
		CollectionService:AddTag(bot, "DragonCrew")
	end
end

-- crew bots follow their owner: on a dragon beside + behind you while you're riding, standing next
-- to you otherwise
local FLY_PITCH = math.rad(75)
RunService.Heartbeat:Connect(function(dt)
	for _, bot in ipairs(CollectionService:GetTagged("DragonCrew")) do
		local owner = Players:GetPlayerByUserId(bot:GetAttribute("CrewOwner") or 0)
		local oroot = owner and rootOf(owner.Character)
		local root = rootOf(bot)
		if not owner or not bot.Parent then
			if bot.Parent then bot:Destroy() end
		elseif root and oroot and not inGroup[bot] then
			local phase = owner.Character:GetAttribute("DragonPhase")
			local side = bot:GetAttribute("CrewSide") or 1
			local heading = flat(oroot.CFrame.LookVector, Vector3.new(0, 0, -1))
			if phase == "fly" or phase == "rise" or phase == "merge" then
				local flying = phase == "fly"
				if flying then heading = flat(oroot.AssemblyLinearVelocity, heading) end
				if bot:GetAttribute("DragonPhase") ~= "fly" then
					bot:SetAttribute("DragonPhase", "fly")
				end
				local right = heading:Cross(Vector3.yAxis)
				local want = oroot.Position + right * side * 13 - heading * 7 + Vector3.new(0, 1.5, 0)
				local pos = root.Position:Lerp(want, 1 - math.exp(-dt * 5))
				local tip = flying and FLY_PITCH * math.clamp(oroot.AssemblyLinearVelocity.Magnitude / 30, 0, 1) or 0
				root.CFrame = CFrame.lookAt(pos, pos + heading) * CFrame.Angles(-tip, 0, 0)
			else
				if bot:GetAttribute("DragonPhase") then bot:SetAttribute("DragonPhase", nil) end
				local right = heading:Cross(Vector3.yAxis)
				local want = oroot.Position + right * side * 6 - heading * 3
				if (root.Position - want).Magnitude > 4 then
					local pos = root.Position:Lerp(want, 1 - math.exp(-dt * 3))
					root.CFrame = CFrame.lookAt(pos, pos + heading)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	Server.removeCrew(player)
end)

return Server
