-- DragonMergeServer v1.1  (ModuleScript in ServerScriptService)
-- Runs Rising Dragon merges (the shared maths + what a merge is: ReplicatedStorage.DragonMerge).
--   request(character)  the merge key (G) on the dragon: with at least 3 dragons close together
--                       (you + other riders + your dragon crew, up to 6) you all merge: swoop
--                       into a ring, fly straight up while the spin builds, then off where the
--                       leader looks. In a merge, the key breaks you away (fewer than 3 left =
--                       it falls apart)
--   steer(character, v) the leader (whoever started it) steers with their camera
-- It flies on until it crashes into something: a huge blast that hurts everyone round it (and
-- breaks Shatterspin), then everyone lands. Also: the dragon crew (bots you pick from the menu
-- that do the Rising Dragon with you, so you can merge on your own).
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
local crew = {} -- [bot] = { owner, slot, home (CFrame), mode, t, from }: the dragon crew (see below)
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
		if crew[character] then crew[character].mode = "fly" end
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
	local heading = flat(lroot.CFrame.LookVector, Vector3.new(0, 0, -1))
	local now = workspace:GetServerTimeNow()
	-- (first it flies straight up, the ring flat, while the spin builds)
	cfg:SetAttribute("Center", center)
	cfg:SetAttribute("Dir", Vector3.yAxis)
	cfg:SetAttribute("Axis", heading)
	cfg:SetAttribute("Angle", 0)
	cfg:SetAttribute("Spin", 0)
	cfg:SetAttribute("Speed", Config.MergeRiseSpeed or 30)
	cfg:SetAttribute("Stamp", now)
	cfg:SetAttribute("Leader", leader.UserId)
	local g = { members = members, want = heading, born = os.clock() }
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
	for i = 1, math.min(Merge.Max - 1, #near) do table.insert(members, near[i][1]) end
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
		elseif os.clock() - g.born > (Config.MergeTime or 17) then
			burst(cfg:GetAttribute("Center"), colorsOf(g.members), 20)
			disband(cfg, "end")
		else
			-- straight up while the spin builds, then on, turning toward where the leader looks
			local age = os.clock() - g.born
			local rising = age < (Config.MergeRiseTime or 2.2)
			local build = math.clamp((age - Merge.FormTime * 0.5) / 1.6, 0, 1)
			local spin = Merge.Spin * build * build * (3 - 2 * build)
			local speed = rising and (Config.MergeRiseSpeed or 30)
				or math.min(Config.MergeSpeed or 80, (cfg:GetAttribute("Speed") or 30) + 90 * dt)
			local center, dir = cfg:GetAttribute("Center"), cfg:GetAttribute("Dir")
			local want = rising and Vector3.yAxis or g.want
			local angleTo = math.acos(math.clamp(dir:Dot(want), -1, 1))
			if angleTo > 1e-3 then
				local step = math.min(1, (Config.MergeTurn or 1.8) * dt / angleTo)
				dir = dir:Lerp(want, step)
				dir = dir.Magnitude > 1e-3 and dir.Unit or want
			end
			local axis = Merge.axisFor(dir, cfg:GetAttribute("Axis"))
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
				cfg:SetAttribute("Axis", axis)
				cfg:SetAttribute("Spin", spin)
				cfg:SetAttribute("Speed", speed)
				cfg:SetAttribute("Angle", (cfg:GetAttribute("Angle") or 0) + spin * dt)
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
-- the dragon crew: bots you pick (up to 5) to merge with on your own. They stand spread out round
-- you; when you do the Rising Dragon each does its own (Spinjitzu -> rises up on its dragon, a
-- moment apart), then they fly with you in a V; when you land they dive back to their spots
----------------------------------------------------------------------------------------

local ELEMENTS = { Fire = true, Lightning = true, Ice = true, Water = true, Earth = true, Energy = true }

function Server.removeCrew(player)
	for _, bot in ipairs(CollectionService:GetTagged("DragonCrew")) do
		if bot:GetAttribute("CrewOwner") == player.UserId then
			if inGroup[bot] then
				local g = groups[inGroup[bot]]
				if g then table.remove(g.members, table.find(g.members, bot) or 0) end
				release(bot, "away")
			end
			crew[bot] = nil
			bot:Destroy()
		end
	end
end

-- elements: a list like { "Fire", "Lightning" }
function Server.spawnCrew(player, elements)
	local root = player.Character and rootOf(player.Character)
	if not root then return 0 end
	Server.removeCrew(player)
	local picks = {}
	for _, el in ipairs(elements) do
		if ELEMENTS[el] and #picks < Merge.Max - 1 then table.insert(picks, el) end
	end
	-- spread round behind you, well apart
	local look = flat(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local base = math.atan2(look.Z, look.X) + math.pi
	for i, el in ipairs(picks) do
		local a = base + ((i - 0.5) / #picks - 0.5) * math.pi * 1.25
		local pos = root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 24
		local bot = Bots.make(el, pos, "DragonCrew_" .. el, root.Position)
		bot:FindFirstChildOfClass("Humanoid").DisplayName = el .. " (dragon crew)"
		bot:SetAttribute("CrewOwner", player.UserId)
		bot:SetAttribute("ServerFlight", true) -- (clients don't fly it round its demo loop)
		CollectionService:AddTag(bot, "DragonCrew")
		crew[bot] = { owner = player, slot = i, home = rootOf(bot).CFrame, mode = "idle", t = 0 }
	end
	return #picks
end

local FLY_PITCH = math.rad(75)
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

RunService.Heartbeat:Connect(function(dt)
	for bot, st in pairs(crew) do
		local root = rootOf(bot)
		local oroot = st.owner.Parent and st.owner.Character and rootOf(st.owner.Character)
		if not bot.Parent or not root then
			crew[bot] = nil
		elseif oroot and not inGroup[bot] then
			local ophase = st.owner.Character:GetAttribute("DragonPhase")
			local riding = ophase == "spin" or ophase == "rise" or ophase == "fly" or ophase == "merge"
			local heading = flat(oroot.CFrame.LookVector, Vector3.new(0, 0, -1))
			if ophase == "fly" then heading = flat(oroot.AssemblyLinearVelocity, heading) end
			st.t += dt
			if st.mode == "idle" then
				if riding then st.mode, st.t, st.wait = "wait", 0, 0.2 + math.random() * 1.4 end
			elseif st.mode == "wait" then
				if not riding then
					st.mode = "idle"
				elseif st.t >= st.wait then
					st.mode, st.t = "spin", 0
					bot:SetAttribute("DragonPhase", "spin")
					bot:SetAttribute("SpinjitzuActive", true)
				end
			elseif st.mode == "spin" then
				if st.t >= (Config.DragonSpinTime or 2) then
					st.mode, st.t, st.from = "rise", 0, root.Position
					bot:SetAttribute("DragonPhase", "rise")
					bot:SetAttribute("SpinjitzuActive", false)
				end
			elseif st.mode == "rise" then
				local f = math.clamp(st.t / (Config.DragonRiseTime or 3), 0, 1)
				local pos = st.from + Vector3.yAxis * (Config.DragonRiseHeight or 35) * (1 - (1 - f) ^ 2)
				root.CFrame = CFrame.lookAt(pos, pos + heading)
				if f >= 1 then
					st.mode, st.t = "fly", 0
					bot:SetAttribute("DragonPhase", "fly")
				end
			elseif st.mode == "fly" then
				if not riding then
					st.mode, st.t, st.from = "land", 0, root.CFrame
				else
					-- a V behind you
					local side = st.slot % 2 == 1 and 1 or -1
					local rank = math.ceil(st.slot / 2)
					local right = heading:Cross(Vector3.yAxis)
					local want = oroot.Position + right * side * 14 * rank - heading * 8 * rank + Vector3.new(0, 2 * rank, 0)
					local pos = root.Position:Lerp(want, 1 - math.exp(-dt * 4))
					local moving = ophase == "fly" and math.clamp(oroot.AssemblyLinearVelocity.Magnitude / 30, 0, 1) or 0
					root.CFrame = CFrame.lookAt(pos, pos + heading) * CFrame.Angles(-FLY_PITCH * moving, 0, 0)
				end
			elseif st.mode == "land" then
				-- dive back down to its spot, then the landing
				local f = smooth(st.t / 0.8)
				root.CFrame = st.from:Lerp(st.home, f)
				if f >= 1 then
					st.mode = "idle"
					bot:SetAttribute("DragonPhase", nil)
					bot:SetAttribute("DragonLanded", (bot:GetAttribute("DragonLanded") or 0) + 1)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	Server.removeCrew(player)
end)

return Server
