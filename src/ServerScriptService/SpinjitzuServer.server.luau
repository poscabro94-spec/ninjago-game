-- SpinjitzuServer v8.0  (Script in ServerScriptService)
-- Toggles Spinjitzu on the character (every client renders it), handles element
-- switching (E), the speed boost, Shatterspin (X, see Shatterspin) and the Dragon move (R):
-- spin -> rise straight up -> DragonFlyTime seconds of flight -> land (R again lands early).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local Creation = require(script.Parent:WaitForChild("SpinjitzuCreation"))
local Shatter = require(script.Parent:WaitForChild("Shatterspin"))

local remote = ReplicatedStorage:FindFirstChild("SpinjitzuToggle")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SpinjitzuToggle"
	remote.Parent = ReplicatedStorage
end

local function elementOf(player)
	local e = player:GetAttribute("SpinjitzuElement")
	if e and Config.Presets[e] then return e end
	return Config.Element
end

-- copy the player's element look onto the character (clients read these)
local function applyLook(player, character)
	local name = elementOf(player)
	local preset = Config.Presets[name] or {}
	character:SetAttribute("SpinjitzuElement", name)
	-- per-player overrides: player:SetAttribute("SpinjitzuColor", Color3.fromRGB(...))
	character:SetAttribute("SpinjitzuHighlight", player:GetAttribute("SpinjitzuHighlight") or preset.Highlight or Config.HighlightColor)
	character:SetAttribute("SpinjitzuColor", player:GetAttribute("SpinjitzuColor") or preset.Color or Config.Color)
end

local function restoreSpeed(character, humanoid)
	local base = character:GetAttribute("SpinjitzuBaseSpeed")
	if base then humanoid.WalkSpeed = base end
	character:SetAttribute("SpinjitzuBaseSpeed", nil)
end

-- Dragon: "spin" (Spinjitzu) -> "rise" (dragon appears, straight up) -> "fly" -> "land" (you dive
-- to the floor; your client says "landed" when you hit it, everyone plays the landing)
local function endDragon(character)
	character:SetAttribute("DragonToken", (character:GetAttribute("DragonToken") or 0) + 1)
	character:SetAttribute("DragonPhase", nil)
	character:SetAttribute("DragonEnds", nil)
	character:SetAttribute("SpinjitzuActive", false)
	Shatter.unlock(character)
end

local function landed(character)
	if character:GetAttribute("DragonPhase") ~= "land" then return end
	endDragon(character)
	character:SetAttribute("DragonLanded", (character:GetAttribute("DragonLanded") or 0) + 1)
end

local function land(character)
	local phase = character:GetAttribute("DragonPhase")
	if phase ~= "rise" and phase ~= "fly" then return end
	local token = character:GetAttribute("DragonToken")
	character:SetAttribute("DragonPhase", "land")
	character:SetAttribute("DragonEnds", nil)
	Shatter.unlock(character)
	-- (in case the client never says it landed)
	task.delay(4, function()
		if character:GetAttribute("DragonToken") == token then landed(character) end
	end)
end

-- flew into a Shatterspinner you were locked onto: you land
Shatter.onCounter = function(rider) land(rider) end

local function startDragon(player, character, humanoid)
	applyLook(player, character)
	restoreSpeed(character, humanoid)
	local token = (character:GetAttribute("DragonToken") or 0) + 1
	character:SetAttribute("DragonToken", token)
	character:SetAttribute("DragonPhase", "spin")
	character:SetAttribute("SpinjitzuActive", true)
	task.delay(Config.DragonSpinTime or 2, function()
		if character:GetAttribute("DragonToken") ~= token or character:GetAttribute("DragonPhase") ~= "spin" then return end
		character:SetAttribute("DragonPhase", "rise") -- set before ending the spin so clients skip the landing pose
		character:SetAttribute("SpinjitzuActive", false)
		task.delay(Config.DragonRiseTime or 3, function()
			if character:GetAttribute("DragonToken") ~= token or character:GetAttribute("DragonPhase") ~= "rise" then return end
			character:SetAttribute("DragonPhase", "fly")
			local flyTime = Config.DragonFlyTime or 6
			character:SetAttribute("DragonEnds", workspace:GetServerTimeNow() + flyTime)
			task.delay(flyTime, function()
				if character:GetAttribute("DragonToken") == token then land(character) end
			end)
		end)
	end)
end

remote.OnServerEvent:Connect(function(player, action)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if Creation.busy[character] then return end -- in the middle of a Tornado of Creation

	if action == "creation" then
		if character:GetAttribute("DragonPhase") then return end
		local order = Config.CreationElements
		if not table.find(order, elementOf(player)) then
			remote:FireClient(player, "notify", "Tornado of Creation: switch to Fire, Earth, Lightning or Ice (E)")
			return
		end
		-- the nearest free player for each element (you count for your own)
		local myRoot = character:FindFirstChild("HumanoidRootPart")
		local byElement = { [elementOf(player)] = character }
		for _, p in ipairs(Players:GetPlayers()) do
			local ch = p.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			local el = elementOf(p)
			if p ~= player and r and h and h.Health > 0 and not Creation.busy[ch] and not ch:GetAttribute("DragonPhase")
				and not byElement[el] and (r.Position - myRoot.Position).Magnitude <= (Config.CreationRange or 40) then
				byElement[el] = ch
			end
		end
		-- your own Creation crew bots (spawned from the menu) fill the gaps
		for _, bot in ipairs(CollectionService:GetTagged("CreationCrew")) do
			local r = bot:FindFirstChild("HumanoidRootPart")
			local el = bot:GetAttribute("CrewElement")
			if bot:GetAttribute("CrewOwner") == player.UserId and r and el and not byElement[el] and not Creation.busy[bot]
				and (r.Position - myRoot.Position).Magnitude <= (Config.CreationRange or 40) then
				byElement[el] = bot
			end
		end
		local members, missing = {}, {}
		for _, el in ipairs(order) do
			if byElement[el] then table.insert(members, byElement[el]) else table.insert(missing, el) end
		end
		if #missing > 0 then
			remote:FireClient(player, "notify", "Tornado of Creation needs nearby: " .. table.concat(missing, ", "))
			return
		end
		for _, ch in ipairs(members) do restoreSpeed(ch, ch:FindFirstChildOfClass("Humanoid")) end
		task.spawn(Creation.run, members)
		return
	end

	if action == "cycle" then
		local order = Config.ElementOrder or { Config.Element }
		local idx = table.find(order, elementOf(player)) or 0
		player:SetAttribute("SpinjitzuElement", order[idx % #order + 1])
		if character:GetAttribute("SpinjitzuActive") and not character:GetAttribute("DragonPhase") then
			applyLook(player, character)
		end
		return
	end

	if action == "landed" then
		landed(character)
		return
	end

	if action == "dragon" then
		local phase = character:GetAttribute("DragonPhase")
		if phase == "rise" or phase == "fly" then
			land(character)
		elseif phase == "spin" then
			endDragon(character)
		elseif not phase and not character:GetAttribute("Shatterspin") then
			startDragon(player, character, humanoid)
		end
		return
	end

	if action == "shatter" then
		if character:GetAttribute("DragonPhase") then return end
		if character:GetAttribute("Shatterspin") then
			Shatter.stop(character)
		else
			if character:GetAttribute("SpinjitzuActive") then -- (plain Spinjitzu off first)
				character:SetAttribute("SpinjitzuActive", false)
				restoreSpeed(character, humanoid)
			end
			local why = Shatter.start(character, humanoid)
			if why then remote:FireClient(player, "notify", why) end
		end
		return
	end

	-- plain Spinjitzu toggle (ignored while the dragon is out / Shatterspinning)
	if character:GetAttribute("DragonPhase") or character:GetAttribute("Shatterspin") then return end
	local turningOn = character:GetAttribute("SpinjitzuActive") ~= true
	if turningOn then applyLook(player, character) end
	character:SetAttribute("SpinjitzuActive", turningOn)

	-- speed boost while spinning
	local mult = Config.SpeedMultiplier or 1
	if turningOn then
		if character:GetAttribute("SpinjitzuBaseSpeed") == nil then
			character:SetAttribute("SpinjitzuBaseSpeed", humanoid.WalkSpeed)
		end
		humanoid.WalkSpeed = character:GetAttribute("SpinjitzuBaseSpeed") * mult
	else
		restoreSpeed(character, humanoid)
	end
end)

local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			endDragon(character)
			Shatter.stop(character)
		end)
	end
end

local function onPlayer(player)
	if player.Character then task.spawn(onCharacter, player.Character) end
	player.CharacterAdded:Connect(onCharacter)
end

for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)
