-- GoldenWeaponsClient v2.0  (LocalScript in StarterPlayerScripts)
-- Aiming for the Shurikens of Ice: a click with them out sends where your mouse (or tap) points
-- to the server, which throws them. Time Blades: their powers on keys (F / G / V / Z, from the
-- blade's Abilities), aimed the same way; a bar above the hotbar shows them + their cooldowns
-- (tap a box on a phone). While time is stopped around you, or you're moving in stopped time,
-- your screen goes grey.
-- Everything else about the weapons is in GoldenWeapons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
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

----------------------------------------------------------------------------------------
-- Time Blades: powers on keys + the bar
----------------------------------------------------------------------------------------

local timeRemote = ReplicatedStorage:WaitForChild("TimeBladePower")

-- the Time Blade you have out (nil = none)
local function heldBlade()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local W = tool and GoldenWeapons.ForTool(tool.Name)
	return W and W.Abilities and W or nil
end

local function use(id)
	timeRemote:FireServer(id, mouse.Hit.Position)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local W = heldBlade()
	if not W then return end
	for _, a in ipairs(W.Abilities) do
		if input.KeyCode.Name == a.key then use(a.id) end
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "TimeBladeBar"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -76)
bar.Size = UDim2.fromOffset(0, 58)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundTransparency = 1
bar.Parent = gui
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.Padding = UDim.new(0, 6)
list.Parent = bar

local slots = {} -- { id, box, shade, count }
local shownFor -- the blade the bar was built for

local function build(W)
	for _, s in ipairs(slots) do s.box:Destroy() end
	slots = {}
	for i, a in ipairs(W.Abilities) do
		local box = Instance.new("TextButton")
		box.LayoutOrder = i
		box.Size = UDim2.fromOffset(84, 58)
		box.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
		box.BackgroundTransparency = 0.2
		box.AutoButtonColor = false
		box.Text = ""
		box.Parent = bar
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
		local stroke = Instance.new("UIStroke")
		stroke.Color = W.EnergyColor
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = box
		local key = Instance.new("TextLabel")
		key.BackgroundTransparency = 1
		key.Position = UDim2.fromOffset(7, 4)
		key.Size = UDim2.fromOffset(20, 18)
		key.Font = Enum.Font.GothamBold
		key.TextSize = 15
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.TextColor3 = W.EnergyColor
		key.Text = a.key
		key.Parent = box
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 4, 1, -24)
		name.Size = UDim2.new(1, -8, 0, 20)
		name.Font = Enum.Font.Gotham
		name.TextSize = 11
		name.TextWrapped = true
		name.TextColor3 = Color3.fromRGB(225, 225, 230)
		name.Text = a.name
		name.Parent = box
		-- cooldown: a dark cover that shrinks + the seconds left
		local shade = Instance.new("Frame")
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.35
		shade.BorderSizePixel = 0
		shade.AnchorPoint = Vector2.new(0, 1)
		shade.Position = UDim2.fromScale(0, 1)
		shade.Size = UDim2.fromScale(1, 0)
		shade.ZIndex = 2
		shade.Parent = box
		Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 6)
		local count = Instance.new("TextLabel")
		count.BackgroundTransparency = 1
		count.Size = UDim2.fromScale(1, 1)
		count.Font = Enum.Font.GothamBold
		count.TextSize = 18
		count.TextColor3 = Color3.new(1, 1, 1)
		count.Text = ""
		count.ZIndex = 3
		count.Parent = box
		box.Activated:Connect(function() use(a.id) end)
		table.insert(slots, { id = a.id, cooldown = a.cooldown, shade = shade, count = count, box = box })
	end
end

RunService.RenderStepped:Connect(function()
	local W = heldBlade()
	gui.Enabled = W ~= nil
	if not W then return end
	if W ~= shownFor then
		shownFor = W
		build(W)
	end
	local now = workspace:GetServerTimeNow()
	for _, s in ipairs(slots) do
		local left = (player:GetAttribute("TimeReady" .. s.id) or 0) - now
		if left > 0 then
			s.shade.Size = UDim2.fromScale(1, math.clamp(left / s.cooldown, 0, 1))
			s.count.Text = tostring(math.ceil(left))
		else
			s.shade.Size = UDim2.fromScale(1, 0)
			s.count.Text = ""
		end
	end
end)

----------------------------------------------------------------------------------------
-- grey screen: caught in stopped time (a red tint), or you're the one moving in it
----------------------------------------------------------------------------------------

local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "TimeStoppedTint"
tint.Enabled = false
tint.Parent = Lighting
local tintUntil = 0
local tinted = false

timeRemote.OnClientEvent:Connect(function(action, seconds)
	if action == "tint" and typeof(seconds) == "number" then tintUntil = math.max(tintUntil, os.clock() + seconds) end
end)

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local caught = character ~= nil and character:GetAttribute("TimeStopped") == true
	local want = caught or os.clock() < tintUntil
	if want == tinted then return end
	tinted = want
	if want then
		tint.Enabled = true
		tint.Saturation, tint.TintColor, tint.Contrast = 0, Color3.new(1, 1, 1), 0
		TweenService:Create(tint, TweenInfo.new(0.25), {
			Saturation = -0.75, TintColor = caught and Color3.fromRGB(255, 190, 190) or Color3.fromRGB(235, 225, 225), Contrast = 0.15,
		}):Play()
	else
		TweenService:Create(tint, TweenInfo.new(0.2), { Saturation = 0, TintColor = Color3.new(1, 1, 1), Contrast = 0 }):Play()
		task.delay(0.2, function()
			if not tinted then tint.Enabled = false end
		end)
	end
end)
