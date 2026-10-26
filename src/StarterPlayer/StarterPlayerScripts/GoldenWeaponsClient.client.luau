-- GoldenWeaponsClient v1.0  (LocalScript in StarterPlayerScripts)
-- Aiming for the Shurikens of Ice: a click with them out sends where your mouse (or tap) points
-- to the server, which throws them. Everything else about the weapons is in GoldenWeapons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local throwRemote = ReplicatedStorage:WaitForChild("ShurikenThrow")
local player = Players.LocalPlayer
local mouse = player:GetMouse()

local hooked = setmetatable({}, { __mode = "k" })

local function hook(tool)
	if not tool:IsA("Tool") or tool.Name ~= GoldenWeapons.Shurikens.ToolName or hooked[tool] then return end
	hooked[tool] = true
	tool.Activated:Connect(function()
		throwRemote:FireServer(mouse.Hit.Position)
	end)
end

-- the server builds a new tool on every spawn / element switch
local function watch(container)
	for _, child in ipairs(container:GetChildren()) do hook(child) end
	container.ChildAdded:Connect(hook)
end

local function onCharacter(character)
	watch(character)
	watch(player:WaitForChild("Backpack"))
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)
