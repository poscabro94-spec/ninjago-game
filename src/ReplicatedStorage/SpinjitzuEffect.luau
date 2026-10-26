-- SpinjitzuEffect v11.0  (ModuleScript in ReplicatedStorage)
-- Procedural Ninjago-style Spinjitzu tornado. Solid fuzzy body made of stacked discs of
-- flattened smoke smears, wrapped in spinning streak rings. Narrow at the ground, wide at
-- the top. Includes the looping sound. Rendered on every client.

local Config = require(script.Parent:WaitForChild("SpinjitzuConfig"))
local Elements = require(script.Parent:WaitForChild("SpinjitzuElements"))

local SpinjitzuEffect = {}
SpinjitzuEffect.__index = SpinjitzuEffect

local TAU = math.pi * 2
local FLAT = CFrame.Angles(math.rad(90), 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"


local function lerp(a, b, t) return a + (b - a) * t end
local function smoothstep(e0, e1, x)
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end
local function shade(c, t)
	if t >= 0 then return c:Lerp(WHITE, math.min(t, 1)) end
	return c:Lerp(BLACK, math.min(-t, 1))
end
local function easeOutCubic(x) return 1 - (1 - x) ^ 3 end
-- colour of a ColorSequence at t (used for tornadoes coloured by height)
local function sampleSeq(seq, t)
	local k = seq.Keypoints
	t = math.clamp(t, 0, 1)
	for i = 1, #k - 1 do
		if t <= k[i + 1].Time then
			local a, b = k[i], k[i + 1]
			return a.Value:Lerp(b.Value, (t - a.Time) / math.max(b.Time - a.Time, 1e-4))
		end
	end
	return k[#k].Value
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

local function newAnchor(name, parent)
	return make("Part", {
		Name = name, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, Massless = true, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
	}, parent)
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

local function getFeetOffset(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return root.Size.Y * 0.5 + 2
	end
	return humanoid.HipHeight + root.Size.Y * 0.5
end

-- Procedural limb poses (no animation assets). Rotations are in the parent part's space:
-- X = right, Y = up, -Z = forward. Arms/legs hang down, so +X rotation swings them forward.
local POSE_JOINTS = {
	RightShoulder = true, LeftShoulder = true, RightHip = true, LeftHip = true,
	Waist = true, Root = true, RightKnee = true, LeftKnee = true,
}
local JOINT_ALIAS = { RootJoint = "Root" } -- R6 name
local WHIP_POSE = {
	LeftShoulder  = CFrame.Angles(0, -0.7, 0) * CFrame.Angles(1.45, 0, 0),  -- whipped across the chest
	RightShoulder = CFrame.Angles(0, -0.5, 0) * CFrame.Angles(0, 0, 1.75),  -- flung up and back
	Waist         = CFrame.Angles(0, -0.45, 0),                             -- torso twisted into the spin
	LeftHip       = CFrame.Angles(0.4, 0, 0.28),                            -- leg stepping across
	RightHip      = CFrame.Angles(-0.1, 0, 0.05),
}
-- End sequence: the spin unwinds with arms flung out, drops into a quick crouched
-- landing, rises into the open stance, then eases back to normal.
local SPIN_OUT_POSE = {
	RightShoulder = CFrame.Angles(-0.2, 0, 1.45),  -- arms flung out by the spin
	LeftShoulder  = CFrame.Angles(-0.2, 0, -1.45),
	Waist         = CFrame.Angles(0.08, 0, 0),      -- leaning back slightly
	RightHip      = CFrame.Angles(0, 0, 0.22),
	LeftHip       = CFrame.Angles(0, 0, -0.22),
}
local CROUCH_POSE = {
	Root          = CFrame.new(0, -0.35, 0),        -- drop into the landing
	Waist         = CFrame.Angles(-0.25, 0, 0),     -- chest forward
	RightShoulder = CFrame.Angles(0.45, 0, 0.7),
	LeftShoulder  = CFrame.Angles(0.45, 0, -0.7),
	RightHip      = CFrame.Angles(0.6, 0, 0.2),
	LeftHip       = CFrame.Angles(0.6, 0, -0.2),
	RightKnee     = CFrame.Angles(-1.0, 0, 0),
	LeftKnee      = CFrame.Angles(-1.0, 0, 0),
}
local LAND_POSE = {
	RightShoulder = CFrame.Angles(0.3, 0, 0.85),    -- arms open
	LeftShoulder  = CFrame.Angles(0.3, 0, -0.85),
	RightHip      = CFrame.Angles(0, 0, 0.15),      -- feet apart
	LeftHip       = CFrame.Angles(0, 0, -0.15),
}
local END_KEYS = {
	{ 0.00, SPIN_OUT_POSE },
	{ 0.25, SPIN_OUT_POSE },
	{ 0.36, CROUCH_POSE },
	{ 0.50, CROUCH_POSE },
	{ 0.75, LAND_POSE },
	{ 0.95, LAND_POSE },
}
local END_LENGTH = 1.2 -- the last pose has eased back to normal by this point

-- pose pair + blend factor at time ts along a keyframe list
local function poseAt(keys, ts)
	if ts <= keys[1][1] then return keys[1][2], keys[1][2], 0 end
	for k = 1, #keys - 1 do
		local a, b = keys[k], keys[k + 1]
		if ts < b[1] then return a[2], b[2], smoothstep(0, 1, (ts - a[1]) / (b[1] - a[1])) end
	end
	local last = keys[#keys][2]
	return last, last, 0
end

local function mirrorPose(pose)
	local out = {}
	for key, cf in pairs(pose) do
		local rx, ry, rz = cf:ToEulerAnglesXYZ()
		local k = key:gsub("^Right", "@"):gsub("^Left", "Right"):gsub("^@", "Left")
		out[k] = CFrame.Angles(rx, -ry, -rz)
	end
	return out
end

function SpinjitzuEffect.new(character, color, highlight, elementName)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return nil end

	local self = setmetatable({}, SpinjitzuEffect)
	self.preset = elementName and Config.Presets[elementName] or nil
	local preset = self.preset or {}
	self.glow = preset.Glow or Config.Glow
	self.band = preset.Band or 0.75
	self.lightBrightness = preset.LightBrightness or Config.LightBrightness
	self.character = character
	self.root = root
	self.color = typeof(color) == "Color3" and color or Config.Color
	self.highlight = typeof(highlight) == "Color3" and highlight or shade(self.color, 0.5)
	self.deep = preset.Deep or shade(self.color, -0.45)
	self.gradient = preset.Gradient -- optional colour by height
	self.dir = (Config.SpinDirection or 1) >= 0 and 1 or -1
	self.rng = Random.new()
	self.seed = self.rng:NextNumber(0, 1000)
	self.time = 0
	self.scale = 0
	self.stopping = false
	self.alive = true

	local okScale, modelScale = pcall(function() return character:GetScale() end)
	self.size = okScale and modelScale or 1
	self.height = Config.Height * self.size
	self.rB = Config.BottomRadius * self.size
	self.rT = Config.TopRadius * self.size
	self.feetOffset = getFeetOffset(humanoid, root)

	self.motors = {}
	for _, m in ipairs(character:GetDescendants()) do
		-- classic Motor6D rigs and the newer AnimationConstraint rigs both expose .Transform
		local isMotor, isAnim = m:IsA("Motor6D"), m:IsA("AnimationConstraint")
		if isMotor or isAnim then
			local key = (m.Name:gsub(" ", ""))
			key = JOINT_ALIAS[key] or key
			local c0 = isMotor and m.C0 or (m.Attachment0 and m.Attachment0.CFrame)
			if POSE_JOINTS[key] and c0 then self.motors[key] = { motor = m, rot = c0.Rotation } end
		end
	end
	self.whipPose = self.dir > 0 and WHIP_POSE or mirrorPose(WHIP_POSE)

	self.spinners, self.scaled, self.beams, self.adorns, self.riders, self.emitters, self.bodies = {}, {}, {}, {}, {}, {}, {}

	self.folder = Instance.new("Folder")
	self.folder.Name = "Spinjitzu_" .. character.Name
	self.basePart = newAnchor("Base", self.folder)

	self:_buildBody()
	self:_buildRings()
	self:_buildParticles()
	self:_buildBase()
	self:_buildRiders()
	self:_buildElement()
	self:_applyScale(0.02)

	local baseCF = CFrame.new(root.Position - Vector3.new(0, self.feetOffset, 0))
	self.basePart.CFrame = baseCF
	self.folder.Parent = getFxFolder()

	self:_buildSound(baseCF)
	self.lean = Vector3.zero
	self.windup = Config.WindupTime or 0
	if self.windup > 0 then
		for _, pe in ipairs(self.emitters) do pe.Enabled = false end
		for _, r in ipairs(self.riders) do r.trail.Enabled = false end
	else
		self:_begin()
	end
	return self
end

-- limb poses: whip during the windup, arms-open landing after Stop. Called after the
-- Animator has run (RunService.Stepped) so it overrides walk/idle on every client.
function SpinjitzuEffect:ApplyPose()
	if not self.alive or not next(self.motors) then return end
	local poseA, poseB, a, w
	if not self.stopping then
		local p = self.windup > 0 and math.clamp(self.time / self.windup, 0, 1) or 1
		poseA, poseB, a, w = self.whipPose, self.whipPose, 0, smoothstep(0, 0.6, p)
	else
		local ts = self.time - self.stopAt
		poseA, poseB, a = poseAt(END_KEYS, ts)
		w = smoothstep(0, 0.05, ts) * (1 - smoothstep(0.95, END_LENGTH, ts))
		if self.noEndPose then w = 0 end -- going straight into the dragon
	end
	for key, j in pairs(self.motors) do
		local m = j.motor
		if m.Parent then
			-- base = the Animator's pose this frame; rigs with no Animator (NPCs) rest at identity
			local cur = m.Transform
			local base = (j.last and cur == j.last) and CFrame.identity or cur
			local out = base
			if w > 0.001 then
				local A, B = poseA[key] or CFrame.identity, poseB[key] or CFrame.identity
				out = base:Lerp(j.rot:Inverse() * A:Lerp(B, a) * j.rot, w)
			end
			if out ~= cur then m.Transform = out end
			j.last = out
		end
	end
end

-- the windup spin is over: start the tornado proper
function SpinjitzuEffect:_begin()
	self.begun = true
	for _, pe in ipairs(self.emitters) do pe.Enabled = true end
	for _, r in ipairs(self.riders) do
		r.trail.Enabled = true
		r.clear = true
	end
	if Config.HideCharacter then self:_hideCharacter() end
	if self.extraBegin then self.extraBegin() end
end

-- funnel radius at normalised height h (0 = ground, 1 = top)
function SpinjitzuEffect:_radius(h)
	h = math.clamp(h, 0, 1)
	local r = self.rB + (self.rT - self.rB) * h ^ Config.FunnelCurve
	return r * (1 - Config.TopRound * smoothstep(0.8, 1, h))
end

-- a part spinning around the tornado axis at height y (studs); h drives the sway
function SpinjitzuEffect:_spinner(name, speed, h, tilt, y)
	local sp = {
		part = newAnchor(name, self.folder), speed = speed, h = h or 0.5, y = y or 0,
		angle = self.rng:NextNumber(0, TAU), tilt = tilt or CFrame.identity,
	}
	table.insert(self.spinners, sp)
	return sp
end

function SpinjitzuEffect:_attach(parent, pos, cf)
	local att = Instance.new("Attachment")
	att.CFrame = cf or CFrame.new(pos)
	att.Parent = parent
	table.insert(self.scaled, { att, att.CFrame })
	return att
end

function SpinjitzuEffect:_emitter(parent, props)
	props.LightInfluence = 0
	local pe = make("ParticleEmitter", props, parent)
	table.insert(self.emitters, pe)
	return pe
end

-- Solid body: each slice is a spinning disc full of flattened smoke smears.
-- Colour bands alternate between the main colour and the yellow highlight.
function SpinjitzuEffect:_buildBody()
	local rng, s, d, H = self.rng, self.size, Config.Density, self.height
	local c, hi, deep = self.color, self.highlight, self.deep
	local N = Config.BodySlices
	local bandPhase = rng:NextNumber(0, TAU)

	local function slice(h, rMul, col, alpha, glow, rateMul, sizeMul)
		local r = self:_radius(h) * rMul
		local sp = self:_spinner("Body", lerp(1.6, 1.0, h) * rng:NextNumber(0.9, 1.1), h,
			CFrame.Angles(rng:NextNumber(-0.03, 0.03), 0, rng:NextNumber(-0.03, 0.03)), h * H)
		sp.part.Size = Vector3.new(r * 2, 0.2, r * 2)
		table.insert(self.bodies, { sp.part, r })
		local size = lerp(0.5, 1.3, h) * s * sizeMul
		self:_emitter(sp.part, {
			Texture = TEX_SMOKE, LockedToPart = true,
			Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Color = ColorSequence.new(col, self.gradient and col or col:Lerp(c, 0.35)),
			LightEmission = glow, Brightness = Config.Brightness,
			Size = NumberSequence.new({ kp(0, size * 0.7), kp(1, size) }),
			Squash = NumberSequence.new(-1.2),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.2, alpha), kp(0.7, alpha + 0.1), kp(1, 1) }),
			Lifetime = NumberRange.new(0.35, 0.6), Rate = lerp(30, 110, h) * d * rateMul,
			Speed = NumberRange.new(0), Rotation = NumberRange.new(-8, 8),
		})
	end

	for i = 1, N do
		local h = lerp(0.02, 0.98, (i - 0.5) / N)
		local band = (math.sin(h * TAU * 2.6 + bandPhase) * 0.5 + 0.5) ^ 8
		local col = c:Lerp(hi, band * self.band):Lerp(deep, (1 - band) * rng:NextNumber(0, 0.25))
		if self.gradient then col = sampleSeq(self.gradient, h):Lerp(WHITE, band * 0.3) end
		slice(h, 0.97, col, 0.06, self.glow * 0.5, 1.6, 0.9)
	end
	-- fuzzy flared rim at the top
	for i = 1, 6 do
		local h = lerp(0.82, 1.0, (i - 1) / 5)
		slice(h, 1.06, self.gradient and sampleSeq(self.gradient, h) or c:Lerp(deep, rng:NextNumber(0, 0.2)), 0.12, self.glow * 0.5, 1.2, 1.3)
	end
	-- darker core, seen from above and through gaps
	local coreN = math.floor(N * 0.5)
	for i = 1, coreN do
		local h = lerp(0.05, 0.97, (i - 0.5) / coreN)
		slice(h, 0.6, self.gradient and sampleSeq(self.gradient, h):Lerp(BLACK, 0.3) or deep:Lerp(c, 0.3), 0.12, 0, 0.9, 1)
	end
end

-- One motion-streak ring: an arc of curved beams around the funnel at height h.
function SpinjitzuEffect:_ring(spec)
	local rng = self.rng
	local sp = spec.spinner or self:_spinner("Ring", spec.speed, spec.h,
		CFrame.Angles(rng:NextNumber(-0.04, 0.04), 0, rng:NextNumber(-0.04, 0.04)))
	local r = self:_radius(spec.h) * spec.rMul
	local y = spec.h * self.height
	local width = math.min(spec.width, r * 0.5)
	local n = math.max(2, math.ceil(spec.span / math.rad(75)))
	local curve = (4 / 3) * math.tan(spec.span / n / 4) * r

	-- rotation moves points toward decreasing angle, so the head sits at -span
	local function point(f)
		local a = -self.dir * f * spec.span
		return Vector3.new(math.cos(a) * r, y + (f - 0.5) * spec.pitch, math.sin(a) * r)
	end
	local pts = {}
	for i = 0, n do
		local f = i / n
		local pos = point(f)
		local tangent = (point(f + 0.001) - point(f - 0.001)).Unit
		local upv = Vector3.yAxis - tangent * tangent:Dot(Vector3.yAxis)
		pts[i] = { att = self:_attach(sp.part, nil, CFrame.fromMatrix(pos, tangent, upv.Unit)), f = f, pos = pos }
	end
	local function alphaAt(f)
		local vis = smoothstep(0, 0.75, f) * (1 - smoothstep(0.9, 1, f))
		return 1 - (1 - spec.alpha) * vis
	end
	for i = 1, n do
		local A, B = pts[i - 1], pts[i]
		local w0, w1 = width * lerp(0.45, 1, A.f), width * lerp(0.45, 1, B.f)
		local beam = make("Beam", {
			Attachment0 = A.att, Attachment1 = B.att,
			FaceCamera = true, Segments = 12, CurveSize0 = curve, CurveSize1 = curve,
			LightEmission = spec.glow, LightInfluence = 0, Brightness = Config.Brightness,
			Width0 = w0, Width1 = w1,
			Transparency = NumberSequence.new(alphaAt(A.f), alphaAt(B.f)),
			Color = ColorSequence.new(spec.col0:Lerp(spec.col1, A.f ^ 1.5), spec.col0:Lerp(spec.col1, B.f ^ 1.5)),
		}, sp.part)
		table.insert(self.beams, { beam, w0, w1, curve })
	end
	return sp
end

function SpinjitzuEffect:_buildRings()
	local rng, s = self.rng, self.size
	local c, hi, deep = self.color, self.highlight, self.deep
	local N = Config.Rings
	local fine = c:Lerp(hi, 0.35):Lerp(WHITE, 0.15)
	local hiSoft = c:Lerp(hi, 0.3)
	local grad = self.gradient
	-- surface streaks + a thin bright line on each
	for i = 1, N do
		local h = math.clamp((i - rng:NextNumber(0.2, 0.8)) / N, 0.02, 1)
		local rMul, span = rng:NextNumber(1.0, 1.07), rng:NextNumber(0.5, 0.85) * TAU
		local sp = self:_ring({
			h = h, rMul = rMul, span = span,
			width = lerp(0.08, 0.22, h) * s, alpha = rng:NextNumber(0.05, 0.3),
			col0 = grad and sampleSeq(grad, h) or c, col1 = grad and sampleSeq(grad, h):Lerp(WHITE, 0.35) or hiSoft, glow = self.glow,
			speed = lerp(1.7, 1.0, h) * rng:NextNumber(0.9, 1.15), pitch = rng:NextNumber(-0.25, 0.25) * s,
		})
		local dark = i % 2 == 0
		self:_ring({
			spinner = sp, h = math.min(1, h + 0.012), rMul = rMul * 1.02, span = span * 0.8,
			width = 0.07 * s, alpha = dark and 0.15 or 0,
			col0 = grad and (dark and sampleSeq(grad, h):Lerp(BLACK, 0.35) or sampleSeq(grad, h):Lerp(WHITE, 0.3)) or (dark and deep or c:Lerp(hi, 0.3)),
			col1 = grad and (dark and sampleSeq(grad, h):Lerp(BLACK, 0.2) or sampleSeq(grad, h):Lerp(WHITE, 0.5)) or (dark and deep:Lerp(c, 0.3) or fine),
			glow = dark and 0 or math.min(1, self.glow * 1.5),
			pitch = 0,
		})
	end
	-- deeper inner swirl
	for _ = 1, math.floor(N * 0.5) do
		local h = rng:NextNumber(0.05, 0.95)
		self:_ring({
			h = h, rMul = rng:NextNumber(0.6, 0.8), span = rng:NextNumber(0.5, 0.85) * TAU,
			width = lerp(0.12, 0.3, h) * s, alpha = rng:NextNumber(0.35, 0.55),
			col0 = grad and sampleSeq(grad, h):Lerp(BLACK, 0.3) or deep, col1 = grad and sampleSeq(grad, h) or c, glow = 0,
			speed = lerp(1.9, 1.2, h) * rng:NextNumber(0.9, 1.15), pitch = rng:NextNumber(-0.2, 0.2) * s,
		})
	end
end

function SpinjitzuEffect:_buildParticles()
	local c, hi, d, s, H = self.color, self.highlight, Config.Density, self.size, self.height
	local deep = self.deep

	-- sparkles flung off the spinning surface (mostly green, a few yellow)
	local fly = self:_spinner("FlyOff", 1.1, 0.5)
	local nSpark = Config.Sparkles or 30
	local style = self.preset and self.preset.Sparks or "sparkle"
	if style == "embers" then nSpark = math.floor(nSpark * 1.4) end
	for k = 1, nSpark do
		local h = lerp(0.08, 0.98, (k - 1) / (nSpark - 1))
		local a = k * 2.4
		local r = self:_radius(h) * 0.95
		local pos = Vector3.new(math.cos(a) * r, h * H, math.sin(a) * r)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local att = self:_attach(fly.part, nil, CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -(math.pi / 2 - 0.35)))
		if style == "embers" then
			-- glowing fire flakes: flung out wide, drifting up as they cool
			self:_emitter(att, {
				Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new({ ckp(0, hi:Lerp(c, 0.3)), ckp(0.4, c), ckp(1, deep) }),
				LightEmission = 0.15, Brightness = 4,
				Size = NumberSequence.new({ kp(0, 0.2 * s), kp(1, 0.07 * s) }),
				Squash = NumberSequence.new(0.7),
				Transparency = NumberSequence.new({ kp(0, 0), kp(0.8, 0.2), kp(1, 1) }),
				Lifetime = NumberRange.new(0.8, 1.6), Rate = 10 * d, Speed = NumberRange.new(6 * s, 16 * s),
				SpreadAngle = Vector2.new(70, 70), Drag = 1.1, Acceleration = Vector3.new(0, 5, 0),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-400, 400),
			})
		elseif style == "droplets" then
			-- bright water droplets: flung out, falling back down
			self:_emitter(att, {
				Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new(WHITE:Lerp(hi, 0.4), hi), LightEmission = 0.8, Brightness = 2,
				Size = NumberSequence.new({ kp(0, 0.28 * s), kp(1, 0) }),
				Transparency = NumberSequence.new({ kp(0, 0), kp(0.7, 0.2), kp(1, 1) }),
				Lifetime = NumberRange.new(0.6, 1.1), Rate = 18 * d, Speed = NumberRange.new(5 * s, 12 * s),
				SpreadAngle = Vector2.new(45, 45), Drag = 1, Acceleration = Vector3.new(0, -10, 0),
			})
		elseif Elements.Sparks[style] then
			self:_emitter(att, Elements.Sparks[style](self, k))
		else
			self:_emitter(att, {
				Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new(k % 4 == 0 and c:Lerp(hi, 0.6) or c), LightEmission = 0.25, Brightness = 2,
				Size = NumberSequence.new({ kp(0, 0.3 * s), kp(1, 0) }),
				Transparency = NumberSequence.new({ kp(0, 0), kp(0.7, 0.2), kp(1, 1) }),
				Lifetime = NumberRange.new(0.6, 1.2), Rate = 12 * d, Speed = NumberRange.new(5 * s, 11 * s),
				SpreadAngle = Vector2.new(35, 35), Drag = 1.5, Acceleration = Vector3.new(0, 2, 0),
			})
		end
	end

	-- soft glow halo
	local glowAtt = self:_attach(fly.part, Vector3.new(0, H * 0.6, 0))
	self:_emitter(glowAtt, {
		Texture = TEX_SMOKE, LockedToPart = true,
		Color = ColorSequence.new(c), LightEmission = 1, Brightness = 1,
		Size = NumberSequence.new({ kp(0, 8 * s), kp(1, 9 * s) }),
		Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.93), kp(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.8), Rate = 6 * d, Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
	})

	-- sparks flung off the lower funnel
	local spray = self:_spinner("Spray", 1.4, 0.3)
	for k = 1, 6 do
		local a = (k - 1) / 6 * TAU
		local h = k % 2 == 0 and 0.3 or 0.55
		local r = self:_radius(h)
		local pos = Vector3.new(math.cos(a) * r, h * H, math.sin(a) * r)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local att = self:_attach(spray.part, nil, CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -(math.pi / 2 - 0.3)))
		self:_emitter(att, {
			Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(c:Lerp(hi, 0.3), c), LightEmission = 1, Brightness = 2,
			Size = NumberSequence.new({ kp(0, 0.25 * s), kp(1, 0) }),
			Lifetime = NumberRange.new(0.5, 0.8), Rate = 14 * d, Speed = NumberRange.new(8 * s, 14 * s),
			SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, -25, 0),
		})
	end

	-- hotspot where the tip touches the ground
	local tip = self:_spinner("Tip", 1.3, 0.05)
	local hotAtt = self:_attach(tip.part, Vector3.new(0, 0.4, 0))
	self:_emitter(hotAtt, {
		Texture = TEX_SMOKE, LockedToPart = true,
		Color = ColorSequence.new(c:Lerp(hi, 0.5)), LightEmission = 1, Brightness = 1.5,
		Size = NumberSequence.new({ kp(0, 2.2 * s), kp(1, 1.5 * s) }),
		Transparency = NumberSequence.new({ kp(0, 0.3), kp(1, 1) }),
		Lifetime = NumberRange.new(0.2, 0.3), Rate = 18 * d, Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
	})
end

-- element-specific extras at the base of the tornado
function SpinjitzuEffect:_buildElement()
	local kind = self.preset and self.preset.Base
	if not kind then return end
	if Elements.Build[kind] then
		Elements.Build[kind](self)
		return
	end
	local c, hi, deep, d, s, H = self.color, self.highlight, self.deep, Config.Density, self.size, self.height
	local tip = self:_spinner("ElementBase", 1.2, 0.05)

	if kind == "fire" then
		-- flames licking up the bottom of the funnel
		local spots = { { Vector3.new(0, 0.2, 0), 2.2 } }
		for k = 1, 5 do
			local a = k / 5 * TAU
			table.insert(spots, { Vector3.new(math.cos(a) * 0.9 * s, 0.15, math.sin(a) * 0.9 * s), 1.4 })
		end
		for _, spot in ipairs(spots) do
			local att = self:_attach(tip.part, spot[1])
			self:_emitter(att, {
				Texture = TEX_FIRE, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new({ ckp(0, WHITE:Lerp(hi, 0.4)), ckp(0.35, hi), ckp(0.75, c), ckp(1, deep) }),
				LightEmission = 1, Brightness = 2,
				Size = NumberSequence.new({ kp(0, spot[2] * s), kp(1, 0.2 * s) }),
				Transparency = NumberSequence.new({ kp(0, 0.2), kp(0.7, 0.4), kp(1, 1) }),
				Lifetime = NumberRange.new(0.35, 0.65), Rate = 22 * d, Speed = NumberRange.new(2 * s, 5 * s),
				SpreadAngle = Vector2.new(15, 15), Acceleration = Vector3.new(0, 6, 0),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
			})
		end
	elseif kind == "water" then
		-- glowing mist puffs + splash droplets around the tip
		for k = 1, 6 do
			local a = k / 6 * TAU
			local pos = Vector3.new(math.cos(a) * 1.3 * s, 0.3, math.sin(a) * 1.3 * s)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
			local att = self:_attach(tip.part, nil, CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -(math.pi / 2 - 0.6)))
			self:_emitter(att, {
				Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new(WHITE:Lerp(hi, 0.3), c), LightEmission = 1, Brightness = 1.5,
				Size = NumberSequence.new({ kp(0, 1.2 * s), kp(1, 3.2 * s) }),
				Transparency = NumberSequence.new({ kp(0, 0.4), kp(1, 1) }),
				Lifetime = NumberRange.new(0.5, 0.9), Rate = 10 * d, Speed = NumberRange.new(1.5 * s, 3 * s),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
			})
			self:_emitter(att, {
				Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new(WHITE:Lerp(hi, 0.3), hi), LightEmission = 0.8, Brightness = 2,
				Size = NumberSequence.new({ kp(0, 0.25 * s), kp(1, 0) }),
				Lifetime = NumberRange.new(0.4, 0.7), Rate = 12 * d, Speed = NumberRange.new(6 * s, 11 * s),
				SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, -30, 0),
			})
		end
		-- glitter swirling inside the funnel
		local glit = self:_spinner("Glitter", 1.3, 0.5)
		for k = 1, 8 do
			local h = lerp(0.15, 0.95, (k - 1) / 7)
			local a = k * 2.4
			local r = self:_radius(h) * 0.5
			local att = self:_attach(glit.part, Vector3.new(math.cos(a) * r, h * H, math.sin(a) * r))
			self:_emitter(att, {
				Texture = TEX_SPARK, LockedToPart = true, EmissionDirection = Enum.NormalId.Top,
				Color = ColorSequence.new(WHITE:Lerp(hi, 0.3)), LightEmission = 1, Brightness = 2,
				Size = NumberSequence.new({ kp(0, 0.18 * s), kp(1, 0) }),
				Lifetime = NumberRange.new(0.4, 0.8), Rate = 18 * d, Speed = NumberRange.new(0.5 * s, 1.5 * s),
				SpreadAngle = Vector2.new(180, 180),
			})
		end
	end
end

function SpinjitzuEffect:_buildBase()
	local c, hi, s = self.color, self.highlight, self.size
	local specs = {}
	for _, r in ipairs(specs) do
		local ad = make("CylinderHandleAdornment", {
			Adornee = self.basePart, Radius = r.R, InnerRadius = r.inner, Height = 0.03, Angle = r.angle,
			Color3 = r.col, Transparency = r.alpha, AlwaysOnTop = false, ZIndex = 0,
		}, self.basePart)
		table.insert(self.adorns, { adorn = ad, R = r.R, inner = r.inner, y = r.y, speed = r.speed, angle = self.rng:NextNumber(0, TAU) })
	end
	local lightAtt = self:_attach(self.basePart, Vector3.new(0, 1.5, 0))
	self.light = make("PointLight", {
		Color = c, Brightness = self.lightBrightness, Range = Config.LightRange * s, Shadows = false,
	}, lightAtt)
end

-- fast energy trails whipping around the outside, slowly climbing
function SpinjitzuEffect:_buildRiders()
	local c, hi = self.color, self.highlight
	for _ = 1, Config.Streaks do
		local a0 = Instance.new("Attachment")
		local a1 = Instance.new("Attachment")
		a0.Parent, a1.Parent = self.basePart, self.basePart
		local trail = make("Trail", {
			Attachment0 = a0, Attachment1 = a1, FaceCamera = true, Lifetime = 0.2, MinLength = 0,
			LightEmission = math.min(1, self.glow * 2), LightInfluence = 0, Brightness = Config.Brightness * 1.3,
			Color = ColorSequence.new(c:Lerp(hi, 0.5), c),
			Transparency = NumberSequence.new({ kp(0, 0), kp(1, 1) }),
			WidthScale = NumberSequence.new({ kp(0, 1), kp(1, 0.3) }),
		}, self.basePart)
		local r = { a0 = a0, a1 = a1, trail = trail, half = self.rng:NextNumber(0.05, 0.1) * self.size }
		self:_resetRider(r, true)
		table.insert(self.riders, r)
	end
end

function SpinjitzuEffect:_resetRider(r, initial)
	local rng = self.rng
	r.h = initial and rng:NextNumber(0, 1) or rng:NextNumber(-0.1, 0.05)
	r.rMul = rng:NextNumber(0.95, 1.2)
	r.speed = rng:NextNumber(0.75, 1.05)
	r.climb = rng:NextNumber(0.3, 0.6)
	r.angle = rng:NextNumber(0, TAU)
	r.clear = true
end

-- looping sound: start -> loop [LoopStart, EndStart) while active -> ending on Stop
function SpinjitzuEffect:_buildSound(baseCF)
	local soundId = self.preset and self.preset.SoundId or Config.SoundId
	local digits = tostring(soundId or ""):match("%d+")
	if not digits then return end
	self.soundPart = newAnchor("Sound", self.folder)
	self.soundPart.CFrame = baseCF
	self.sound = make("Sound", {
		SoundId = "rbxassetid://" .. digits, Volume = Config.SoundVolume, Looped = false,
		RollOffMode = Enum.RollOffMode.InverseTapered, RollOffMinDistance = 10, RollOffMaxDistance = Config.SoundRange,
	}, self.soundPart)
	self.sound:Play()
end

function SpinjitzuEffect:_applyScale(s)
	self.displayScale = s
	for _, e in ipairs(self.scaled) do
		e[1].CFrame = CFrame.new(e[2].Position * s) * e[2].Rotation
	end
	for _, b in ipairs(self.beams) do
		b[1].Width0 = b[2] * s
		b[1].Width1 = b[3] * s
		b[1].CurveSize0 = b[4] * s
		b[1].CurveSize1 = b[4] * s
	end
	for _, b in ipairs(self.bodies) do
		local w = math.max(b[2] * 2 * s, 0.05)
		b[1].Size = Vector3.new(w, 0.2, w)
	end
	for _, r in ipairs(self.adorns) do
		r.adorn.Radius = math.max(r.R * s, 0.02)
		r.adorn.InnerRadius = math.min(r.inner * s, r.adorn.Radius * 0.99)
	end
end

-- invisible character (local to each client, so everyone sees only the tornado)
function SpinjitzuEffect:_hideCharacter()
	self.hidden = {}
	local function add(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			self.hidden[d] = true
			d.LocalTransparencyModifier = 1
		end
	end
	for _, d in ipairs(self.character:GetDescendants()) do add(d) end
	self.hideConn = self.character.DescendantAdded:Connect(add)
end

-- silence the default running sound (lives in the HumanoidRootPart on every client)
function SpinjitzuEffect:_muteFootsteps()
	if not Config.MuteFootsteps or self.stopping then return end
	self.muted = self.muted or {}
	for _, snd in ipairs(self.root:GetChildren()) do
		if snd:IsA("Sound") and snd.Name == "Running" then
			if self.muted[snd] == nil then self.muted[snd] = snd.Volume end
			snd.Volume = 0
		end
	end
end

function SpinjitzuEffect:_unmuteFootsteps()
	if self.muted then
		for snd, vol in pairs(self.muted) do
			if snd.Parent then snd.Volume = vol end
		end
	end
	self.muted = nil
end

function SpinjitzuEffect:_showCharacter()
	self:_unmuteFootsteps()
	if self.hideConn then
		self.hideConn:Disconnect()
		self.hideConn = nil
	end
	if self.hidden then
		for d in pairs(self.hidden) do
			if d.Parent then d.LocalTransparencyModifier = 0 end
		end
	end
	self.hidden = nil
end

function SpinjitzuEffect:Stop()
	if self.stopping then return end
	self.stopping = true
	self.stopAt = self.time
	self:_showCharacter()
	for _, pe in ipairs(self.emitters) do pe.Enabled = false end
	if self.extraStop then self.extraStop() end
	local snd = self.sound
	if snd then
		-- jump to the "stop" part of the sound (or let it finish if already there)
		if snd.TimePosition < Config.SoundEndStart then
			snd.TimePosition = Config.SoundEndStart
		end
		if not snd.Playing then snd:Play() end
	end
end

function SpinjitzuEffect:Destroy()
	if not self.alive then return end
	self.alive = false
	self:_showCharacter()
	-- rigs without an Animator would otherwise freeze in the last pose
	for _, j in pairs(self.motors or {}) do
		if j.last and j.motor.Parent and j.motor.Transform == j.last then j.motor.Transform = CFrame.identity end
	end
	if self.folder then self.folder:Destroy() end
	self.folder = nil
end

-- returns false once the effect has finished and been destroyed
function SpinjitzuEffect:Update(dt)
	if not self.alive then return false end
	if not self.root.Parent or not self.character.Parent then
		self:Destroy()
		return false
	end
	self.time += dt
	local t = self.time
	local baseCF = CFrame.new(self.root.Position - Vector3.new(0, self.feetOffset, 0))

	-- sound: follow the player, loop while active
	local snd = self.sound
	if snd then
		self.soundPart.CFrame = baseCF
		if not self.stopping then
			if snd.TimePosition >= Config.SoundEndStart - 0.03 or (not snd.Playing and snd.IsLoaded) then
				snd.TimePosition = Config.SoundLoopStart
				if not snd.Playing then snd:Play() end
			end
		end
	end

	-- visuals already gone, just letting the stop sound finish
	if self.visualsCleared then
		if (not snd or not snd.Playing or t - self.stopAt > 2) and t - self.stopAt > END_LENGTH then
			self:Destroy()
			return false
		end
		return true
	end

	if not self.begun then
		if self.stopping then
			self.scale = 0
		elseif t >= self.windup then
			self:_begin()
		else
			return true
		end
	end
	if self.stopping and self.scale <= 0 then
		if (snd and snd.Playing) or t - self.stopAt < END_LENGTH then
			for _, child in ipairs(self.folder:GetChildren()) do
				if child ~= self.soundPart then child:Destroy() end
			end
			self.visualsCleared = true
			return true
		end
		self:Destroy()
		return false
	end

	local target = self.stopping and 0 or 1
	if self.scale ~= target then
		if target > self.scale then
			self.scale = math.min(1, self.scale + dt / Config.FadeInTime)
		else
			self.scale = math.max(0, self.scale - dt / Config.FadeOutTime)
		end
		if self.stopping and self.scale <= 0 then
			if (snd and snd.Playing) or t - self.stopAt < END_LENGTH then
				for _, child in ipairs(self.folder:GetChildren()) do
					if child ~= self.soundPart then child:Destroy() end
				end
				self.visualsCleared = true
				return true
			end
			self:Destroy()
			return false
		end
		self:_applyScale(math.max(0.02, easeOutCubic(self.scale)))
	end
	local s = self.displayScale

	self:_muteFootsteps()

	-- keep the character hidden (camera scripts can reset the modifier)
	if self.hidden then
		for d in pairs(self.hidden) do d.LocalTransparencyModifier = 1 end
	end

	-- tilt toward the direction of travel
	local vel = self.root.AssemblyLinearVelocity
	local hv = Vector3.new(vel.X, 0, vel.Z)
	local leanTarget = Vector3.zero
	if hv.Magnitude > 0.5 then
		leanTarget = Vector3.yAxis:Cross(hv.Unit) * (math.min(hv.Magnitude / Config.LeanFullSpeed, 1) * Config.LeanAngle)
	end
	self.lean = self.lean:Lerp(leanTarget, math.min(1, dt * Config.LeanSmoothing))
	local leanBase = baseCF
	if self.lean.Magnitude > 1e-4 then
		leanBase = baseCF * CFrame.fromAxisAngle(self.lean.Unit, self.lean.Magnitude)
	end
	self.basePart.CFrame = leanBase

	local spin = Config.SpinSpeed * self.dir
	local sway = Config.Sway * s
	for _, sp in ipairs(self.spinners) do
		sp.angle = (sp.angle + spin * sp.speed * dt) % TAU
		local h = sp.h
		local off = Vector3.new(math.sin(t * 1.9 + h * 2.5), 0, math.cos(t * 1.6 + h * 2.1)) * (sway * h)
		sp.part.CFrame = leanBase * CFrame.new(off + Vector3.new(0, sp.y * s, 0)) * sp.tilt * CFrame.Angles(0, sp.angle, 0)
	end
	if self.extraUpdate then self.extraUpdate(dt, leanBase, s, t) end

	for _, R in ipairs(self.adorns) do
		R.angle = (R.angle + spin * R.speed * dt) % TAU
		R.adorn.CFrame = CFrame.new(0, R.y, 0) * CFrame.Angles(0, R.angle, 0) * FLAT
	end

	local H = self.height * s
	for _, r in ipairs(self.riders) do
		r.h += r.climb * dt
		if r.h >= 1 then self:_resetRider(r, false) end
		r.angle -= spin * r.speed * lerp(1.6, 1, math.max(r.h, 0)) * dt
		local hh = math.max(r.h, 0)
		local rad = self:_radius(hh) * r.rMul * s
		local off = Vector3.new(math.sin(t * 1.9 + hh * 2.5), 0, math.cos(t * 1.6 + hh * 2.1)) * (sway * hh)
		local p = off + Vector3.new(math.cos(r.angle) * rad, hh * H, math.sin(r.angle) * rad)
		r.a0.Position = p + Vector3.new(0, r.half * s, 0)
		r.a1.Position = p - Vector3.new(0, r.half * s, 0)
		if r.clear then
			r.clear = false
			r.trail:Clear()
		end
	end

	if self.light then
		self.light.Brightness = self.lightBrightness * (0.85 + 0.2 * math.noise(t * 8, self.seed)) * s
	end
	return true
end

return SpinjitzuEffect
