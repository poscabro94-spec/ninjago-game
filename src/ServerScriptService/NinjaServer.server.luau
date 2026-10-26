-- NinjaServer v1.3  (Script in ServerScriptService)
-- Relays parkour moves so every client can show them, and builds the parkour course
-- (from code, at the start of the game) next to the spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:FindFirstChild("NinjaParkour")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "NinjaParkour"
	remote.Parent = ReplicatedStorage
end

local ALLOWED = { vault = true, mantle = true, wallrunL = true, wallrunR = true, walljump = true }
remote.OnServerEvent:Connect(function(player, name)
	local character = player.Character
	if not character then return end
	if name ~= nil and not ALLOWED[name] then return end
	character:SetAttribute("ParkourMove", name)
end)

----------------------------------------------------------------------------------------
-- parkour course: runs along +X starting at COURSE_START
--   hurdles -> mantle block -> wall-run gap (wall on the right, then on the left)
--   -> vault box -> high mantle -> finish flag
----------------------------------------------------------------------------------------

local COURSE_START = Vector3.new(50, 0, 0)

local COLORS = {
	pad = Color3.fromRGB(70, 200, 120),
	hurdle = Color3.fromRGB(255, 170, 40),
	block = Color3.fromRGB(110, 120, 140),
	wall = Color3.fromRGB(80, 140, 230),
	finish = Color3.fromRGB(255, 220, 60),
}

local function part(model, name, size, pos, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(COURSE_START + pos)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function sign(model, text, pos)
	local anchor = Instance.new("Part")
	anchor.Name = "Sign"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(COURSE_START + pos)
	anchor.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 46)
	gui.MaxDistance = 120
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
end

local function build()
	if workspace:FindFirstChild("ParkourCourse") then return end
	local m = Instance.new("Model")
	m.Name = "ParkourCourse"

	part(m, "StartPad", Vector3.new(8, 0.6, 12), Vector3.new(0, 0.3, 0), COLORS.pad, Enum.Material.Neon)
	sign(m, "PARKOUR  (hold Shift to sprint)", Vector3.new(0, 7, 0))

	-- hurdles: just run into them
	for i, x in ipairs({ 14, 26, 38 }) do
		part(m, "Hurdle" .. i, Vector3.new(1, 2.6, 10), Vector3.new(x, 1.3, 0), COLORS.hurdle)
	end
	sign(m, "HURDLE: run into it", Vector3.new(14, 6, 0))

	-- mantle up onto a platform (6 high): jump at it
	part(m, "MantleBlock", Vector3.new(22, 6, 12), Vector3.new(61, 3, 0), COLORS.block)
	sign(m, "MANTLE: jump at the wall", Vector3.new(50, 10, 0))

	-- wall-run gap: first wall on the right, then wall jump (Space) to the left one
	part(m, "WallRunA", Vector3.new(18, 20, 1), Vector3.new(79, 12, 7), COLORS.wall)
	part(m, "WallRunB", Vector3.new(18, 20, 1), Vector3.new(93, 12, -7), COLORS.wall)
	sign(m, "WALL RUN: run along the right edge, jump, then Space to wall jump", Vector3.new(80, 24, 0))

	-- landing platform with a vault box on it
	part(m, "PlatformB", Vector3.new(14, 6, 12), Vector3.new(107, 3, 0), COLORS.block)
	part(m, "VaultBox", Vector3.new(1.2, 2.4, 12), Vector3.new(108, 7.2, 0), COLORS.hurdle)

	-- high mantle to the finish
	part(m, "HighBlock", Vector3.new(10, 12, 12), Vector3.new(119, 6, 0), COLORS.block)
	part(m, "FinishPad", Vector3.new(8, 0.4, 10), Vector3.new(119, 12.2, 0), COLORS.finish, Enum.Material.Neon)
	part(m, "FlagPole", Vector3.new(0.4, 8, 0.4), Vector3.new(121, 16.4, 4), Color3.fromRGB(230, 230, 230))
	part(m, "Flag", Vector3.new(0.2, 2.2, 3.4), Vector3.new(121, 19.2, 2.2), COLORS.finish, Enum.Material.Neon)
	sign(m, "FINISH", Vector3.new(119, 22, 0))

	-- stairs back down to the start
	for i = 1, 6 do
		part(m, "Step" .. i, Vector3.new(4, 12 - (i - 1) * 2, 4), Vector3.new(127 + (i - 1) * 4, (12 - (i - 1) * 2) / 2, 0), COLORS.block)
	end

	m.Parent = workspace
end

build()
