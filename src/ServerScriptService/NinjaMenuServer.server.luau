-- NinjaMenuServer v1.0  (Script in ServerScriptService)
-- What the menu (NinjaMenu) asks for:
--   "character", name  -> become that ninja (element + look), "You" = back to your own avatar
--   "weapon", kind     -> that Golden Weapon ("None" = no weapon); GoldenWeaponsServer gives it
-- Your look stays when you respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roster = require(ReplicatedStorage:WaitForChild("NinjaRoster"))
local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))

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

remote.OnServerEvent:Connect(function(player, action, value)
	if typeof(value) ~= "string" then return end
	if action == "character" then
		local ninja = Roster.find(value)
		if not ninja and value ~= "You" then return end
		player:SetAttribute("GoldenWeapon", nil) -- back to the character's own weapon
		player:SetAttribute("Ninja", ninja and ninja.Name or nil)
		if ninja then player:SetAttribute("SpinjitzuElement", ninja.Element) end
		task.spawn(applyLook, player)
	elseif action == "weapon" then
		if value ~= "None" and not GoldenWeapons.Weapons[value] then return end
		if value ~= "None" and not Roster.AnyWeapon then
			local own = GoldenWeapons.ByElement[player:GetAttribute("SpinjitzuElement") or ""]
			if own ~= value then return end
		end
		player:SetAttribute("GoldenWeapon", value)
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
	originals[player] = nil
	pending[player] = nil
end)
