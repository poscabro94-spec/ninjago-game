-- VersionLabel v1.0  (LocalScript in StarterPlayerScripts)
-- The build number (GameVersion) in the bottom right corner, so you can tell which update you're on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage:WaitForChild("GameVersion"))

local gui = Instance.new("ScreenGui")
gui.Name = "VersionLabel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -8, 1, -6)
label.Size = UDim2.fromOffset(220, 16)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 13
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextColor3 = Color3.new(1, 1, 1)
label.TextTransparency = 0.25
label.TextStrokeTransparency = 0.5
label.Text = ("v%d  ·  %s"):format(Version.Build, Version.Date)
label.Parent = gui
