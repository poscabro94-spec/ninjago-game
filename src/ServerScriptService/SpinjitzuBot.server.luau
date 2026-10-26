-- SpinjitzuBot v6.0  (Script in ServerScriptService)
-- Test dummies that loop Spinjitzu: 6s on, stop, 1s pause, repeat. One bot per
-- element in Config.TestBotElements, side by side. Turn off with Config.TestBot = false.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))

if not Config.TestBot then return end

local SPIN_TIME = 6
local PAUSE_TIME = 1
local SPACING = 16
local ROW_GAP = 18
local PER_ROW = 6
local SKIN = Color3.fromRGB(245, 205, 48)
local BODY_COLORS = {
	Life = Color3.fromRGB(40, 165, 45),
	Fire = Color3.fromRGB(200, 40, 30),
	Water = Color3.fromRGB(30, 100, 210),
	Lightning = Color3.fromRGB(35, 70, 200),
	Earth = Color3.fromRGB(110, 70, 35),
	Ice = Color3.fromRGB(215, 235, 245),
}

-- Use classic Motor6D joints: limb positions then follow the (locally spun) root on
-- every client, instead of being physics-simulated on the server.
local function toMotors(model)
	for _, ac in ipairs(model:GetDescendants()) do
		if ac:IsA("AnimationConstraint") and ac.Attachment0 and ac.Attachment1 then
			local m = Instance.new("Motor6D")
			m.Name = ac.Name
			m.Part0 = ac.Attachment0.Parent
			m.Part1 = ac.Attachment1.Parent
			m.C0 = ac.Attachment0.CFrame
			m.C1 = ac.Attachment1.CFrame
			m.Parent = m.Part1
			ac:Destroy()
		end
	end
	for _, bs in ipairs(model:GetDescendants()) do
		if bs:IsA("BallSocketConstraint") then bs:Destroy() end
	end
end

local function makeBot(element, pos, name)
	local col = BODY_COLORS[element] or Color3.fromRGB(120, 120, 120)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = SKIN
	desc.TorsoColor = col
	desc.LeftArmColor, desc.RightArmColor = col, col
	desc.LeftLegColor, desc.RightLegColor = col, col

	local bot = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	bot.Name = name or ("SpinjitzuBot_" .. element)
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = element .. " Bot"
	local root = bot:WaitForChild("HumanoidRootPart")
	root.Anchored = true
	local animate = bot:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	toMotors(bot)

	-- stand on whatever ground is below the spot, facing the spawn
	local hit = workspace:Raycast(pos + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0))
	local groundY = hit and hit.Position.Y or pos.Y
	local rootY = groundY + humanoid.HipHeight + root.Size.Y / 2
	local spawnLoc = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local at = Vector3.new(pos.X, rootY, pos.Z)
	local lookAt = spawnLoc and Vector3.new(spawnLoc.Position.X, rootY, spawnLoc.Position.Z) or at + Vector3.new(0, 0, -1)
	if (lookAt - at).Magnitude < 0.1 then lookAt = at + Vector3.new(0, 0, -1) end
	bot:PivotTo(CFrame.lookAt(at, lookAt))

	local preset = Config.Presets[element] or {}
	bot:SetAttribute("SpinjitzuElement", element)
	bot:SetAttribute("SpinjitzuColor", preset.Color or Config.Color)
	bot:SetAttribute("SpinjitzuHighlight", preset.Highlight or Config.HighlightColor)
	CollectionService:AddTag(bot, "SpinjitzuNPC")
	bot.Parent = workspace
	return bot
end

local elements = Config.TestBotElements or { Config.Element }
local origin = Config.TestBotPosition or Vector3.new(0, 0, 20)
local bots = {}
for i, element in ipairs(elements) do
	local col = (i - 1) % PER_ROW
	local row = math.floor((i - 1) / PER_ROW)
	local inRow = math.min(PER_ROW, #elements - row * PER_ROW)
	local offset = (col - (inRow - 1) / 2) * SPACING
	table.insert(bots, makeBot(element, origin + Vector3.new(offset, 0, row * ROW_GAP)))
end

task.spawn(function()
	task.wait(2)
	while true do
		for _, bot in ipairs(bots) do
			if bot.Parent then bot:SetAttribute("SpinjitzuActive", true) end
		end
		task.wait(SPIN_TIME)
		for _, bot in ipairs(bots) do
			if bot.Parent then bot:SetAttribute("SpinjitzuActive", false) end
		end
		task.wait(PAUSE_TIME)
	end
end)
-- Tornado of Creation demo: Fire, Earth, Lightning and Ice bots in a square behind spawn
if Config.CreationBot then
	local Creation = require(script.Parent:WaitForChild("SpinjitzuCreation"))
	local center = origin + Vector3.new(0, 0, -75)
	local crew = {}
	for i, el in ipairs(Config.CreationElements) do
		local a = (i - 1) / 4 * math.pi * 2 + math.pi / 4
		local b = makeBot(el, center + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9), "CreationBot_" .. el)
		b:FindFirstChildOfClass("Humanoid").DisplayName = el .. " (Creation)"
		table.insert(crew, b)
	end
	task.spawn(function()
		task.wait(5)
		while true do
			Creation.run(crew)
			task.wait(5)
		end
	end)
end

-- Dragon demo bot: spin -> rises straight up with the dragon -> flies a loop -> lands, on repeat
if Config.DragonBot then
	local dbot = makeBot(Config.Element, origin + Vector3.new(0, 0, 30), "SpinjitzuBot_Dragon")
	dbot:FindFirstChildOfClass("Humanoid").DisplayName = "Dragon Bot"
	task.spawn(function()
		task.wait(3)
		while dbot.Parent do
			dbot:SetAttribute("DragonPhase", "spin")
			dbot:SetAttribute("SpinjitzuActive", true)
			task.wait(Config.DragonSpinTime or 2)
			dbot:SetAttribute("DragonPhase", "rise")
			dbot:SetAttribute("SpinjitzuActive", false)
			task.wait(Config.DragonRiseTime or 3)
			dbot:SetAttribute("DragonPhase", "fly")
			task.wait(7)
			dbot:SetAttribute("DragonPhase", "land")
			task.wait(2.5)
			dbot:SetAttribute("DragonPhase", nil)
			task.wait(2)
		end
	end)
end
