-- NinjaRoster v1.0  (ModuleScript in ReplicatedStorage)
-- The characters in the menu (NinjaMenu). Picking one sets your element (Spinjitzu + Golden
-- Weapon) and your look. The look is body colours, plus optional catalog IDs:
--   Shirt / Pants = clothing asset IDs from the Roblox catalog (0 = none)
--   Accessories   = accessory asset IDs, comma separated (e.g. a ninja hood), "" = none

local Roster = {}

Roster.AnyWeapon = true -- the menu can give you any Golden Weapon (false = only your character's own)
Roster.SkinColor = Color3.fromRGB(245, 205, 48) -- minifig yellow head

Roster.Ninjas = {
	{ Name = "Kai",   Element = "Fire",      Color = Color3.fromRGB(196, 32, 24),  Shirt = 0, Pants = 0, Accessories = "" },
	{ Name = "Cole",  Element = "Earth",     Color = Color3.fromRGB(32, 32, 36),   Shirt = 0, Pants = 0, Accessories = "" },
	{ Name = "Jay",   Element = "Lightning", Color = Color3.fromRGB(20, 92, 196),  Shirt = 0, Pants = 0, Accessories = "" },
	{ Name = "Zane",  Element = "Ice",       Color = Color3.fromRGB(236, 238, 240), Shirt = 0, Pants = 0, Accessories = "" },
	{ Name = "Lloyd", Element = "Life",      Color = Color3.fromRGB(34, 140, 58),  Shirt = 0, Pants = 0, Accessories = "" },
	{ Name = "Nya",   Element = "Water",     Color = Color3.fromRGB(18, 150, 170), Shirt = 0, Pants = 0, Accessories = "" },
}

function Roster.find(name)
	for _, ninja in ipairs(Roster.Ninjas) do
		if ninja.Name == name then return ninja end
	end
	return nil
end

return Roster
