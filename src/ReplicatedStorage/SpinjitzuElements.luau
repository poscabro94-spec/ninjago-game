-- SpinjitzuElements v2.9  (ModuleScript in ReplicatedStorage)
-- Element-specific extras for the Spinjitzu tornado: Lightning arcs, Earth rock particles +
-- faint dust, Ice frost, and the matching spark styles. Used by SpinjitzuEffect.

local Config = require(script.Parent:WaitForChild("SpinjitzuConfig"))

local Elements = { Sparks = {}, Build = {} }

local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		pcall(function() inst[k] = v end)
	end
	inst.Parent = parent
	return inst
end

----------------------------------------------------------------------------------------
-- spark styles (the particles flung off the tornado surface)
----------------------------------------------------------------------------------------

-- quick electric sparks
function Elements.Sparks.electric(fx)
	local hi, s, d = fx.highlight, fx.size, Config.Density
	return {
		Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(WHITE:Lerp(hi, 0.35), hi), LightEmission = 1, Brightness = 3,
		Size = NumberSequence.new({ kp(0, 0.22 * s), kp(1, 0) }),
		Transparency = NumberSequence.new({ kp(0, 0), kp(1, 1) }),
		Lifetime = NumberRange.new(0.2, 0.45), Rate = 10 * d, Speed = NumberRange.new(8 * s, 16 * s),
		SpreadAngle = Vector2.new(50, 50), Drag = 3,
	}
end

-- small rock bits flicked off the funnel, falling back down
function Elements.Sparks.dust(fx)
	local c, hi, s, d = fx.color, fx.highlight, fx.size, Config.Density
	return {
		Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(hi:Lerp(c, 0.3), c), LightEmission = 0.2, Brightness = 1.8,
		Size = NumberSequence.new({ kp(0, 0.35 * s), kp(1, 0.25 * s) }),
		Transparency = NumberSequence.new({ kp(0, 0.05), kp(0.7, 0.2), kp(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1), Rate = 4 * d, Speed = NumberRange.new(5 * s, 11 * s),
		SpreadAngle = Vector2.new(40, 40), Drag = 1, Acceleration = Vector3.new(0, -18, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
	}
end

-- snowflakes drifting off and floating down
function Elements.Sparks.snow(fx)
	local hi, s, d = fx.highlight, fx.size, Config.Density
	return {
		Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(WHITE, hi:Lerp(fx.color, 0.5)), LightEmission = 0.4, Brightness = 1.6,
		Size = NumberSequence.new({ kp(0, 0.22 * s), kp(1, 0) }),
		Transparency = NumberSequence.new({ kp(0, 0.1), kp(0.7, 0.3), kp(1, 1) }),
		Lifetime = NumberRange.new(1.0, 1.8), Rate = 8 * d, Speed = NumberRange.new(3 * s, 8 * s),
		SpreadAngle = Vector2.new(60, 60), Drag = 2, Acceleration = Vector3.new(0, -3, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
	}
end

----------------------------------------------------------------------------------------
-- shared pieces
----------------------------------------------------------------------------------------

-- every element registers objects with begin(fx) / update(fx, dt, leanBase, s, t) / stop(fx)
local function install(fx, obj)
	fx.extras = fx.extras or {}
	table.insert(fx.extras, obj)
	if fx.extraBegin then return end
	fx.extraBegin = function()
		for _, o in ipairs(fx.extras) do if o.begin then o.begin(fx) end end
	end
	fx.extraUpdate = function(dt, leanBase, s, t)
		for _, o in ipairs(fx.extras) do if o.update then o.update(fx, dt, leanBase, s, t) end end
	end
	fx.extraStop = function()
		for _, o in ipairs(fx.extras) do if o.stop then o.stop(fx) end end
	end
end

-- solid chunks (ice shards) orbiting the funnel and tumbling
local function addDebris(fx, opts)
	local rng = fx.rng
	local list = {}
	for _ = 1, opts.count do
		local sz = rng:NextNumber(opts.sizeMin, opts.sizeMax)
		local size = opts.shard and Vector3.new(sz * 0.35, sz * 1.6, sz * 0.35)
			or Vector3.new(sz * rng:NextNumber(0.8, 1.2), sz * rng:NextNumber(0.7, 1.1), sz * rng:NextNumber(0.8, 1.2))
		local part = make("Part", {
			Name = "Debris", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false, Massless = true, Material = opts.material,
			Color = opts.colors[rng:NextInteger(1, #opts.colors)], Size = size * fx.size, Transparency = 1,
		}, fx.folder)
		table.insert(list, {
			part = part, size = size * fx.size, h = rng:NextNumber(opts.hMin, opts.hMax),
			angle = rng:NextNumber(0, TAU), speed = rng:NextNumber(0.45, 0.8), rMul = rng:NextNumber(opts.rMin, opts.rMax),
			rot = CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), rng:NextNumber(0, TAU)),
			axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
			spinRate = rng:NextNumber(3, 8), bob = rng:NextNumber(0, TAU), bobRate = rng:NextNumber(1.5, 3),
		})
	end
	install(fx, {
		begin = function()
			for _, r in ipairs(list) do r.part.Transparency = opts.alpha or 0 end
		end,
		update = function(fx2, dt, leanBase, s, t)
			local spin = Config.SpinSpeed * fx2.dir
			local H = fx2.height * s
			for _, r in ipairs(list) do
				if r.part.Parent then
					r.angle = (r.angle + spin * r.speed * dt) % TAU
					local h = math.clamp(r.h + math.sin(t * r.bobRate + r.bob) * 0.05, 0.03, 1)
					local rad = fx2:_radius(h) * r.rMul * s
					local pos = (leanBase * CFrame.Angles(0, r.angle, 0) * CFrame.new(rad, h * H, 0)).Position
					r.rot = r.rot * CFrame.fromAxisAngle(r.axis, r.spinRate * dt)
					r.part.CFrame = CFrame.new(pos) * r.rot
					r.part.Size = r.size * math.max(s, 0.05)
				end
			end
		end,
	})
end

-- particles riding a spinning ring on the funnel surface (they orbit with the tornado)
local function surfaceRing(fx, h, rMul, count, props)
	local r = fx:_radius(h) * rMul
	local sp = fx:_spinner("Surface", (1.6 - 0.6 * h) * fx.rng:NextNumber(0.9, 1.1), h)
	local off = fx.rng:NextNumber(0, TAU)
	for k = 1, count do
		local a = off + k / count * TAU
		local att = fx:_attach(sp.part, Vector3.new(math.cos(a) * r, h * fx.height, math.sin(a) * r))
		local p = table.clone(props)
		p.LockedToPart = true
		p.Speed = p.Speed or NumberRange.new(0)
		fx:_emitter(att, p)
	end
end

----------------------------------------------------------------------------------------
-- LIGHTNING
----------------------------------------------------------------------------------------

local BOLT_POINTS = 7 -- corners per bolt: straight segments = jagged zig-zag

-- a short arc starting on the funnel surface, mostly hugging it / reaching for the ground
local function boltPath(fx, b, s)
	local rng = fx.rng
	local low = rng:NextNumber() < 0.7
	local h = low and rng:NextNumber(0.02, 0.45) or rng:NextNumber(0.45, 1)
	local a = rng:NextNumber(0, TAU)
	local r = fx:_radius(h) * s
	local out = Vector3.new(math.cos(a), 0, math.sin(a))
	local tan = Vector3.new(-math.sin(a), 0, math.cos(a))
	local vert = low and rng:NextNumber(-1, 0.3) or rng:NextNumber(-0.3, 1)
	local dir = (out * rng:NextNumber(0.3, 0.8) + tan * rng:NextNumber(-1, 1) + Vector3.yAxis * vert).Unit
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 1e-3 then side = Vector3.xAxis end
	side = side.Unit
	b.start = out * r + Vector3.new(0, h * fx.height * s, 0)
	b.dir, b.side, b.up = dir, side, side:Cross(dir).Unit
	b.len = rng:NextNumber(2.2, 4.5) * s
	b.s = s
end

-- zig-zag: every corner kicks out to alternating sides by a random amount
local function boltJitter(fx, b)
	local rng = fx.rng
	local j0 = 0.32 * b.s
	for k = 1, BOLT_POINTS do
		local f = (k - 1) / (BOLT_POINTS - 1)
		local p = b.start + b.dir * b.len * f
		if k > 1 then
			local alt = (k % 2 == 0) and 1 or -1
			p += b.side * alt * j0 * rng:NextNumber(0.4, 1.2) + b.up * rng:NextNumber(-j0, j0) * 0.6
		end
		if p.Y < 0.05 then p = Vector3.new(p.X, 0.05, p.Z) end -- stop at the ground
		b.pts[k].Position = p
	end
end

function Elements.Build.lightning(fx)
	local c, hi, d, s = fx.color, fx.highlight, Config.Density, fx.size
	local rng = fx.rng
	local core = WHITE:Lerp(hi, 0.2)

	-- bright glow where the tip touches the ground
	local tip = fx:_spinner("ElementBase", 1.2, 0.05)
	local att = fx:_attach(tip.part, Vector3.new(0, 0.4, 0))
	fx:_emitter(att, {
		Texture = TEX_SMOKE, LockedToPart = true,
		Color = ColorSequence.new(core), LightEmission = 1, Brightness = 3,
		Size = NumberSequence.new({ kp(0, 2.4 * s), kp(1, 1.6 * s) }),
		Transparency = NumberSequence.new({ kp(0, 0.15), kp(1, 1) }),
		Lifetime = NumberRange.new(0.15, 0.25), Rate = 24 * d, Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
	})

	-- bright electric flashes on the surface (mostly the lower half)
	for i = 1, 5 do
		local h = 0.08 + (i - 1) * 0.12
		surfaceRing(fx, h, 1.02, 4, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(WHITE:Lerp(hi, 0.4)), LightEmission = 1, Brightness = 2.5,
			Size = NumberSequence.new({ kp(0, 0.9 * s), kp(1, 1.4 * s) }),
			Transparency = NumberSequence.new({ kp(0, 0.35), kp(1, 1) }),
			Lifetime = NumberRange.new(0.08, 0.18), Rate = 2 * d,
			Rotation = NumberRange.new(0, 360),
		})
	end

	-- thin jagged lightning bolts that flicker on and off around the funnel
	local bolts = {}
	for _ = 1, 20 do
		local pts = {}
		for k = 1, BOLT_POINTS do
			local a = Instance.new("Attachment")
			a.Parent = fx.basePart
			pts[k] = a
		end
		local beams = {}
		for k = 1, BOLT_POINTS - 1 do
			table.insert(beams, { make("Beam", {
				Attachment0 = pts[k], Attachment1 = pts[k + 1], FaceCamera = true, Segments = 1,
				LightEmission = 1, LightInfluence = 0, Brightness = 4,
				Color = ColorSequence.new(core), Transparency = NumberSequence.new(0), Enabled = false,
			}, fx.basePart), 0.07 })
			table.insert(beams, { make("Beam", {
				Attachment0 = pts[k], Attachment1 = pts[k + 1], FaceCamera = true, Segments = 1,
				LightEmission = 1, LightInfluence = 0, Brightness = 2,
				Color = ColorSequence.new(c:Lerp(hi, 0.5)), Transparency = NumberSequence.new(0.55), Enabled = false,
			}, fx.basePart), 0.3 })
		end
		table.insert(bolts, { pts = pts, beams = beams, on = false, t = rng:NextNumber(0, 0.3), jit = 0 })
	end

	local active = false
	local function setOn(b, on)
		b.on = on
		for i, bm in ipairs(b.beams) do
			if on then
				-- taper along the arc
				local seg = math.floor((i - 1) / 2)
				local f0, f1 = seg / (BOLT_POINTS - 1), (seg + 1) / (BOLT_POINTS - 1)
				local w = bm[2] * b.s
				bm[1].Width0, bm[1].Width1 = w * (1 - 0.6 * f0), w * (1 - 0.6 * f1)
			end
			bm[1].Enabled = on
		end
	end

	install(fx, {
		begin = function() active = true end,
		stop = function()
			active = false
			for _, b in ipairs(bolts) do setOn(b, false) end
		end,
		update = function(fx2, dt, _, s2)
			if not active then return end
			for _, b in ipairs(bolts) do
				b.t -= dt
				if b.t <= 0 then
					if b.on then
						setOn(b, false)
						b.t = rng:NextNumber(0.05, 0.35)
					else
						boltPath(fx2, b, s2)
						boltJitter(fx2, b)
						setOn(b, true)
						b.t = rng:NextNumber(0.08, 0.22)
						b.jit = 0.05
					end
				elseif b.on then
					b.jit -= dt
					if b.jit <= 0 then
						boltJitter(fx2, b)
						b.jit = 0.05
					end
				end
			end
		end,
	})
end

----------------------------------------------------------------------------------------
-- EARTH
----------------------------------------------------------------------------------------

function Elements.Build.earth(fx)
	local c, hi, deep, d, s = fx.color, fx.highlight, fx.deep, Config.Density, fx.size
	local rng = fx.rng
	local dustCol = WHITE:Lerp(hi, 0.25)

	-- rock particles swirling around the funnel (round golden-brown chunks)
	for i = 1, 10 do
		local h = 0.08 + (i - 1) * 0.095
		local col = ({ hi, hi:Lerp(c, 0.5), c, c:Lerp(deep, 0.35) })[rng:NextInteger(1, 4)]
		surfaceRing(fx, h, rng:NextNumber(1.08, 1.18), 4, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(col, col:Lerp(deep, 0.25)), LightEmission = 0.25, Brightness = 1.8,
			Size = NumberSequence.new({ kp(0, 0.75 * s), kp(1, 0.95 * s) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.15, 0.05), kp(0.75, 0.15), kp(1, 1) }),
			Lifetime = NumberRange.new(0.5, 0.9), Rate = (1.5 + 2 * h) * d,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		})
	end

	-- faint white dust near the bottom
	local tip = fx:_spinner("ElementBase", 1.1, 0.05)
	for k = 1, 6 do
		local a = k / 6 * TAU
		local pos = Vector3.new(math.cos(a) * 1.0 * s, 0.25, math.sin(a) * 1.0 * s)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local att = fx:_attach(tip.part, nil, CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -(math.pi / 2 - 0.35)))
		fx:_emitter(att, {
			Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(dustCol), LightEmission = 0, Brightness = 1,
			Size = NumberSequence.new({ kp(0, 1.0 * s), kp(1, 3.0 * s) }),
			Transparency = NumberSequence.new({ kp(0, 0.8), kp(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.3), Rate = 5 * d, Speed = NumberRange.new(1.5 * s, 3 * s),
			Drag = 1.5, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		})
	end

	-- faint dust trail left on the ground while you move
	local trailAtt = Instance.new("Attachment")
	trailAtt.Position = Vector3.new(0, 0.3, 0)
	trailAtt.Parent = fx.basePart
	local trail = make("ParticleEmitter", {
		Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top, LightInfluence = 0,
		Color = ColorSequence.new(dustCol), LightEmission = 0, Brightness = 1,
		Size = NumberSequence.new({ kp(0, 1.2 * s), kp(1, 3.2 * s) }),
		Transparency = NumberSequence.new({ kp(0, 0.75), kp(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2.2), Rate = 0, Speed = NumberRange.new(0.5 * s, 1.5 * s),
		SpreadAngle = Vector2.new(90, 10), Drag = 1, Acceleration = Vector3.new(0, 0.5, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), Enabled = false,
	}, trailAtt)
	local active = false
	install(fx, {
		begin = function() active = true end,
		stop = function()
			active = false
			trail.Enabled = false
		end,
		update = function(fx2)
			if not active then return end
			local v = fx2.root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			trail.Enabled = speed > 2
			-- the client's particle budget reads this and sets the actual Rate
			trail:SetAttribute("LodBase", math.clamp(speed * 1.2, 0, 40) * Config.Density)
		end,
	})
end

----------------------------------------------------------------------------------------
-- ICE
----------------------------------------------------------------------------------------

function Elements.Build.ice(fx)
	local c, d, s, H = fx.color, Config.Density, fx.size, fx.height

	-- frost mist rolling out of the tip
	local tip = fx:_spinner("ElementBase", 1.1, 0.05)
	for k = 1, 6 do
		local a = k / 6 * TAU
		local pos = Vector3.new(math.cos(a) * 1.2 * s, 0.3, math.sin(a) * 1.2 * s)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local att = fx:_attach(tip.part, nil, CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -(math.pi / 2 - 0.5)))
		fx:_emitter(att, {
			Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(WHITE, c), LightEmission = 0.35, Brightness = 1.2,
			Size = NumberSequence.new({ kp(0, 1.2 * s), kp(1, 3.4 * s) }),
			Transparency = NumberSequence.new({ kp(0, 0.6), kp(1, 1) }),
			Lifetime = NumberRange.new(0.7, 1.2), Rate = 7 * d, Speed = NumberRange.new(1 * s, 2.5 * s),
			Drag = 1, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		})
	end

	-- soft white core glow up the funnel
	local core = fx:_spinner("IceCore", 0.6, 0.5)
	for k = 1, 3 do
		local h = 0.25 + (k - 1) * 0.3
		local att = fx:_attach(core.part, Vector3.new(0, h * H, 0))
		fx:_emitter(att, {
			Texture = TEX_SMOKE, LockedToPart = true,
			Color = ColorSequence.new(WHITE), LightEmission = 0.5, Brightness = 1,
			Size = NumberSequence.new({ kp(0, fx:_radius(h) * 1.5), kp(1, fx:_radius(h) * 1.8) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.9), kp(1, 1) }),
			Lifetime = NumberRange.new(0.4, 0.7), Rate = 6 * d, Speed = NumberRange.new(0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
		})
	end

end

----------------------------------------------------------------------------------------
-- TORNADO OF CREATION (Fire + Earth + Lightning + Ice combined)
----------------------------------------------------------------------------------------

function Elements.Build.creation(fx)
	local d, s, rng = Config.Density, fx.size, fx.rng
	-- bright blue glow where it touches the ground
	local tip = fx:_spinner("ElementBase", 1.2, 0.05)
	local att = fx:_attach(tip.part, Vector3.new(0, 0.5 * s, 0))
	fx:_emitter(att, {
		Texture = TEX_SMOKE, LockedToPart = true,
		Color = ColorSequence.new(Color3.fromRGB(170, 230, 255)), LightEmission = 1, Brightness = 3,
		Size = NumberSequence.new({ kp(0, 2.2 * s), kp(1, 1.5 * s) }),
		Transparency = NumberSequence.new({ kp(0, 0.2), kp(1, 1) }),
		Lifetime = NumberRange.new(0.15, 0.3), Rate = 20 * d, Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
	})
	-- dark rocks whirling around the orange part
	for i = 1, 8 do
		surfaceRing(fx, 0.32 + (i - 1) * 0.045, rng:NextNumber(1.1, 1.35), 4, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(40, 30, 22), Color3.fromRGB(20, 16, 12)), LightEmission = 0, Brightness = 1,
			Size = NumberSequence.new({ kp(0, 0.16 * s), kp(1, 0.12 * s) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.1, 0), kp(0.85, 0), kp(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.1), Rate = 9 * d,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
		})
	end
	-- rocks flung off it, falling away
	for k = 1, 4 do
		local h = 0.35 + (k - 1) * 0.06
		local a = k / 4 * TAU
		local r = fx:_radius(h)
		local fling = fx:_spinner("Surface", 1.3, h)
		local att2 = fx:_attach(fling.part, Vector3.new(math.cos(a) * r, h * fx.height, math.sin(a) * r))
		fx:_emitter(att2, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(55, 42, 30)), LightEmission = 0, Brightness = 1,
			Size = NumberSequence.new({ kp(0, 0.13 * s), kp(1, 0.09 * s) }),
			Transparency = NumberSequence.new({ kp(0, 0), kp(0.8, 0), kp(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.4), Rate = 12 * d, Speed = NumberRange.new(5 * s, 10 * s),
			SpreadAngle = Vector2.new(180, 180), Drag = 1, Acceleration = Vector3.new(0, -20, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
		})
	end
	-- big billowing fog around most of it
	for i = 1, 7 do
		surfaceRing(fx, 0.22 + (i - 1) * 0.12, 1.5, 4, {
			Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(245, 232, 205), Color3.fromRGB(210, 190, 155)), LightEmission = 0.15, Brightness = 1.3,
			Size = NumberSequence.new({ kp(0, 3.5 * s), kp(1, 6 * s) }),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.62), kp(1, 1) }),
			Lifetime = NumberRange.new(1.2, 2.0), Rate = 2.5 * d,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20),
		})
	end

	-- the moment it forms: white flash, a shockwave ring racing outward and a ring of dust
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 240, 200)
	ring.Transparency = 1
	ring.Size = Vector3.new(0.3, 1, 1)
	ring.Parent = fx.folder
	local flash = make("PointLight", { Color = Color3.fromRGB(255, 235, 190), Range = 60, Brightness = 0, Shadows = false }, ring)
	local dust = {}
	for k = 1, 16 do
		local a = k / 16 * TAU
		local pos = Vector3.new(math.cos(a) * 1.5 * s, 0.4, math.sin(a) * 1.5 * s)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local att2 = Instance.new("Attachment")
		att2.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -(math.pi / 2 - 0.12))
		att2.Parent = fx.basePart
		table.insert(dust, make("ParticleEmitter", {
			Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top, LightInfluence = 0,
			Color = ColorSequence.new(Color3.fromRGB(240, 228, 205)), LightEmission = 0.1, Brightness = 1.2,
			Size = NumberSequence.new({ kp(0, 2 * s), kp(1, 5 * s) }),
			Transparency = NumberSequence.new({ kp(0, 0.35), kp(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.3), Rate = 0, Speed = NumberRange.new(14 * s, 22 * s),
			SpreadAngle = Vector2.new(10, 10), Drag = 3,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), Enabled = false,
		}, att2))
	end
	local boom = nil
	install(fx, {
		begin = function()
			boom = 0
			for _, pe in ipairs(dust) do pe:Emit(5) end
		end,
		update = function(fx2, dt)
			if not boom then return end
			boom += dt
			local f = math.clamp(boom / 0.9, 0, 1)
			local d = (2 + f * fx2.rT * 3.2)
			ring.Size = Vector3.new(0.3 + (1 - f) * 0.8, d, d)
			ring.CFrame = fx2.basePart.CFrame * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Transparency = 0.15 + 0.85 * f
			flash.Brightness = 12 * (1 - f) ^ 2
			if f >= 1 then boom = nil ring.Transparency = 1 end
		end,
	})
end

return Elements
