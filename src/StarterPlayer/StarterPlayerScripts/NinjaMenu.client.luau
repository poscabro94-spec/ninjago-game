-- NinjaMenu v1.8  (LocalScript in StarterPlayerScripts)
-- The MENU button (bottom left, or M) opens a panel: pick your character (NinjaRoster), switch
-- Golden Weapons on and off (several at once), spawn the Tornado of Creation crew as bots and
-- training dummies (normal / infinite HP), and Duels: two NPCs clashing beams (you pick who
-- wins) or an NPC that fights you.
-- Cards show live 3D previews: your own avatar in each ninja's colours, and the weapon models
-- from ReplicatedStorage. NinjaMenuServer does the actual change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Roster = require(ReplicatedStorage:WaitForChild("NinjaRoster"))
local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local GoldenWeapons = require(ReplicatedStorage:WaitForChild("GoldenWeapons"))
local remote = ReplicatedStorage:WaitForChild("NinjaMenu")
local player = Players.LocalPlayer

local RED = Color3.fromRGB(226, 22, 28)
local INK = Color3.fromRGB(14, 14, 16)
local PANEL = Color3.fromRGB(23, 23, 26)
local PILL = Color3.fromRGB(40, 40, 44)
local RIM = Color3.fromRGB(56, 56, 60)
local GOLD = Color3.fromRGB(255, 196, 40)
local MUTED = Color3.fromRGB(150, 150, 156)
local TITLE = Font.fromName("Sarpanch", Enum.FontWeight.Bold)
local LABEL = Font.fromName("Montserrat", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
local SMALL = Font.fromName("Montserrat", Enum.FontWeight.SemiBold)
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ELEMENT_COLORS = {
	Fire = Color3.fromRGB(255, 120, 40), Earth = Color3.fromRGB(205, 150, 80), Lightning = Color3.fromRGB(90, 190, 255),
	Ice = Color3.fromRGB(190, 235, 255), Energy = Color3.fromRGB(110, 230, 90), Water = Color3.fromRGB(60, 200, 220),
}
local WEAPON_ORDER = {}
for _, kind in ipairs({ "Sword", "Scythe", "Nunchucks", "Shurikens", "PauseBlade" }) do
	if not GoldenWeapons.Weapons[kind].Hidden then table.insert(WEAPON_ORDER, kind) end -- (Hidden = parked)
end
local GOLDEN = { "Sword", "Scythe", "Nunchucks", "Shurikens" } -- what "All" gives
local OWNER = {} -- weapon kind -> element that owns it
for element, kind in pairs(GoldenWeapons.ByElement) do OWNER[kind] = element end

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do inst[k] = v end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	return inst
end
local function round(r) return new("UICorner", { CornerRadius = r or UDim.new(1, 0) }) end
local function outline(color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function textOutline(thickness)
	return new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end
local function label(props)
	local strokeWidth = props.Stroke
	props.Stroke = nil
	props.BackgroundTransparency = 1
	return new("TextLabel", props, { textOutline(strokeWidth) })
end

----------------------------------------------------------------------------------------
-- screen + MENU button
----------------------------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "NinjaMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 })

local menuScale = new("UIScale")
local menuButton = new("TextButton", {
	Name = "MenuButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18),
	Size = UDim2.fromOffset(86, 86), BackgroundColor3 = INK, Text = "", AutoButtonColor = false,
}, {
	round(), outline(RED, 4), menuScale,
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(48, 48, 52), Color3.fromRGB(8, 8, 10)) }),
	-- thin inner ring
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -14, 1, -14),
		BackgroundTransparency = 1 }, { round(), outline(RED, 1.5, 0.35) }),
	-- little bars above and below the word, like the trim on the reference
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 17), Size = UDim2.fromOffset(26, 3),
		BackgroundColor3 = RED, BorderSizePixel = 0 }, { round(UDim.new(0, 2)) }),
	new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -17), Size = UDim2.fromOffset(26, 3),
		BackgroundColor3 = RED, BorderSizePixel = 0 }, { round(UDim.new(0, 2)) }),
	label({ Size = UDim2.fromScale(1, 1), Text = "MENU", FontFace = TITLE, TextSize = 23, TextColor3 = RED }),
})
menuButton.Parent = gui

----------------------------------------------------------------------------------------
-- panel
----------------------------------------------------------------------------------------

local panelScale = new("UIScale")
local panel = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(900, 580), BackgroundColor3 = RIM, Visible = false,
}, { round(UDim.new(0, 30)), panelScale })
panel.Parent = gui

local inner = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundColor3 = PANEL },
	{ round(UDim.new(0, 24)), outline(RED, 3) })
inner.Parent = panel

local SIDEBAR_W, TABS_H = 150, 78
new("Frame", { Position = UDim2.fromOffset(SIDEBAR_W, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0 }).Parent = inner
new("Frame", { Position = UDim2.fromOffset(SIDEBAR_W + 3, TABS_H), Size = UDim2.new(1, -SIDEBAR_W - 3, 0, 3),
	BackgroundColor3 = RED, BorderSizePixel = 0 }).Parent = inner

local sidebar = new("Frame", { Size = UDim2.new(0, SIDEBAR_W, 1, 0), BackgroundTransparency = 1 }, {
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingTop = UDim.new(0, 18) }),
})
sidebar.Parent = inner

local tabsBar = new("Frame", { Position = UDim2.fromOffset(SIDEBAR_W + 3, 0), Size = UDim2.new(1, -SIDEBAR_W - 3, 0, TABS_H),
	BackgroundTransparency = 1 }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingLeft = UDim.new(0, 14) }),
})
tabsBar.Parent = inner

local content = new("Frame", { Position = UDim2.fromOffset(SIDEBAR_W + 3, TABS_H + 3),
	Size = UDim2.new(1, -SIDEBAR_W - 3, 1, -TABS_H - 3), BackgroundTransparency = 1, ClipsDescendants = true })
content.Parent = inner

-- faint rings in the background (the swirl pattern of the reference, drawn instead of an image)
for _, ring in ipairs({ { 0.18, 0.3, 360 }, { 0.18, 0.3, 250 }, { 0.18, 0.3, 140 }, { 0.82, 0.78, 420 }, { 0.82, 0.78, 300 },
	{ 0.82, 0.78, 180 }, { 0.55, 1.05, 260 } }) do
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(ring[1], ring[2]),
		Size = UDim2.fromOffset(ring[3], ring[3]), BackgroundTransparency = 1 }, { round(), outline(Color3.new(1, 1, 1), 2, 0.95) }).Parent = content
end

local status = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 30, 1, -14), Size = UDim2.new(1, -60, 0, 20),
	FontFace = SMALL, TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Stroke = 1, ZIndex = 3 })
status.Parent = content

----------------------------------------------------------------------------------------
-- sidebar icons, drawn from frames
----------------------------------------------------------------------------------------

local function ninjaIcon()
	return new("Frame", { Size = UDim2.fromOffset(60, 60), BackgroundColor3 = RED }, {
		round(),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 90, 90), Color3.fromRGB(150, 0, 6)) }),
		-- eye slit in the hood
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(40, 13),
			BackgroundColor3 = Roster.SkinColor }, {
			round(UDim.new(0, 5)),
			new("Frame", { Position = UDim2.fromOffset(9, 4), Size = UDim2.fromOffset(7, 5), BackgroundColor3 = INK }, { round(UDim.new(0, 2)) }),
			new("Frame", { Position = UDim2.fromOffset(24, 4), Size = UDim2.fromOffset(7, 5), BackgroundColor3 = INK }, { round(UDim.new(0, 2)) }),
		}),
		-- knot of the hood
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(16, 6),
			BackgroundColor3 = Color3.fromRGB(150, 0, 6) }, { round(UDim.new(0, 3)) }),
	})
end

local function bladesIcon()
	local holder = new("Frame", { Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1 })
	for _, angle in ipairs({ 40, -40 }) do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(7, 58),
			Rotation = angle, BackgroundColor3 = GOLD }, {
			round(UDim.new(0, 3)), outline(Color3.fromRGB(110, 70, 0), 1.5),
			new("UIGradient", { Rotation = 0, Color = ColorSequence.new(Color3.fromRGB(255, 235, 140), Color3.fromRGB(220, 150, 20)) }),
			-- guard + grip
			new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(17, 4),
				BackgroundColor3 = GOLD, BorderSizePixel = 0 }, { round(UDim.new(0, 2)) }),
			new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(7, 14),
				BackgroundColor3 = Color3.fromRGB(150, 22, 14), BorderSizePixel = 0 }, { round(UDim.new(0, 3)) }),
		}).Parent = holder
	end
	return holder
end

-- the Tornado of Creation: bands from blue at the bottom to white at the top
local function tornadoIcon()
	local holder = new("Frame", { Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1 })
	local bands = {
		{ 58, Color3.fromRGB(255, 250, 235) }, { 50, Color3.fromRGB(255, 220, 120) }, { 42, Color3.fromRGB(255, 160, 50) },
		{ 33, Color3.fromRGB(240, 110, 30) }, { 24, Color3.fromRGB(120, 200, 255) }, { 14, Color3.fromRGB(55, 150, 255) },
	}
	for i, band in ipairs(bands) do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (i % 2 == 0) and 2 or -2, 0, (i - 1) * 10),
			Size = UDim2.fromOffset(band[1], 8), BackgroundColor3 = band[2], BorderSizePixel = 0 }, { round(UDim.new(0, 4)) }).Parent = holder
	end
	return holder
end

-- two beams crashing into each other
local function clashIcon()
	local holder = new("Frame", { Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1 })
	for _, side in ipairs({ { -1, Color3.fromRGB(90, 200, 255) }, { 1, Color3.fromRGB(255, 120, 30) } }) do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side[1] * 14, 0.5, 0), Size = UDim2.fromOffset(30, 9),
			Rotation = side[1] * 12, BackgroundColor3 = side[2], BorderSizePixel = 0 }, { round(UDim.new(0, 4)) }).Parent = holder
	end
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, { round() }).Parent = holder
	for i = 0, 3 do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 34),
			Rotation = i * 45, BackgroundColor3 = Color3.fromRGB(255, 240, 170), BorderSizePixel = 0 }, { round(UDim.new(0, 2)) }).Parent = holder
	end
	return holder
end

----------------------------------------------------------------------------------------
-- cards
----------------------------------------------------------------------------------------

local function grid()
	return new("ScrollingFrame", {
		Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -46, 1, -62), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = RED, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, ZIndex = 2,
	}, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(128, 170), CellPadding = UDim2.fromOffset(26, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
	})
end

-- a round glossy card: returns the button, the viewport to put a preview in, a setter for
-- "selected" and the disc. The preview is framed to stay inside the circle (no clipping needed);
-- the viewport stops a little above the bottom so a bust is cut off inside the ring.
local function card(order, title, subtitle, subColor)
	local scale = new("UIScale")
	local button = new("TextButton", { LayoutOrder = order, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 2 }, { scale })
	local function onDisc(z) -- same spot as the disc
		return { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(118, 118), ZIndex = z }
	end
	local disc = new("Frame", onDisc(3), {
		round(),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 92)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(215, 16, 22)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 0, 4)),
		}) }),
	})
	disc.BackgroundColor3 = RED
	disc.Parent = button
	local viewport = new("ViewportFrame", onDisc(4))
	viewport.Size = UDim2.fromOffset(118, 108)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 140, 140)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -0.6, 1)
	viewport.Parent = button
	-- the preview is square: a ring in the panel colour hides whatever pokes out past the circle
	local mask = new("Frame", onDisc(5), { round(), outline(PANEL, 22) })
	mask.BackgroundTransparency = 1
	mask.Parent = button
	-- shine across the top, over the preview like glass
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 7), Size = UDim2.fromOffset(96, 50),
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 6 }, {
		round(),
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }) }),
	}).Parent = button
	-- dark halo, a little down and to the right, like a shadow
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 1, 0, 2), Size = UDim2.fromOffset(124, 124),
		BackgroundTransparency = 1, ZIndex = 7 }, { round(), outline(Color3.fromRGB(10, 10, 30), 4, 0.15) }).Parent = button
	local rimStroke = outline(Color3.fromRGB(245, 245, 245), 3)
	local rim = new("Frame", onDisc(8), { round(), rimStroke })
	rim.BackgroundTransparency = 1
	rim.Parent = button
	local name = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 126), Size = UDim2.new(1, 0, 0, 22),
		Text = title, FontFace = LABEL, TextSize = 19, TextColor3 = Color3.new(1, 1, 1), ZIndex = 9 })
	name.Parent = button
	if subtitle then
		label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 147), Size = UDim2.new(1, 0, 0, 16),
			Text = subtitle, FontFace = SMALL, TextSize = 13, TextColor3 = subColor or MUTED, Stroke = 1, ZIndex = 9 }).Parent = button
	end

	button.MouseEnter:Connect(function() TweenService:Create(scale, QUICK, { Scale = 1.06 }):Play() end)
	button.MouseLeave:Connect(function() TweenService:Create(scale, QUICK, { Scale = 1 }):Play() end)
	button.MouseButton1Down:Connect(function() TweenService:Create(scale, QUICK, { Scale = 0.95 }):Play() end)
	button.MouseButton1Up:Connect(function() TweenService:Create(scale, QUICK, { Scale = 1.06 }):Play() end)

	local function setSelected(on)
		rimStroke.Color = on and GOLD or Color3.fromRGB(245, 245, 245)
		rimStroke.Thickness = on and 5 or 3
		name.TextColor3 = on and GOLD or Color3.new(1, 1, 1)
	end
	return button, viewport, setSelected, disc
end

----------------------------------------------------------------------------------------
-- 3D previews
----------------------------------------------------------------------------------------

local avatar -- copy of your character as it looked when the menu first opened

local function captureAvatar()
	local character = player.Character
	if not character then return nil end
	local was = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = was
	if not copy then return nil end
	for _, d in ipairs(copy:GetDescendants()) do
		-- only the body, clothes and accessories: no scripts, tools, weapons on the back, effects
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("Folder") or d:IsA("ParticleEmitter")
			or d:IsA("Sound") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	local hum = copy:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	return copy
end

local function dressed(ninja)
	local model = avatar:Clone()
	if ninja then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then d:Destroy() end
		end
		for _, part in ipairs(model:GetChildren()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				local isLeg = part.Name:find("Leg") or part.Name:find("Foot")
				part.Color = part.Name == "Head" and Roster.SkinColor or (isLeg and ninja.LegColor) or ninja.Color
			end
		end
	end
	return model
end

local function showCharacter(viewport, ninja)
	if not avatar then return end
	local model = dressed(ninja)
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local head = model:FindFirstChild("Head")
	local y = head and head.Position.Y or 1.5
	local camera = new("Camera", { FieldOfView = 30 })
	camera.CFrame = CFrame.lookAt(Vector3.new(1.2, y + 0.2, -5.6), Vector3.new(0, y - 0.9, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- weapon model from ReplicatedStorage, or a simple gold stand-in shaped like the placeholder
local function showWeapon(viewport, kind)
	local W = GoldenWeapons.Weapons[kind]
	local model = new("Model")
	local src = W and W.ModelName and (ReplicatedStorage:FindFirstChild(W.ModelName, true)
		or (W.OldModelName and ReplicatedStorage:FindFirstChild(W.OldModelName, true)))
	if src and W.Gauntlet then
		-- Time Blade: bronze gauntlet, blades in the blade's colour
		local copy = src:Clone()
		copy.Parent = model
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local blade = d.Name == "Blades"
				d.Color = blade and W.BladeColor or W.GauntletColor
				d.Material = blade and Enum.Material.SmoothPlastic or W.Material
				if d:IsA("MeshPart") then d.TextureID = "" end
			end
		end
	elseif src then
		local copy = src:Clone()
		copy.Parent = model
		local parts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
		table.sort(parts, function(a, b) return a.Size.Magnitude > b.Size.Magnitude end)
		if parts[1] then
			parts[1].Color, parts[1].Material = W.Color, W.Material
			if parts[1]:IsA("MeshPart") then parts[1].TextureID = "" end
		end
	else
		local function block(size, cf)
			new("Part", { Size = size, CFrame = cf, Color = W.Color, Material = Enum.Material.Metal, Anchored = true }).Parent = model
		end
		if kind == "Scythe" then
			block(Vector3.new(0.22, 5.5, 0.22), CFrame.new())
			block(Vector3.new(0.1, 0.45, 2.2), CFrame.new(0, 2.5, 1.2))
		elseif kind == "Shurikens" then
			block(Vector3.new(0.77, 0.12, 0.77), CFrame.Angles(math.pi / 2, math.pi / 4, 0))
		elseif kind == "Nunchucks" then
			block(Vector3.new(0.4, 2.4, 0.4), CFrame.new(-0.4, 0, 0) * CFrame.Angles(0, 0, 0.25))
			block(Vector3.new(0.4, 2.4, 0.4), CFrame.new(0.4, 0, 0) * CFrame.Angles(0, 0, -0.25))
		else
			block(Vector3.new(0.12, 5, 0.4), CFrame.new())
		end
	end
	-- centre it, longest side on the diagonal
	local cf, size = model:GetBoundingBox()
	model:PivotTo(cf:Inverse() * model:GetPivot())
	local longest = math.max(size.X, size.Y, size.Z)
	local axis = size.X == longest and Vector3.xAxis or (size.Y == longest and Vector3.yAxis or Vector3.zAxis)
	local turn = CFrame.fromRotationBetweenVectors(axis, Vector3.new(1, 1, 0).Unit)
	model:PivotTo(turn * model:GetPivot())
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	model.Parent = viewport
	local camera = new("Camera", { FieldOfView = 30 })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, -longest * 2.2), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- the crew you'd get: the other Creation ninja side by side
local function showCrew(viewport, elements)
	if not avatar then return end
	for i, el in ipairs(elements) do
		local ninja
		for _, n in ipairs(Roster.Ninjas) do
			if n.Element == el then ninja = n end
		end
		local model = dressed(ninja or Roster.Ninjas[1])
		model:PivotTo(CFrame.new((i - (#elements + 1) / 2) * 2.6, 0, (i == 2) and -0.6 or 0))
		model.Parent = viewport
	end
	local camera = new("Camera", { FieldOfView = 30 })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, -13), Vector3.new(0, 0.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- a training dummy: your avatar's shape in the dummy colours
local function showDummy(viewport, cloth)
	showCharacter(viewport, { Color = cloth, LegColor = cloth })
	local model = viewport:FindFirstChildOfClass("Model")
	for _, part in ipairs(model and model:GetChildren() or {}) do
		if part:IsA("BasePart") and (part.Name:find("Arm") or part.Name:find("Hand") or part.Name == "Head") then
			part.Color = Color3.fromRGB(190, 160, 110)
		end
	end
end

-- "no weapon": an empty disc with a slash through it
local function showNone(disc)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(70, 70),
		BackgroundTransparency = 1, ZIndex = 4 }, { round(), outline(Color3.fromRGB(30, 0, 2), 6) }).Parent = disc
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 70),
		Rotation = 45, BackgroundColor3 = Color3.fromRGB(30, 0, 2), BorderSizePixel = 0, ZIndex = 4 }).Parent = disc
end

----------------------------------------------------------------------------------------
-- pages
----------------------------------------------------------------------------------------

local characterGrid, weaponGrid, botGrid = grid(), grid(), grid()
characterGrid.Parent, weaponGrid.Parent, botGrid.Parent = content, content, content
local characterCards, weaponCards = {}, {}
local crewSubtitle

local function currentNinja() return player:GetAttribute("Ninja") or "You" end
local function myElement() return player:GetAttribute("SpinjitzuElement") or Config.Element end
-- the weapons you have now (same rule as GoldenWeaponsServer)
local function currentWeapons()
	local attr = player:GetAttribute("GoldenWeapons")
	local set, count = {}, 0
	if attr == nil then
		local own = GoldenWeapons.ByElement[myElement()]
		if own then set[own], count = true, 1 end
	elseif attr ~= "None" then
		for kind in attr:gmatch("[^,]+") do
			if GoldenWeapons.Weapons[kind] and not set[kind] then set[kind], count = true, count + 1 end
		end
	end
	return set, count
end
local function crewElements()
	local list = {}
	for _, el in ipairs(Config.CreationElements) do
		if el ~= myElement() then table.insert(list, el) end
	end
	return list
end

local function refresh()
	local ninja = currentNinja()
	local weapons, count = currentWeapons()
	for name, setSelected in pairs(characterCards) do setSelected(name == ninja) end
	for kind, setSelected in pairs(weaponCards) do
		if kind == "All" then
			local all = true
			for _, k in ipairs(GOLDEN) do all = all and weapons[k] == true end
			setSelected(all)
		elseif kind == "None" then setSelected(count == 0)
		else setSelected(weapons[kind] == true) end
	end
	local names = {}
	for _, kind in ipairs(WEAPON_ORDER) do
		if weapons[kind] then table.insert(names, kind) end
	end
	if crewSubtitle then
		local crew = crewElements()
		crewSubtitle.Text = #crew == 3 and table.concat(crew, ", ") or "be Fire, Earth, Lightning or Ice"
	end
	status.Text = ("Playing as %s (%s)   |   Weapons: %s"):format(ninja == "You" and "yourself" or ninja, myElement(),
		#names > 0 and table.concat(names, ", ") or "none")
end

local setOpen -- (below)
local built = false
local function buildCards()
	if built then return end
	built = true
	avatar = captureAvatar()

	local button, viewport, setSelected = card(0, "You", "your avatar")
	showCharacter(viewport, nil)
	characterCards.You = setSelected
	button.Activated:Connect(function() remote:FireServer("character", "You") end)
	button.Parent = characterGrid
	for i, ninja in ipairs(Roster.Ninjas) do
		button, viewport, setSelected = card(i, ninja.Name, ninja.Element, ELEMENT_COLORS[ninja.Element])
		showCharacter(viewport, ninja)
		characterCards[ninja.Name] = setSelected
		button.Activated:Connect(function() remote:FireServer("character", ninja.Name) end)
		button.Parent = characterGrid
	end

	for i, kind in ipairs(WEAPON_ORDER) do
		local W = GoldenWeapons.Weapons[kind]
		local owner = OWNER[kind]
		button, viewport, setSelected = card(i, W.ToolName:match("^%S+"), owner and (owner .. " ninja") or "time blade",
			owner and ELEMENT_COLORS[owner] or W.EnergyColor)
		showWeapon(viewport, kind)
		weaponCards[kind] = setSelected
		button.Activated:Connect(function() remote:FireServer("weapon", kind) end)
		button.Parent = weaponGrid
	end
	local disc
	button, viewport, setSelected, disc = card(#WEAPON_ORDER + 1, "All", "golden weapons")
	local icon = bladesIcon()
	icon.AnchorPoint, icon.Position, icon.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), 4
	for _, d in ipairs(icon:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex = 4 end
	end
	icon.Parent = disc
	weaponCards.All = setSelected
	button.Activated:Connect(function() remote:FireServer("weapon", "All") end)
	button.Parent = weaponGrid
	button, viewport, setSelected, disc = card(#WEAPON_ORDER + 2, "None", "no weapon")
	showNone(disc)
	weaponCards.None = setSelected
	button.Activated:Connect(function() remote:FireServer("weapon", "None") end)
	button.Parent = weaponGrid

	button, viewport = card(1, "Creation Crew", " ")
	for _, d in ipairs(button:GetChildren()) do -- the subtitle, filled in by refresh()
		if d:IsA("TextLabel") and d.Text == " " then crewSubtitle = d end
	end
	showCrew(viewport, crewElements())
	button.Activated:Connect(function()
		remote:FireServer("bots", "creation")
		task.delay(0.3, function() setOpen(false) end) -- out of the way so you can press T
	end)
	button.Parent = botGrid
	button, viewport = card(2, "Dummy", "200 HP, heals")
	showDummy(viewport, Color3.fromRGB(150, 110, 70))
	button.Activated:Connect(function() remote:FireServer("bots", "dummy") end)
	button.Parent = botGrid
	button, viewport = card(3, "Infinite", "can't die")
	showDummy(viewport, Color3.fromRGB(70, 110, 160))
	button.Activated:Connect(function() remote:FireServer("bots", "dummyInf") end)
	button.Parent = botGrid
	button, viewport = card(4, "Shatterspin", "bot to counter")
	showDummy(viewport, Color3.fromRGB(200, 20, 30))
	button.Activated:Connect(function()
		remote:FireServer("bots", "shatter")
		task.delay(0.3, function() setOpen(false) end)
	end)
	button.Parent = botGrid
	button, viewport = card(5, "Dragon Crew", "merge with them")
	showCrew(viewport, { "Fire", "Lightning" })
	button.Activated:Connect(function()
		remote:FireServer("bots", "dragoncrew")
		task.delay(0.3, function() setOpen(false) end)
	end)
	button.Parent = botGrid
	button, viewport, setSelected, disc = card(6, "Remove Bots", "crew, dummies, bots")
	showNone(disc)
	button.Activated:Connect(function() remote:FireServer("bots", "remove") end)
	button.Parent = botGrid
	refresh()
end

----------------------------------------------------------------------------------------
-- Duels page: pick two elements + who wins, or an element to fight
----------------------------------------------------------------------------------------

local DUEL_ELEMENTS = { "Fire", "Ice", "Earth", "Lightning", "Water", "Energy" }
local duelPanel = new("Frame", { Position = UDim2.fromOffset(28, 14), Size = UDim2.new(1, -46, 1, -48), BackgroundTransparency = 1,
	Visible = false, ZIndex = 2 })
duelPanel.Parent = content

-- a row of pill chips where one is picked; returns a getter for the pick
local function chipRow(y, caption, options, colors, default)
	label({ Position = UDim2.fromOffset(0, y + 6), Size = UDim2.fromOffset(70, 22), Text = caption, FontFace = SMALL, TextSize = 15,
		TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Stroke = 1, ZIndex = 3 }).Parent = duelPanel
	local picked, chips = default, {}
	local function paint()
		for value, c in pairs(chips) do
			c.button.BackgroundColor3 = value == picked and INK or PILL
			c.stroke.Transparency = value == picked and 0 or 1
		end
	end
	for i, option in ipairs(options) do
		local stroke = outline(RED, 2, 1)
		local button = new("TextButton", { Position = UDim2.fromOffset(74 + (i - 1) * 98, y), Size = UDim2.fromOffset(90, 34),
			BackgroundColor3 = PILL, Text = "", AutoButtonColor = false, ZIndex = 3 }, {
			round(), stroke,
			label({ Size = UDim2.fromScale(1, 1), Text = option[2], FontFace = LABEL, TextSize = 15,
				TextColor3 = colors and colors[option[1]] or Color3.new(1, 1, 1), Stroke = 1, ZIndex = 4 }),
		})
		button.Activated:Connect(function()
			picked = option[1]
			paint()
		end)
		button.Parent = duelPanel
		chips[option[1]] = { button = button, stroke = stroke }
	end
	paint()
	return function() return picked end
end

local function bigButton(x, y, text, onClick)
	local b = new("TextButton", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(170, 40), BackgroundColor3 = RED,
		Text = "", AutoButtonColor = false, ZIndex = 3 }, {
		round(), outline(Color3.fromRGB(120, 0, 4), 2),
		label({ Size = UDim2.fromScale(1, 1), Text = text, FontFace = TITLE, TextSize = 22, TextColor3 = Color3.new(1, 1, 1), ZIndex = 4 }),
	})
	b.Activated:Connect(onClick)
	b.Parent = duelPanel
	return b
end

local function sectionTitle(y, text)
	label({ Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(400, 26), Text = text, FontFace = LABEL, TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }).Parent = duelPanel
end

local elementOptions = {}
for _, el in ipairs(DUEL_ELEMENTS) do table.insert(elementOptions, { el, el }) end

sectionTitle(0, "NPC vs NPC")
local leftPick = chipRow(34, "Left", elementOptions, ELEMENT_COLORS, "Water")
local rightPick = chipRow(76, "Right", elementOptions, ELEMENT_COLORS, "Earth")
local winnerPick = chipRow(118, "Winner", { { "a", "Left" }, { "random", "Random" }, { "b", "Right" } }, nil, "random")
bigButton(74 + 3 * 98 + 20, 115, "START DUEL", function()
	remote:FireServer("duel", leftPick() .. "|" .. rightPick() .. "|" .. winnerPick())
	setOpen(false)
end)

sectionTitle(186, "Fight an NPC")
local fightPick = chipRow(220, "Element", elementOptions, ELEMENT_COLORS, "Fire")
bigButton(74, 266, "FIGHT", function()
	remote:FireServer("fight", fightPick())
	setOpen(false)
end)
label({ Position = UDim2.fromOffset(0, 330), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, FontFace = SMALL, TextSize = 14,
	TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Stroke = 1, ZIndex = 3,
	Text = "Beam them back to clash, then mash F. The loser gets hit by both elements. Remove Bots (Bots page) clears them." }).Parent = duelPanel

-- tab pills along the top (one per page for now, the bar is ready for more)
local function tab(text, selected)
	return new("TextButton", {
		Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = selected and INK or PILL,
		Text = "", AutoButtonColor = false,
	}, {
		round(), outline(RED, 3, selected and 0 or 1),
		new("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 28) }),
		label({ Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Text = text, FontFace = TITLE, TextSize = 27,
			TextColor3 = RED }),
	})
end

local pages = {
	{ name = "Characters", icon = ninjaIcon, tabs = { "Ninjas" }, grid = characterGrid },
	{ name = "Weapons", icon = bladesIcon, tabs = { "Golden Weapons" }, grid = weaponGrid },
	{ name = "Bots", icon = tornadoIcon, tabs = { "Bots & Dummies" }, grid = botGrid },
	{ name = "Duels", icon = clashIcon, tabs = { "Duels" }, grid = duelPanel },
}
local sideItems = {}

local function showPage(page)
	for _, p in ipairs(pages) do p.grid.Visible = p == page end
	for p, item in pairs(sideItems) do
		item.text.TextColor3 = p == page and Color3.new(1, 1, 1) or MUTED
		item.scale.Scale = p == page and 1 or 0.86
	end
	for _, child in ipairs(tabsBar:GetChildren()) do
		if child:IsA("GuiButton") then child:Destroy() end
	end
	for i, name in ipairs(page.tabs) do
		local t = tab(name, i == 1)
		t.LayoutOrder = i
		t.Parent = tabsBar
	end
end

for i, page in ipairs(pages) do
	local scale = new("UIScale")
	local icon = page.icon()
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 4)
	local text = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68), Size = UDim2.new(1, 0, 0, 24),
		Text = page.name, FontFace = LABEL, TextSize = 20, TextColor3 = MUTED })
	local item = new("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(SIDEBAR_W, 104), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false }, { scale, icon, text })
	item.Activated:Connect(function() showPage(page) end)
	item.Parent = sidebar
	sideItems[page] = { text = text, scale = scale }
end

----------------------------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------------------------

local blur = new("BlurEffect", { Name = "NinjaMenuBlur", Size = 0, Enabled = false })
blur.Parent = Lighting
local open = false

local function fit()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min((vp.X - 40) / 900, (vp.Y - 130) / 580), 0.45, 1)
end

function setOpen(on)
	if on == open then return end
	open = on
	if on then
		buildCards()
		refresh()
		panel.Visible = true
		panelScale.Scale = fit() * 0.92
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit() }):Play()
		blur.Enabled = true
		TweenService:Create(blur, QUICK, { Size = 10 }):Play()
	else
		panel.Visible = false
		TweenService:Create(blur, QUICK, { Size = 0 }):Play()
		task.delay(0.13, function() if not open then blur.Enabled = false end end)
	end
end

menuButton.Activated:Connect(function() setOpen(not open) end)
menuButton.MouseEnter:Connect(function() TweenService:Create(menuScale, QUICK, { Scale = 1.07 }):Play() end)
menuButton.MouseLeave:Connect(function() TweenService:Create(menuScale, QUICK, { Scale = 1 }):Play() end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		setOpen(not open)
	elseif input.KeyCode == Enum.KeyCode.Escape and open then
		setOpen(false)
	end
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if open then panelScale.Scale = fit() end
end)
task.spawn(function()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if open then panelScale.Scale = fit() end
		end)
	end
end)

for _, attr in ipairs({ "Ninja", "GoldenWeapon", "SpinjitzuElement" }) do
	player:GetAttributeChangedSignal(attr):Connect(function() if built then refresh() end end)
end

showPage(pages[1])
gui.Parent = player:WaitForChild("PlayerGui")
