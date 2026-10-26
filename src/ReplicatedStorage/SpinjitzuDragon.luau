-- SpinjitzuDragon v8.1  (ModuleScript in ReplicatedStorage)
-- Elemental dragon that appears behind the character after Spinjitzu: huge glowing bat
-- wings with bones, a long dragon head over the character's head, a neck and tail, and a big elemental
-- cloud (flames for Fire) pouring off it that trails behind when flying. No assets.
-- Rendered on every client; colours come from the element. The wing beat and pose
-- follow how fast the character is actually moving, so it looks right for everyone.

local Config = require(script.Parent:WaitForChild("SpinjitzuConfig"))

local Dragon = {}
Dragon.__index = Dragon

local WHITE = Color3.new(1, 1, 1)
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

local function lerp(a, b, t) return a + (b - a) * t end
local function smoothstep(e0, e1, x)
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end
local function approach(v, target, step)
	if v < target then return math.min(target, v + step) end
	return math.max(target, v - step)
end
local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end
local function ckp(t, c) return ColorSequenceKeypoint.new(t, c) end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		pcall(function() inst[k] = v end)
	end
	inst.Parent = parent
	return inst
end

local function newPart(className, parent, props)
	local p = Instance.new(className)
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	for k, v in pairs(props) do
		pcall(function() p[k] = v end)
	end
	p.Parent = parent
	return p
end

-- two wedges filling triangle a,b,c (all points in the same local space)
local function triangle(a, b, c, thick)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return {
		{ CFrame.fromMatrix((a + b) / 2, right, up, back), Vector3.new(thick, height, math.abs(ab:Dot(back))) },
		{ CFrame.fromMatrix((a + c) / 2, -right, up, -back), Vector3.new(thick, height, math.abs(ac:Dot(back))) },
	}
end

-- right wing outline in hinge space (x = out, y = up), studs before DragonWingScale.
-- Bat-style: leading bone rises to a peak (J), runs out to the tip (T); scalloped bottom.
local WING = {
	R0 = Vector3.new(0, 0.4, 0), R1 = Vector3.new(0.2, -1.0, 0),
	J = Vector3.new(3.4, 1.9, 0), T = Vector3.new(7.8, 1.7, 0),
	B1 = Vector3.new(6.9, -0.1, 0), B2 = Vector3.new(5.6, 0.5, 0), B3 = Vector3.new(4.4, -1.3, 0),
	B4 = Vector3.new(3.1, -0.5, 0), B5 = Vector3.new(2.0, -2.0, 0), B6 = Vector3.new(1.0, -1.1, 0),
}
local INNER = { { "R0", "J", "B3" }, { "R0", "B3", "B4" }, { "R0", "B4", "B5" }, { "R0", "B5", "B6" }, { "R0", "B6", "R1" } }
local OUTER = { { "J", "T", "B1" }, { "J", "B1", "B2" }, { "J", "B2", "B3" } }
-- where the elemental cloud pours off each wing (inner part / outer part)
local CLOUD_INNER = { "B3", "B4", "B5", "B6", "R1", "J" }
local CLOUD_OUTER = { "B1", "T", "B2" }

local TAIL_POINTS = 9

-- character poses while the dragon is out (same joint space as SpinjitzuEffect)
local POSE_JOINTS = { RightShoulder = true, LeftShoulder = true, RightHip = true, LeftHip = true, Waist = true }
local JOINT_ALIAS = { RootJoint = "Root" }
local HOVER_POSE = {
	RightShoulder = CFrame.Angles(0.1, 0, 0.45),  -- arms slightly out and down
	LeftShoulder  = CFrame.Angles(0.1, 0, -0.45),
	RightHip      = CFrame.Angles(0, 0, 0.03),    -- legs straight, together
	LeftHip       = CFrame.Angles(0, 0, -0.03),
}
local FLY_POSE = {
	RightShoulder = CFrame.Angles(-0.3, 0, 0.25),  -- arms swept back along the body
	LeftShoulder  = CFrame.Angles(-0.3, 0, -0.25),
	RightHip      = CFrame.Angles(-0.1, 0, 0.02),
	LeftHip       = CFrame.Angles(-0.1, 0, -0.02),
}

-- faceted crystal mesh head, built once per client (per colour) by DragonMeshBuilder;
-- falls back to the part head if meshes can't be made
local meshHeads = {} -- [key] = head data, or false if unavailable
local function getMeshHead(core, dark)
	if meshHeads.failed then return nil end
	-- facets fade from the core colour to the dark colour: dark = core * darkMul
	local darkMul = Color3.new(
		math.clamp(dark.R / math.max(core.R, 0.01), 0, 1),
		math.clamp(dark.G / math.max(core.G, 0.01), 0, 1),
		math.clamp(dark.B / math.max(core.B, 0.01), 0, 1))
	local key = darkMul:ToHex()
	if meshHeads[key] then return meshHeads[key] end
	local builder = script.Parent:FindFirstChild("DragonMeshBuilder")
	if not builder or Config.DragonMeshHead == false then return nil end
	local ok, res = pcall(function()
		local B = require(builder)
		local built = (B.buildFlameHead and Config.DragonHeadStyle ~= "plated") and B.buildFlameHead() or B.buildHead()
		if B.shade then B.shade(built, darkMul) end
		local part = B.toPart(built, "DragonHead")
		return { part = part, offset = part:GetAttribute("OriginOffset"), size = part.Size, lines = built.lines or {} }
	end)
	if ok then
		meshHeads[key] = res
		return res
	end
	meshHeads.failed = true
	warn("[SpinjitzuDragon] mesh head unavailable, using parts: " .. tostring(res))
	return nil
end

local function getFxFolder()
	local f = workspace:FindFirstChild("SpinjitzuFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SpinjitzuFX"
		f.Parent = workspace
	end
	return f
end

function Dragon.new(character, color, highlight, elementName)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local preset = elementName and Config.Presets[elementName] or {}

	local self = setmetatable({}, Dragon)
	self.character, self.root = character, root
	self.c = typeof(color) == "Color3" and color or Config.Color
	self.hi = typeof(highlight) == "Color3" and highlight or self.c:Lerp(WHITE, 0.5)
	self.deep = preset.Deep or self.c:Lerp(Color3.new(0, 0, 0), 0.45)
	self.kind = preset.Base or "default"
	-- Neon washes pale colours out to white, so the dragon uses a saturated version of the hue
	local h, s, v = self.c:ToHSV()
	self.glowCol = Color3.fromHSV(h, math.max(s, 0.65), math.max(v, 0.85))
	self.flakeCol = Color3.fromHSV(h, 0.9, 0.85)
	self.flakeDark = Color3.fromHSV(h, 0.95, 0.55)
	self.membraneCol = preset.DragonMembrane or self.glowCol
	self.boneCol = preset.DragonBone or WHITE:Lerp(self.glowCol, 0.35)
	self.seamCol = preset.DragonSeam or WHITE:Lerp(self.glowCol, 0.45)
	self.coreCol = preset.DragonCore or self.hi:Lerp(WHITE, 0.25)
	self.creaseCol = self.deep:Lerp(self.glowCol, 0.4)
	self.headCol = preset.DragonHead or self.glowCol
	self.haloCol = preset.DragonGlow or self.headCol:Lerp(WHITE, 0.3)
	self.flameSeq = preset.DragonFlame or ColorSequence.new({
		ckp(0, self.hi:Lerp(WHITE, 0.3)), ckp(0.45, self.glowCol), ckp(1, self.deep) })
	local okScale, modelScale = pcall(function() return character:GetScale() end)
	self.sc = (Config.DragonScale or 1) * (okScale and modelScale or 1)
	self.ws = self.sc * (Config.DragonWingScale or 1.5)
	self.t, self.flapT = 0, 0
	self.alpha, self.flyBlend, self.effort = 0, 0, 0
	self.vel = Vector3.zero
	self.phase = "rise"
	self.alive, self.stopping = true, false
	self.fadeParts, self.fadeBeams, self.emitters = {}, {}, {}

	self.motors = {}
	for _, m in ipairs(character:GetDescendants()) do
		local isMotor, isAnim = m:IsA("Motor6D"), m:IsA("AnimationConstraint")
		if isMotor or isAnim then
			local key = (m.Name:gsub(" ", ""))
			key = JOINT_ALIAS[key] or key
			local c0 = isMotor and m.C0 or (m.Attachment0 and m.Attachment0.CFrame)
			if POSE_JOINTS[key] and c0 then self.motors[key] = { motor = m, rot = c0.Rotation } end
		end
	end

	self.folder = Instance.new("Folder")
	self.folder.Name = "Dragon_" .. character.Name
	self.anchor = newPart("Part", self.folder, { Name = "Anchor", Size = Vector3.new(0.2, 0.2, 0.2) })
	self.anchor.CFrame = root.CFrame

	self.wings = { self:_buildWing(1), self:_buildWing(-1) }
	self:_buildHead()
	self:_buildTail()
	self:_buildAura()

	self.folder.Parent = getFxFolder()
	self:Update(0)
	return self
end

function Dragon:_emitter(parent, props)
	props.LightInfluence = 0
	local pe = make("ParticleEmitter", props, parent)
	table.insert(self.emitters, pe)
	return pe
end

function Dragon:_fadePart(part, base)
	table.insert(self.fadeParts, { part, base })
end

function Dragon:_fadeBeam(beam, base)
	table.insert(self.fadeBeams, { beam, base })
end

-- the big elemental cloud: flames (Fire) or tinted mist + flakes (other elements)
function Dragon:_cloud(att, mul)
	local sc = self.ws * (mul or 1)
	if self.kind == "fire" then
		self:_emitter(att, {
			Texture = TEX_FIRE, LightEmission = 1, Brightness = 3,
			Color = ColorSequence.new({ ckp(0, Color3.fromRGB(255, 230, 90)), ckp(0.35, Color3.fromRGB(255, 140, 20)), ckp(1, Color3.fromRGB(200, 30, 0)) }),
			Size = NumberSequence.new({ kp(0, 1.2 * sc), kp(0.4, 2.0 * sc), kp(1, 0.7 * sc) }),
			Transparency = NumberSequence.new({ kp(0, 0.4), kp(0.2, 0), kp(0.8, 0.3), kp(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.1), Rate = 28, Speed = NumberRange.new(0.5, 2.5),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 4, 0), Drag = 1.5,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		})
		-- dark patches between the flames
		self:_emitter(att, {
			Texture = TEX_SMOKE, LightEmission = 0, Brightness = 1, ZOffset = 0.5,
			Color = ColorSequence.new(Color3.fromRGB(45, 8, 0), Color3.fromRGB(20, 3, 0)),
			Size = NumberSequence.new({ kp(0, 0.5 * sc), kp(1, 1.1 * sc) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.6), kp(1, 1) }),
			Lifetime = NumberRange.new(0.5, 0.9), Rate = 3, Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 4, 0), Drag = 1.5,
			Rotation = NumberRange.new(0, 360),
		})
		-- embers
		self:_emitter(att, {
			Texture = TEX_SPARK, LightEmission = 1, Brightness = 3,
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 80, 10)),
			Size = NumberSequence.new({ kp(0, 0.2 * self.sc), kp(1, 0) }),
			Lifetime = NumberRange.new(0.6, 1.2), Rate = 6, Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 5, 0), Drag = 1,
		})
	else
		-- flame wisps in the element's colours
		self:_emitter(att, {
			Texture = TEX_FIRE, LightEmission = 0.6, Brightness = 3,
			Color = self.flameSeq,
			Size = NumberSequence.new({ kp(0, 0.8 * sc), kp(0.35, 1.5 * sc), kp(1, 0.5 * sc) }),
			Transparency = NumberSequence.new({ kp(0, 0.5), kp(0.2, 0.1), kp(0.75, 0.4), kp(1, 1) }),
			Lifetime = NumberRange.new(0.7, 1.3), Rate = 9, Speed = NumberRange.new(1.5, 4.5),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 3, 0), Drag = 1.5,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		})
		self:_emitter(att, {
			Texture = TEX_SPARK, Color = ColorSequence.new(self.flakeCol, self.flakeDark),
			LightEmission = 1, Brightness = 3,
			Size = NumberSequence.new({ kp(0, 0.35 * self.sc), kp(1, 0.1 * self.sc) }),
			Transparency = NumberSequence.new({ kp(0, 0.1), kp(0.7, 0.3), kp(1, 1) }),
			Lifetime = NumberRange.new(0.7, 1.3), Rate = 5, Speed = NumberRange.new(0.5, 2.5),
			SpreadAngle = Vector2.new(180, 180), Drag = 1,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
		})
	end
end

local function attachAt(entry, point)
	local a = Instance.new("Attachment")
	a.CFrame = entry.cf:Inverse() * CFrame.new(point)
	a.Parent = entry.part
	return a
end

function Dragon:_buildWing(side)
	local ws = self.ws
	local function P(name)
		local v = WING[name]
		return Vector3.new(v.X * side, v.Y, v.Z) * ws
	end
	local wing = { side = side, J = P("J"), foldAxis = (P("B3") - P("J")).Unit, inner = {}, outer = {} }

	local function addTris(list, dest)
		for _, tri in ipairs(list) do
			for _, w in ipairs(triangle(P(tri[1]), P(tri[2]), P(tri[3]), 0.05 * ws)) do
				local part = newPart("WedgePart", self.folder, { Name = "Wing", Color = self.membraneCol, Size = w[2] })
				self:_fadePart(part, 0.12)
				table.insert(dest, { part = part, cf = w[1] })
			end
		end
	end
	addTris(INNER, wing.inner)
	addTris(OUTER, wing.outer)
	local innerE, outerE = wing.inner[1], wing.outer[1]

	-- glowing bones: shoulder -> peak -> tip, plus two fingers down to the scalloped edge
	local function bone(entry, p0, p1, w0, w1)
		local beam = make("Beam", {
			Attachment0 = attachAt(entry, p0), Attachment1 = attachAt(entry, p1), FaceCamera = true, Segments = 1,
			LightEmission = 0.6, LightInfluence = 0, Brightness = 1,
			Width0 = w0 * ws, Width1 = w1 * ws, Color = ColorSequence.new(self.boneCol),
			Transparency = NumberSequence.new(1),
		}, entry.part)
		self:_fadeBeam(beam, 0.15)
	end
	bone(innerE, P("R0"), P("J"), 0.14, 0.11)
	bone(outerE, P("J"), P("T"), 0.11, 0.05)
	bone(innerE, P("J"), P("B3"), 0.08, 0.04)
	bone(outerE, P("J"), P("B1"), 0.07, 0.03)
	bone(innerE, P("J"), P("B5"), 0.06, 0.03)
	-- glowing outline along the scalloped edge
	for _, e in ipairs({ { outerE, "T", "B1" }, { outerE, "B1", "B2" }, { outerE, "B2", "B3" },
		{ innerE, "B3", "B4" }, { innerE, "B4", "B5" }, { innerE, "B5", "B6" }, { innerE, "B6", "R1" } }) do
		bone(e[1], P(e[2]), P(e[3]), 0.04, 0.04)
	end

	-- soft glow halo around the whole wing outline
	local function halo(entry, p0, p1)
		local beam = make("Beam", {
			Attachment0 = attachAt(entry, p0), Attachment1 = attachAt(entry, p1), FaceCamera = true, Segments = 1,
			LightEmission = 1, LightInfluence = 0, Brightness = 1.5,
			Width0 = 0.22 * ws, Width1 = 0.22 * ws, Color = ColorSequence.new(self.haloCol),
			Transparency = NumberSequence.new(1),
		}, entry.part)
		self:_fadeBeam(beam, 0.78)
	end
	halo(innerE, P("R0"), P("J"))
	halo(outerE, P("J"), P("T"))
	for _, e in ipairs({ { outerE, "T", "B1" }, { outerE, "B1", "B2" }, { outerE, "B2", "B3" },
		{ innerE, "B3", "B4" }, { innerE, "B4", "B5" }, { innerE, "B5", "B6" }, { innerE, "B6", "R1" } }) do
		halo(e[1], P(e[2]), P(e[3]))
	end
	-- slowly moving blotches inside the membrane (the mottled flame look)
	local blot = self.membraneCol:Lerp(Color3.fromRGB(200, 120, 0), 0.6)
	for _, list in ipairs({ wing.inner, wing.outer }) do
		for _, entry in ipairs(list) do
			self:_emitter(entry.part, {
				Texture = TEX_SMOKE, LockedToPart = true,
				Color = ColorSequence.new(blot), LightEmission = 0, Brightness = 1,
				Size = NumberSequence.new({ kp(0, 0.5 * ws), kp(1, 0.9 * ws) }),
				Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.3), kp(1, 1) }),
				Lifetime = NumberRange.new(0.8, 1.5), Rate = 3, Speed = NumberRange.new(0),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
			})
		end
	end
	-- elemental cloud pouring off the wing (world space, so it trails when flying)
	for _, name in ipairs(CLOUD_INNER) do self:_cloud(attachAt(innerE, P(name)), 1) end
	for _, name in ipairs(CLOUD_OUTER) do self:_cloud(attachAt(outerE, P(name)), 0.9) end
	return wing
end

-- head shape (studs before DragonHeadScale): rings of a tapered skull -> snout, -Z = snout
local HEAD_RINGS = {
	{ z = 0.55, w = 1.35, h = 1.15 },
	{ z = 0, w = 1.75, h = 1.5 },
	{ z = -1.4, w = 1.55, h = 1.2 },
	{ z = -3.0, w = 1.2, h = 0.9 },
	{ z = -3.9, w = 0.9, h = 0.6 },
}
local HEAD_BACK = Vector3.new(0, 0.05, 1.0)
local HEAD_TIP = Vector3.new(0, -0.1, -4.25)
local HEAD_RIDGE = { { 0.4, 0.68, 0.35 }, { -0.4, 0.8, 0.38 }, { -1.2, 0.68, 0.3 }, { -2.1, 0.58, 0.24 } } -- z, y, height

local function headRing(r)
	local w, h, z = r.w, r.h, r.z
	return {
		Vector3.new(0, 0.55 * h, z), Vector3.new(0.5 * w, 0.2 * h, z), Vector3.new(0.42 * w, -0.32 * h, z),
		Vector3.new(0, -0.5 * h, z), Vector3.new(-0.42 * w, -0.32 * h, z), Vector3.new(-0.5 * w, 0.2 * h, z),
	}
end

function Dragon:_buildMeshHead(mh)
	local hs = self.sc * (Config.DragonHeadScale or 1)
	self.hs = hs
	local head = {}
	local center = CFrame.identity -- EditableMesh parts keep the mesh origin at the part centre
	-- solid glowing head in the element colour, with a soft glow halo around it
	local core = mh.part:Clone()
	core.Size = mh.size * hs
	core.Material = Enum.Material.Neon
	core.Color = self.headCol
	core.Transparency = 1
	core.Parent = self.folder
	self:_fadePart(core, 0)
	table.insert(head, { part = core, cf = center })
	local shell = mh.part:Clone()
	shell.Name = "DragonHeadGlow"
	shell.Size = mh.size * hs * 1.1
	shell.Material = Enum.Material.Neon
	shell.Color = self.haloCol
	shell.Transparency = 1
	shell.Parent = self.folder
	self:_fadePart(shell, 0.85)
	table.insert(head, { part = shell, cf = center })
	self.head = head
	self.headFx = Instance.new("Attachment")
	self.headFx.Parent = self.anchor
	self:_cloud(self.headFx, 0.7)
end

function Dragon:_buildHead()
	local mh = getMeshHead(self.headCol, self.headCol:Lerp(Color3.new(0, 0, 0), 0.18))
	if mh then return self:_buildMeshHead(mh) end
	local hs = self.sc * (Config.DragonHeadScale or 1.1)
	self.hs = hs
	local head = {}
	local function tri(a, b, c, col, base, thick)
		for _, w in ipairs(triangle(a * hs, b * hs, c * hs, (thick or 0.06) * hs)) do
			local part = newPart("WedgePart", self.folder, { Name = "Head", Color = col, Size = w[2] })
			self:_fadePart(part, base)
			table.insert(head, { part = part, cf = w[1] })
		end
	end
	local col, dark = self.glowCol, self.boneCol
	-- skull -> snout, built as a closed tapered shell of triangles
	local rings = {}
	for i, r in ipairs(HEAD_RINGS) do rings[i] = headRing(r) end
	local n = #rings[1]
	for k = 1, n do
		local k2 = k % n + 1
		tri(HEAD_BACK, rings[1][k2], rings[1][k], col, 0.05)
		for i = 1, #rings - 1 do
			local a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k], rings[i + 1][k2]
			tri(a, b, d, col, 0.05)
			tri(a, d, c, col, 0.05)
		end
		tri(rings[#rings][k], rings[#rings][k2], HEAD_TIP, col, 0.05)
	end
	-- horns swept back, and a spiky ridge along the top
	for _, sd in ipairs({ 1, -1 }) do
		tri(Vector3.new(0.35 * sd, 0.72, 0.05), Vector3.new(0.75 * sd, 0.28, 0.4), Vector3.new(0.95 * sd, 1.0, 2.3), dark, 0.05, 0.16)
	end
	for _, r in ipairs(HEAD_RIDGE) do
		local z, y, hgt = r[1], r[2], r[3]
		tri(Vector3.new(0, y - 0.05, z - 0.35), Vector3.new(0, y - 0.05, z + 0.35), Vector3.new(0, y + hgt, z + 0.45), dark, 0.05, 0.1)
	end
	-- lower jaw, hanging slightly open
	local jaw = CFrame.new(0, -0.45, -1.0) * CFrame.Angles(-0.22, 0, 0)
	local jL0, jR0 = jaw * Vector3.new(-0.6, 0, 0), jaw * Vector3.new(0.6, 0, 0)
	local jL1, jR1 = jaw * Vector3.new(-0.4, 0, -2.5), jaw * Vector3.new(0.4, 0, -2.5)
	local jT = jaw * Vector3.new(0, 0, -3.0)
	tri(jL0, jR0, jL1, col, 0.05, 0.22)
	tri(jR0, jR1, jL1, col, 0.05, 0.22)
	tri(jL1, jR1, jT, col, 0.05, 0.22)
	-- glowing eyes
	for _, sd in ipairs({ 1, -1 }) do
		local part = newPart("Part", self.folder, { Name = "Eye", Shape = Enum.PartType.Ball, Color = WHITE, Size = Vector3.new(0.26, 0.26, 0.26) * hs })
		self:_fadePart(part, 0)
		table.insert(head, { part = part, cf = CFrame.new(Vector3.new(0.76 * sd, 0.3, -1.1) * hs) })
	end
	self.head = head
	-- flames licking off the head
	self.headFx = Instance.new("Attachment")
	self.headFx.Parent = self.anchor
	self:_cloud(self.headFx, 0.7)
end

function Dragon:_buildTail()
	local sc = self.sc
	-- neck: from the back up to the head, then tail points down behind the legs
	self.neck0 = Instance.new("Attachment")
	self.neck0.Position = Vector3.new(0, 1.0 * sc, 0.7 * sc)
	self.neck0.Parent = self.anchor
	self.neck1 = Instance.new("Attachment")
	self.neck1.Parent = self.anchor
	local neck = make("Beam", {
		Attachment0 = self.neck0, Attachment1 = self.neck1, FaceCamera = true, Segments = 1,
		LightEmission = 1, LightInfluence = 0, Brightness = 1.6,
		Width0 = 1.5 * sc, Width1 = 1.2 * sc, Color = ColorSequence.new(self.membraneCol, self.headCol),
		Transparency = NumberSequence.new(1),
	}, self.anchor)
	self:_fadeBeam(neck, 0.15)
	-- glowing chevrons up the front of the neck
	self.chevrons = {}
	for i = 1, 4 do
		local c = { Instance.new("Attachment"), Instance.new("Attachment"), Instance.new("Attachment") }
		for _, at in ipairs(c) do at.Parent = self.anchor end
		for j = 1, 2 do
			local beam = make("Beam", {
				Attachment0 = c[j == 1 and 1 or 3], Attachment1 = c[2], FaceCamera = true, Segments = 1,
				LightEmission = 1, LightInfluence = 0, Brightness = 3,
				Width0 = 0.1 * sc, Width1 = 0.1 * sc, Color = ColorSequence.new(self.seamCol),
				Transparency = NumberSequence.new(1),
			}, self.anchor)
			self:_fadeBeam(beam, 1)
		end
		self.chevrons[i] = c
	end

	self.tail = {}
	for k = 1, TAIL_POINTS do
		local a = Instance.new("Attachment")
		a.Parent = self.anchor
		self.tail[k] = a
	end
	local c0, c1 = self.headCol, self.membraneCol
	for k = 1, TAIL_POINTS - 1 do
		local f0, f1 = (k - 1) / (TAIL_POINTS - 1), k / (TAIL_POINTS - 1)
		local beam = make("Beam", {
			Attachment0 = self.tail[k], Attachment1 = self.tail[k + 1], FaceCamera = true, Segments = 4,
			LightEmission = 1, LightInfluence = 0, Brightness = 1.6,
			Width0 = lerp(2.2, 0.1, f0) * sc, Width1 = lerp(2.2, 0.1, f1) * sc,
			Color = ColorSequence.new(c0:Lerp(c1, f0), c0:Lerp(c1, f1)),
			Transparency = NumberSequence.new(1),
		}, self.anchor)
		self:_fadeBeam(beam, 0.15)
	end
	-- bright glowing tail tip
	self:_emitter(self.tail[TAIL_POINTS], {
		Texture = TEX_SPARK, LockedToPart = true, Color = ColorSequence.new(WHITE:Lerp(self.hi, 0.3)),
		LightEmission = 1, Brightness = 4,
		Size = NumberSequence.new({ kp(0, 1.0 * sc), kp(1, 0.6 * sc) }),
		Transparency = NumberSequence.new({ kp(0, 0.2), kp(1, 1) }),
		Lifetime = NumberRange.new(0.15, 0.25), Rate = 30, Speed = NumberRange.new(0),
	})
	for _, k in ipairs({ 2, 4, 6 }) do self:_cloud(self.tail[k], 0.8) end
	for _, k in ipairs({ 3, 7 }) do
		self:_emitter(self.tail[k], {
			Texture = TEX_SPARK, Color = ColorSequence.new(WHITE:Lerp(self.hi, 0.3)), LightEmission = 1, Brightness = 2,
			Size = NumberSequence.new({ kp(0, 0.25 * sc), kp(1, 0) }),
			Lifetime = NumberRange.new(0.4, 0.9), Rate = 12, Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
		})
	end
end

function Dragon:_buildAura()
	local sc = self.sc
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 0.5 * sc, 0.4 * sc)
	att.Parent = self.anchor
	self.aura = self:_emitter(att, {
		Texture = self.kind == "fire" and TEX_FIRE or TEX_SPARK,
		Color = ColorSequence.new(self.flakeCol, self.flakeDark),
		LightEmission = 1, Brightness = 3,
		Size = NumberSequence.new({ kp(0, 0.6 * sc), kp(1, 0.15 * sc) }),
		Lifetime = NumberRange.new(0.6, 1.2), Rate = 10, Speed = NumberRange.new(4 * sc, 9 * sc),
		SpreadAngle = Vector2.new(180, 180), Drag = 2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
	})
	self.light = make("PointLight", { Color = self.glowCol, Brightness = 3, Range = 22 * sc, Shadows = false }, att)
	-- burst when the dragon appears
	task.defer(function()
		if self.aura and self.aura.Parent then self.aura:Emit(50) end
	end)
end

-- "rise" (going straight up), "fly" (free flight), "land" (bots coming back down)
function Dragon:SetPhase(phase)
	self.phase = phase
end

-- limb pose while the dragon is out; call after the Animator has run (RunService.Stepped)
function Dragon:ApplyPose()
	if not self.alive or not next(self.motors) then return end
	local w = smoothstep(0, 1, self.alpha)
	for key, j in pairs(self.motors) do
		local m = j.motor
		if m.Parent then
			local cur = m.Transform
			local base = (j.last and cur == j.last) and CFrame.identity or cur
			local out = base
			if w > 0.001 then
				local A, B = HOVER_POSE[key] or CFrame.identity, FLY_POSE[key] or CFrame.identity
				out = base:Lerp(j.rot:Inverse() * A:Lerp(B, self.flyBlend) * j.rot, w)
			end
			if out ~= cur then m.Transform = out end
			j.last = out
		end
	end
end

function Dragon:Stop()
	if self.stopping then return end
	self.stopping = true
	for _, pe in ipairs(self.emitters) do pe.Enabled = false end
end

function Dragon:Destroy()
	if not self.alive then return end
	self.alive = false
	for _, j in pairs(self.motors) do
		if j.last and j.motor.Parent and j.motor.Transform == j.last then j.motor.Transform = CFrame.identity end
	end
	if self.folder then self.folder:Destroy() end
	self.folder = nil
end

function Dragon:Update(dt)
	if not self.alive then return false end
	if not self.root.Parent or not self.character.Parent then
		self:Destroy()
		return false
	end
	self.t += dt
	local t, sc, ws = self.t, self.sc, self.ws

	-- fade in / out
	local prev = self.alpha
	self.alpha = approach(self.alpha, self.stopping and 0 or 1, dt / (self.stopping and 0.35 or 0.45))
	if self.stopping and self.alpha <= 0 then
		self:Destroy()
		return false
	end
	local a = self.alpha
	if a ~= prev or dt == 0 then
		for _, fp in ipairs(self.fadeParts) do fp[1].Transparency = 1 - (1 - fp[2]) * a end
		for _, fb in ipairs(self.fadeBeams) do fb[1].Transparency = NumberSequence.new(1 - (1 - fb[2]) * a) end
	end

	-- how fast are we really moving? (works for you, other players and bots alike)
	local rootCF = self.root.CFrame
	local pos = rootCF.Position
	if self.lastPos and dt > 0 then
		local v = (pos - self.lastPos) / dt
		if v.Magnitude < 400 then self.vel = self.vel:Lerp(v, math.min(1, dt * 6)) end
	end
	self.lastPos = pos
	local horiz = Vector3.new(self.vel.X, 0, self.vel.Z).Magnitude
	local speed = self.vel.Magnitude

	local flyTarget, effortTarget = 0, 0.3
	if self.phase == "rise" then
		effortTarget = 1
	elseif self.phase == "fly" then
		flyTarget = math.clamp(horiz / 25, 0, 1)
		effortTarget = math.max(0.3, math.clamp(speed / 20, 0, 1))
	elseif self.phase == "land" then
		effortTarget = 0.5
	end
	self.flyBlend = approach(self.flyBlend, flyTarget, dt * 2.5)
	self.effort = approach(self.effort, effortTarget, dt * 2)
	local effort = smoothstep(0, 1, self.effort)

	self.anchor.CFrame = rootCF

	-- wing beat: gentle flutter when hovering -> big flaps when climbing / flying
	self.flapT += dt * lerp(2.2, Config.DragonFlapSpeed or 6, effort)
	local beat = math.sin(self.flapT)
	local flap = beat * lerp(0.12, 0.55, effort) + 0.1 - (1 - smoothstep(0, 1, a)) * 1.2
	local fold = math.max(0, -math.sin(self.flapT - 0.6)) * lerp(0.08, 0.6, effort)
	local parts, cfs = {}, {} -- moved together with one BulkMoveTo
	for _, wing in ipairs(self.wings) do
		local side = wing.side
		local hinge = rootCF * CFrame.new(side * 0.5 * sc, 1.25 * sc, 0.75 * sc)
			* CFrame.Angles(0, -side * 0.25, 0) * CFrame.Angles(0, 0, side * flap)
		for _, e in ipairs(wing.inner) do
			table.insert(parts, e.part)
			table.insert(cfs, hinge * e.cf)
		end
		local elbow = hinge * CFrame.new(wing.J) * CFrame.fromAxisAngle(wing.foldAxis, fold) * CFrame.new(-wing.J)
		for _, e in ipairs(wing.outer) do
			table.insert(parts, e.part)
			table.insert(cfs, elbow * e.cf)
		end
	end

	-- head: just above the character's head, snout forward and a little up when hovering
	-- (looks like a pointed hood from the front), straight ahead when flying
	local hs = self.hs
	local fb = self.flyBlend
	local pitch = lerp(0.3, 1.3, fb) + math.sin(t * 2) * 0.04 + beat * 0.03 * effort
	local headLocal = CFrame.new(0, lerp(3.6, 3.2, fb) * sc, lerp(0.5, 0.3, fb) * sc) * CFrame.Angles(pitch, 0, 0)
	local headCF = rootCF * headLocal
	for _, e in ipairs(self.head) do
		table.insert(parts, e.part)
		table.insert(cfs, headCF * e.cf)
	end
	self.neck1.CFrame = headLocal * CFrame.new(0, -0.3 * hs, 0.9 * hs)
	if self.chevrons then
		local n0, n1 = self.neck0.Position, self.neck1.Position
		local dir = n1 - n0
		local len = dir.Magnitude
		dir = len > 1e-3 and dir / len or Vector3.yAxis
		local side = Vector3.xAxis
		local front = dir:Cross(side)
		for i, c in ipairs(self.chevrons) do
			local f = i / (#self.chevrons + 1)
			local w = lerp(0.85, 0.55, f) * sc
			local p = n0 + dir * len * f + front * 0.35 * sc
			c[1].Position = p - side * w - dir * 0.3 * sc
			c[2].Position = p + dir * 0.15 * sc
			c[3].Position = p + side * w - dir * 0.3 * sc
		end
	end
	self.headFx.CFrame = headLocal * CFrame.new(0, 0, -1.6 * hs)
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	-- tail sways (and whips more in flight)
	local n = TAIL_POINTS
	for k = 1, n do
		local f = (k - 1) / (n - 1)
		local sway = math.sin(t * lerp(2.5, 5, effort) - k * 0.6) * lerp(0.35, 0.6, effort) * f
		self.tail[k].Position = Vector3.new(sway * sc, (-0.8 - f * 7.5) * sc, (0.7 + f * 1.4 + math.cos(t * 2 - k) * 0.15 * f) * sc)
	end

	if self.light then
		self.light.Brightness = 3 * a * (0.85 + 0.15 * math.sin(t * 7))
	end
	return true
end

return Dragon
