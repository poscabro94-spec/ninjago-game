-- SpinjitzuBot v6.1  (Script in ServerScriptService)
-- Test dummies that loop Spinjitzu: 6s on, stop, 1s pause, repeat. One bot per
-- element in Config.TestBotElements, side by side. Turn off with Config.TestBot = false.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))

if not Config.TestBot then return end

local SPIN_TIME = 6
local PAUSE_TIME = 1
local SPACING = 16
local ROW_GAP = 18
local PER_ROW = 6
local Bots = require(script.Parent:WaitForChild("SpinjitzuBots"))
local makeBot = Bots.make

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
