-- SpinjitzuBots v1.0  (ModuleScript in ServerScriptService)
-- Builds the ninja bots (minifig colours per element): SpinjitzuBot's demo bots and the
-- Tornado of Creation crew you can spawn from the menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))

local Bots = {}

local SKIN = Color3.fromRGB(245, 205, 48)
local BODY_COLORS = {
	Energy = Color3.fromRGB(40, 165, 45),
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

-- a bot standing on the ground at pos, facing lookAt (default: the spawn)
function Bots.make(element, pos, name, lookAt)
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
	local at = Vector3.new(pos.X, rootY, pos.Z)
	if lookAt then
		lookAt = Vector3.new(lookAt.X, rootY, lookAt.Z)
	else
		local spawnLoc = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		lookAt = spawnLoc and Vector3.new(spawnLoc.Position.X, rootY, spawnLoc.Position.Z) or at + Vector3.new(0, 0, -1)
	end
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

return Bots
