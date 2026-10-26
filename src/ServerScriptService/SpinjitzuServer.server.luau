-- SpinjitzuServer v7.0  (Script in ServerScriptService)
-- Toggles Spinjitzu on the character (every client renders it), handles element
-- switching (E), the speed boost, and the Dragon move (R): spin -> rise straight up -> free flight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local Creation = require(script.Parent:WaitForChild("SpinjitzuCreation"))

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

-- Dragon: "spin" (Spinjitzu) -> "rise" (dragon appears, straight up) -> "fly" (free); R again ends it
local function endDragon(character)
	character:SetAttribute("DragonToken", (character:GetAttribute("DragonToken") or 0) + 1)
	character:SetAttribute("DragonPhase", nil)
	character:SetAttribute("SpinjitzuActive", false)
end

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

	if action == "dragon" then
		if character:GetAttribute("DragonPhase") then
			endDragon(character)
		else
			startDragon(player, character, humanoid)
		end
		return
	end

	-- plain Spinjitzu toggle (ignored while the dragon is out)
	if character:GetAttribute("DragonPhase") then return end
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
		end)
	end
end

local function onPlayer(player)
	if player.Character then task.spawn(onCharacter, player.Character) end
	player.CharacterAdded:Connect(onCharacter)
end

for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)
