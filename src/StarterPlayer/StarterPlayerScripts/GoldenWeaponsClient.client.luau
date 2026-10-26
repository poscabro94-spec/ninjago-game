-- GoldenWeaponsClient v1.1  (LocalScript in StarterPlayerScripts)
-- Aiming for the Shurikens of Ice: a click with them out sends where your mouse (or tap) points
-- to the server, which throws them. Time Blades: F uses the blade's time power (aimed the same
-- way). While time is stopped around you, your screen goes grey and red.
-- Everything else about the weapons is in GoldenWeapons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

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

-- Time Blades: F = the blade's power
local timeRemote = ReplicatedStorage:WaitForChild("TimeBladePower")
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.F then return end
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("TimePower") then timeRemote:FireServer(mouse.Hit.Position) end
end)

-- caught in stopped time: the world goes grey with a red tint
local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "TimeStoppedTint"
tint.Enabled = false
tint.Parent = Lighting
local function watchTime(character)
	local function update()
		local stopped = character:GetAttribute("TimeStopped") == true
		if stopped then
			tint.Enabled = true
			tint.Saturation, tint.TintColor, tint.Contrast = 0, Color3.new(1, 1, 1), 0
			TweenService:Create(tint, TweenInfo.new(0.25), {
				Saturation = -0.75, TintColor = Color3.fromRGB(255, 190, 190), Contrast = 0.15,
			}):Play()
		elseif tint.Enabled then
			TweenService:Create(tint, TweenInfo.new(0.2), { Saturation = 0, TintColor = Color3.new(1, 1, 1), Contrast = 0 }):Play()
			task.delay(0.2, function()
				if not character:GetAttribute("TimeStopped") then tint.Enabled = false end
			end)
		end
	end
	character:GetAttributeChangedSignal("TimeStopped"):Connect(update)
	update()
end
if player.Character then watchTime(player.Character) end
player.CharacterAdded:Connect(watchTime)
