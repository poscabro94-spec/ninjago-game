-- NinjaMenuServer v1.3  (Script in ServerScriptService)
-- What the menu (NinjaMenu) asks for:
--   "character", name  -> become that ninja (element + look), "You" = back to your own avatar
--   "weapon", kind     -> add / remove that Golden Weapon ("All", "None" too). The list is the
--                         player attribute GoldenWeapons ("Sword,Scythe" / "None"; unset = your
--                         character's own); GoldenWeaponsServer hands them out
--   "bots", "creation" -> the other three Tornado of Creation ninja as bots around you
--   "bots", "dummy" / "dummyInf" -> a training dummy (normal / infinite HP) in front of you
--   "bots", "shatter"  -> a bot Shatterspinning in a circle in front of you (practise the counter)
--   "bots", "remove"   -> your bots and dummies go away
-- Your look stays when you respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Roster = require(ReplicatedStorage:WaitForChild("NinjaRoster"))
local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local Bots = require(script.Parent:WaitForChild("SpinjitzuBots"))
local Creation = require(script.Parent:WaitForChild("SpinjitzuCreation"))
local TrainingDummy = require(script.Parent:WaitForChild("TrainingDummy"))
local MAX_DUMMIES = 8
local WEAPON_KINDS = { "Sword", "Scythe", "Nunchucks", "Shurikens" }

local remote = ReplicatedStorage:FindFirstChild("NinjaMenu")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "NinjaMenu"
	remote.Parent = ReplicatedStorage
end

local ACCESSORY_SLOTS = {
	"HatAccessory", "HairAccessory", "FaceAccessory", "NeckAccessory",
	"ShouldersAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory",
}

local originals = {} -- [player] = their own avatar's HumanoidDescription
local pending = {}   -- [player] = true while a look is being applied (false/true = run again)

-- the description for the player's current pick (nil = their own avatar)
local function describe(player)
	local base = originals[player]
	if not base then return nil end
	local ninja = Roster.find(player:GetAttribute("Ninja") or "")
	local d = base:Clone()
	if ninja then
		d.Shirt, d.Pants, d.GraphicTShirt = ninja.Shirt or 0, ninja.Pants or 0, 0
		pcall(function() d:SetAccessories({}, true) end)
		for _, slot in ipairs(ACCESSORY_SLOTS) do d[slot] = "" end
		d.HatAccessory = ninja.Accessories or ""
		d.HeadColor = Roster.SkinColor
		d.TorsoColor = ninja.Color
		d.LeftArmColor, d.RightArmColor = ninja.Color, ninja.Color
		d.LeftLegColor, d.RightLegColor = ninja.LegColor or ninja.Color, ninja.LegColor or ninja.Color
	end
	return d
end

-- ApplyDescription takes a moment: clicks while it runs just apply the newest pick after it
local function applyLook(player)
	if pending[player] ~= nil then
		pending[player] = true
		return
	end
	pending[player] = false
	while player.Parent do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local desc = describe(player)
		if hum and desc then
			local ok, err = pcall(function() hum:ApplyDescription(desc) end)
			if not ok then warn("[NinjaMenu] couldn't change the look:", err) end
		end
		if not pending[player] then break end
		pending[player] = false
	end
	pending[player] = nil
end

local function elementOf(player)
	local e = player:GetAttribute("SpinjitzuElement")
	if e and Config.Presets[e] then return e end
	return Config.Element
end

local function notify(player, text)
	local toggle = ReplicatedStorage:FindFirstChild("SpinjitzuToggle")
	if toggle then toggle:FireClient(player, "notify", text) end
end

----------------------------------------------------------------------------------------
-- weapons: a list you add to / take from
----------------------------------------------------------------------------------------

local function weaponList(player)
	local attr = player:GetAttribute("GoldenWeapons")
	local list = {}
	if attr == nil then
		local own = GoldenWeapons.ByElement[elementOf(player)]
		if own then table.insert(list, own) end
	elseif attr ~= "None" then
		for kind in attr:gmatch("[^,]+") do
			if GoldenWeapons.Weapons[kind] then table.insert(list, kind) end
		end
	end
	return list
end

local function pickWeapon(player, value)
	local own = GoldenWeapons.ByElement[elementOf(player)]
	if value == "None" then
		player:SetAttribute("GoldenWeapons", "None")
	elseif value == "All" then
		if Roster.AnyWeapon then player:SetAttribute("GoldenWeapons", table.concat(WEAPON_KINDS, ",")) end
	elseif GoldenWeapons.Weapons[value] then
		if not Roster.AnyWeapon and value ~= own then return end
		local list = weaponList(player)
		local i = table.find(list, value)
		if i then table.remove(list, i) else table.insert(list, value) end
		player:SetAttribute("GoldenWeapons", #list > 0 and table.concat(list, ",") or "None")
	end
end

----------------------------------------------------------------------------------------
-- Tornado of Creation crew: the three you're missing, in a square with you
----------------------------------------------------------------------------------------

local function removeCrew(player)
	for _, bot in ipairs(CollectionService:GetTagged("CreationCrew")) do
		if bot:GetAttribute("CrewOwner") == player.UserId and not Creation.busy[bot] then bot:Destroy() end
	end
end

local function removeDummies(player)
	for _, dummy in ipairs(CollectionService:GetTagged("PlayerDummy")) do
		if dummy:GetAttribute("DummyOwner") == player.UserId then dummy:Destroy() end
	end
	for _, bot in ipairs(CollectionService:GetTagged("PlayerShatterBot")) do
		if bot:GetAttribute("BotOwner") == player.UserId then bot:Destroy() end
	end
end

-- a bot Shatterspinning round in a circle in front of you (up to 3 each; the oldest goes)
local function spawnShatterBot(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local mine = {}
	for _, bot in ipairs(CollectionService:GetTagged("PlayerShatterBot")) do
		if bot:GetAttribute("BotOwner") == player.UserId then table.insert(mine, bot) end
	end
	if #mine >= 3 then mine[1]:Destroy() end
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local Shatter = require(script.Parent:WaitForChild("Shatterspin"))
	local bot = Shatter.spawnBot(root.Position + look * (26 + #mine * 8), "ShatterBot_" .. player.Name, 10)
	bot:SetAttribute("BotOwner", player.UserId)
	CollectionService:AddTag(bot, "PlayerShatterBot")
	notify(player, ("Shatterspin bot: get on the dragon (%s), lock on (%s), fly into it"):format(
		Config.DragonKey and Config.DragonKey.Name or "R", Config.DragonLockKey and Config.DragonLockKey.Name or "C"))
end

-- a row of up to 4 in front of you, then another row behind it
local function spawnDummy(player, infinite)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local count = 0
	for _, dummy in ipairs(CollectionService:GetTagged("PlayerDummy")) do
		if dummy:GetAttribute("DummyOwner") == player.UserId then count += 1 end
	end
	if count >= MAX_DUMMIES then
		notify(player, ("That's %d dummies already: Remove Bots to clear them"):format(MAX_DUMMIES))
		return
	end
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)
	local at = root.Position + look * (9 + math.floor(count / 4) * 5) + right * ((count % 4) - 1.5) * 4.5
	TrainingDummy.spawn(at, root.Position, {
		infinite = infinite,
		setup = function(dummy)
			dummy:SetAttribute("DummyOwner", player.UserId)
			CollectionService:AddTag(dummy, "PlayerDummy")
		end,
	})
end

local function spawnCrew(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local order = Config.CreationElements
	local mine = elementOf(player)
	local myIndex = table.find(order, mine)
	if not myIndex then
		notify(player, "Creation bots: be Fire, Earth, Lightning or Ice first")
		return
	end
	for _, bot in ipairs(CollectionService:GetTagged("CreationCrew")) do
		if bot:GetAttribute("CrewOwner") == player.UserId and Creation.busy[bot] then return end -- mid-tornado
	end
	removeCrew(player)
	-- square of 4 corners, 9 studs from its middle; you're the corner you stand on, the
	-- middle is in front of you
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local center = root.Position + look * 9
	local base = math.atan2(-look.Z, -look.X) - (myIndex - 1) * math.pi / 2
	for i, el in ipairs(order) do
		if i ~= myIndex then
			local a = base + (i - 1) * math.pi / 2
			local bot = Bots.make(el, center + Vector3.new(math.cos(a), 0, math.sin(a)) * 9, "CrewBot_" .. el, center)
			bot:FindFirstChildOfClass("Humanoid").DisplayName = el .. " (your crew)"
			bot:SetAttribute("CrewOwner", player.UserId)
			bot:SetAttribute("CrewElement", el)
			CollectionService:AddTag(bot, "CreationCrew")
		end
	end
	notify(player, ("Creation crew ready: press %s"):format(Config.CreationKey and Config.CreationKey.Name or "T"))
end

remote.OnServerEvent:Connect(function(player, action, value)
	if typeof(value) ~= "string" then return end
	if action == "character" then
		local ninja = Roster.find(value)
		if not ninja and value ~= "You" then return end
		player:SetAttribute("GoldenWeapons", nil) -- back to the character's own weapon
		player:SetAttribute("Ninja", ninja and ninja.Name or nil)
		if ninja then player:SetAttribute("SpinjitzuElement", ninja.Element) end
		task.spawn(applyLook, player)
	elseif action == "weapon" then
		pickWeapon(player, value)
	elseif action == "bots" then
		if value == "creation" then
			spawnCrew(player)
		elseif value == "shatter" then
			spawnShatterBot(player)
		elseif value == "dummy" or value == "dummyInf" then
			spawnDummy(player, value == "dummyInf")
		elseif value == "remove" then
			removeCrew(player)
			removeDummies(player)
		end
	end
end)

local function onAppearance(player, character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if not originals[player] and not player:GetAttribute("Ninja") then
		originals[player] = hum:GetAppliedDescription()
	elseif player:GetAttribute("Ninja") then
		task.spawn(applyLook, player) -- respawned: dress them again
	end
end

local function onPlayer(player)
	player.CharacterAppearanceLoaded:Connect(function(character) onAppearance(player, character) end)
	if player.Character and player:HasAppearanceLoaded() then onAppearance(player, player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	removeCrew(player)
	removeDummies(player)
	originals[player] = nil
	pending[player] = nil
end)
