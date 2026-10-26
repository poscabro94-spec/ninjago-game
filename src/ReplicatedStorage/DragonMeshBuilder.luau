-- DragonMeshBuilder v4.0  (ModuleScript in ReplicatedStorage)
-- Builds the dragon head in code (EditableMesh) the way the Ninjago Dragons Rising energy
-- dragons look: big blocky flat plates (chamfered box sections, hard corners), a long boxy
-- snout, a wide-open jaw with jagged teeth, swept-back horns and crest. Returns "seam" lines
-- along every plate edge so SpinjitzuDragon can outline the plates with glowing lines.
-- Built on each client; no uploaded assets. Head space: -Z = snout, +Y = up.

local AS = game:GetService("AssetService")

local function new()
	local em = AS:CreateEditableMesh()
	local b = {
		em = em, lines = {},
		minV = Vector3.new(math.huge, math.huge, math.huge), maxV = -Vector3.new(math.huge, math.huge, math.huge),
	}
	-- every triangle gets its own 3 vertices -> flat shading (crisp plates)
	function b.T(p, q, r)
		b.minV = b.minV:Min(p):Min(q):Min(r)
		b.maxV = b.maxV:Max(p):Max(q):Max(r)
		em:AddTriangle(em:AddVertex(p), em:AddVertex(q), em:AddVertex(r))
	end
	-- smooth lofts share vertices (soft shading); otherwise every triangle is its own facet
	local shared = {}
	local function vid(p)
		local key = string.format("%.4f,%.4f,%.4f", p.X, p.Y, p.Z)
		local id = shared[key]
		if not id then
			b.minV = b.minV:Min(p)
			b.maxV = b.maxV:Max(p)
			id = em:AddVertex(p)
			shared[key] = id
		end
		return id
	end
	function b.TS(p, q, r) em:AddTriangle(vid(p), vid(q), vid(r)) end
	-- connect rings (each a list of Vector3, same count); optional end caps
	function b.loft(rings, capStart, capEnd, smooth)
		local T = smooth and b.TS or b.T
		local n = #rings[1]
		for i = 1, #rings - 1 do
			for k = 1, n do
				local k2 = k % n + 1
				local p, q, r, s = rings[i][k], rings[i][k2], rings[i + 1][k], rings[i + 1][k2]
				T(p, r, q)
				T(q, r, s)
			end
		end
		if capStart then
			for k = 1, n do T(capStart, rings[1][k], rings[1][k % n + 1]) end
		end
		if capEnd then
			local L = #rings
			for k = 1, n do T(capEnd, rings[L][k % n + 1], rings[L][k]) end
		end
	end
	-- outline: every corner line along the rings, plus closed loops on every `step`-th ring
	function b.outline(rings, first, last, step)
		local n = #rings[1]
		for k = 1, n do
			local line = {}
			if first then table.insert(line, first) end
			for _, r in ipairs(rings) do table.insert(line, r[k]) end
			if last then table.insert(line, last) end
			table.insert(b.lines, line)
		end
		for i = 1, #rings, step or 2 do
			local loop = {}
			for k = 1, n do table.insert(loop, rings[i][k]) end
			table.insert(loop, rings[i][1])
			table.insert(b.lines, loop)
		end
	end
	return b
end

-- chamfered box cross-section at z: 8 corners, flat sides (corner 1 = right side, low)
local function ring(z, w, top, bot, xform)
	local c = math.min(w, top - bot) * 0.22
	local hw = w / 2
	local pts = {
		Vector3.new(hw, bot + c, z), Vector3.new(hw, top - c, z), Vector3.new(hw - c, top, z), Vector3.new(-(hw - c), top, z),
		Vector3.new(-hw, top - c, z), Vector3.new(-hw, bot + c, z), Vector3.new(-(hw - c), bot, z), Vector3.new(hw - c, bot, z),
	}
	if xform then
		for i, p in ipairs(pts) do pts[i] = xform(p) end
	end
	return pts
end

-- tapered square-section spike along a quadratic bezier
local function spike(b, p0, p1, p2, r0, r1, rings, withSeam)
	local rs = {}
	for i = 0, rings - 1 do
		local t = i / (rings - 1) * 0.92
		local pos = p0 * (1 - t) ^ 2 + p1 * 2 * (1 - t) * t + p2 * t * t
		local tan = ((p1 - p0) * 2 * (1 - t) + (p2 - p1) * 2 * t).Unit
		local side = tan:Cross(Vector3.yAxis)
		if side.Magnitude < 1e-3 then side = Vector3.xAxis end
		side = side.Unit
		local up = side:Cross(tan).Unit
		local r = r0 + (r1 - r0) * t / 0.92
		local pts = {}
		for k = 0, 3 do
			local th = k / 4 * 2 * math.pi + math.pi / 4
			table.insert(pts, pos + (side * math.cos(th) + up * math.sin(th)) * r)
		end
		table.insert(rs, pts)
	end
	b.loft(rs, p0 - (p1 - p0).Unit * 0.05, p2)
	if withSeam then
		for _, k in ipairs({ 1, 2 }) do
			local line = {}
			for _, r in ipairs(rs) do table.insert(line, r[k]) end
			table.insert(line, p2)
			table.insert(b.lines, line)
		end
	end
end

-- skull -> long boxy snout (z, width, top, bottom); each key is one ring of plates
local HEAD_UPPER = {
	{ 0.9, 1.4, 0.6, -0.5 },
	{ 0.4, 1.9, 1.0, -0.7 },
	{ -0.2, 2.0, 1.1, -0.7 },
	{ -0.8, 1.75, 1.0, -0.55 },
	{ -1.4, 1.45, 0.75, -0.4 },
	{ -2.4, 1.35, 0.68, -0.32 },
	{ -3.3, 1.3, 0.66, -0.3 },
	{ -3.8, 1.2, 0.6, -0.28 },
	{ -4.1, 0.9, 0.45, -0.22 },
}
-- lower jaw (before it's swung open)
local HEAD_JAW = {
	{ 0.4, 1.6, -0.3, -0.9 },
	{ -0.6, 1.5, -0.32, -0.88 },
	{ -1.7, 1.35, -0.32, -0.78 },
	{ -2.9, 1.2, -0.32, -0.68 },
	{ -3.6, 1.0, -0.32, -0.6 },
	{ -4.0, 0.6, -0.33, -0.5 },
}
-- swept-back crest along the top: z, y, length
local CREST = { { 0.75, 0.65, 1.3 }, { 0.25, 1.0, 1.9 }, { -0.35, 1.1, 1.6 }, { -0.95, 1.0, 1.15 } }

local function buildHead(jawOpen)
	local b = new()
	-- skull + upper jaw
	local rings = {}
	for _, k in ipairs(HEAD_UPPER) do table.insert(rings, ring(k[1], k[2], k[3], k[4])) end
	local back, tip = Vector3.new(0, 0.05, 1.1), Vector3.new(0, 0.12, -4.25)
	b.loft(rings, back, tip)
	b.outline(rings, nil, tip, 2)
	-- lower jaw, hinged at the back and hanging wide open
	local hinge = Vector3.new(0, -0.5, 0.2)
	local rot = CFrame.Angles(-(jawOpen or 0.36), 0, 0)
	local function xf(p) return hinge + rot * (p - hinge) end
	local jaw = {}
	for _, k in ipairs(HEAD_JAW) do table.insert(jaw, ring(k[1], k[2], k[3], k[4], xf)) end
	local jawTip = xf(Vector3.new(0, -0.42, -4.1))
	b.loft(jaw, xf(Vector3.new(0, -0.6, 0.6)), jawTip)
	b.outline(jaw, nil, jawTip, 2)
	for _, s in ipairs({ 1, -1 }) do
		-- horns, cheek spikes, brow plates
		spike(b, Vector3.new(0.55 * s, 0.95, 0.3), Vector3.new(0.8 * s, 1.35, 1.4), Vector3.new(0.95 * s, 1.95, 2.5), 0.3, 0.03, 5, true)
		spike(b, Vector3.new(0.95 * s, 0.0, 0.2), Vector3.new(1.3 * s, -0.05, 1.0), Vector3.new(1.5 * s, -0.2, 1.9), 0.22, 0.02, 4, true)
		spike(b, Vector3.new(0.85 * s, -0.5, -0.3), Vector3.new(1.15 * s, -0.65, 0.4), Vector3.new(1.3 * s, -0.85, 1.2), 0.17, 0.02, 4, true)
		spike(b, Vector3.new(0.45 * s, 1.08, -0.2), Vector3.new(0.98 * s, 1.02, -0.8), Vector3.new(0.85 * s, 0.78, -1.6), 0.2, 0.05, 4, true)
		-- jagged teeth along both jaws
		for i = 0, 5 do
			local z = -3.85 + i * 0.45
			local len = (i % 2 == 0) and 0.42 or 0.28
			local x = 0.55 * s
			local top = Vector3.new(x, -0.28, z)
			spike(b, top, top + Vector3.new(0, -len * 0.5, 0.02), top + Vector3.new(0, -len, 0.04), 0.1, 0.01, 3)
			local jp = xf(Vector3.new(x * 0.95, -0.33, z + 0.2))
			spike(b, jp, jp + Vector3.new(0, len * 0.45, 0), jp + Vector3.new(0, len * 0.9, -0.03), 0.09, 0.01, 3)
		end
	end
	for _, c in ipairs(CREST) do
		local z, y, len = c[1], c[2], c[3]
		spike(b, Vector3.new(0, y - 0.1, z), Vector3.new(0, y + 0.35 * len, z + 0.35 * len), Vector3.new(0, y + 0.55 * len, z + 0.9 * len), 0.24, 0.02, 4, true)
	end
	return b
end

-- flame-style head (like the Roblox game): smooth rounded skull + snout, mouth closed,
-- and flame licks sweeping back off its sides, top and chin
local FLAME_HEAD = { -- z, width, top, bottom
	{ 1.1, 0.9, 0.45, -0.45 },
	{ 0.6, 1.6, 0.85, -0.75 },
	{ 0.0, 1.9, 1.0, -0.85 },
	{ -0.7, 1.7, 0.9, -0.75 },
	{ -1.5, 1.35, 0.65, -0.6 },
	{ -2.4, 1.15, 0.5, -0.5 },
	{ -3.2, 1.0, 0.42, -0.42 },
	{ -3.7, 0.7, 0.3, -0.32 },
}

local function roundRing(z, w, top, bot, seg)
	local pts = {}
	local mid, hh = (top + bot) / 2, (top - bot) / 2
	for k = 0, seg - 1 do
		local th = k / seg * 2 * math.pi
		table.insert(pts, Vector3.new(w / 2 * math.cos(th), mid + hh * math.sin(th), z))
	end
	return pts
end

local function buildFlameHead()
	local b = new()
	local rings = {}
	for _, k in ipairs(FLAME_HEAD) do table.insert(rings, roundRing(k[1], k[2], k[3], k[4], 14)) end
	b.loft(rings, Vector3.new(0, 0, 1.3), Vector3.new(0, 0, -4.0), true)
	-- flame licks: z, height on the side (-1..1), length; mirrored left/right
	local LICKS = { { 0.7, 0.55, 1.6 }, { 0.15, 0.7, 1.9 }, { -0.5, 0.6, 1.5 }, { -1.2, 0.45, 1.1 }, { -1.9, 0.3, 0.8 },
		{ 0.5, -0.3, 1.3 }, { -0.3, -0.45, 1.1 }, { -1.1, -0.5, 0.8 } }
	for _, s in ipairs({ 1, -1 }) do
		for _, l in ipairs(LICKS) do
			local z, h, len = l[1], l[2], l[3]
			local k = FLAME_HEAD[1]
			for i = 1, #FLAME_HEAD - 1 do
				if z <= FLAME_HEAD[i][1] and z >= FLAME_HEAD[i + 1][1] then k = FLAME_HEAD[i] break end
			end
			local mid, hh = (k[3] + k[4]) / 2, (k[3] - k[4]) / 2
			local base = Vector3.new(s * k[2] / 2 * math.sqrt(math.max(0, 1 - h * h)) * 0.9, mid + hh * h * 0.9, z)
			local out = Vector3.new(s * 0.45, h * 0.35, 1)
			spike(b, base, base + out * len * 0.45 + Vector3.new(0, 0.15, 0), base + out * len + Vector3.new(0, 0.35 * len, 0), 0.2, 0.02, 4)
		end
	end
	-- crest of flames along the top
	for _, c in ipairs({ { 0.8, 0.5, 1.6 }, { 0.2, 0.9, 2.1 }, { -0.5, 0.85, 1.7 }, { -1.3, 0.6, 1.2 }, { -2.1, 0.45, 0.8 } }) do
		local z, y, len = c[1], c[2], c[3]
		spike(b, Vector3.new(0, y, z), Vector3.new(0, y + 0.35 * len, z + 0.35 * len), Vector3.new(0, y + 0.6 * len, z + 0.9 * len), 0.24, 0.02, 4)
	end
	return b
end

-- colour every plate by which way it faces: top/front plates hot (white = full part colour),
-- side/under plates fade toward darkMul (multiplied with the part's Color)
local function shade(b, darkMul)
	local em = b.em
	local cache = {}
	for _, f in ipairs(em:GetFaces()) do
		local vs = em:GetFaceVertices(f)
		local p, q, r = em:GetPosition(vs[1]), em:GetPosition(vs[2]), em:GetPosition(vs[3])
		local n = (q - p):Cross(r - p)
		n = n.Magnitude > 1e-6 and n.Unit or Vector3.yAxis
		local t = math.clamp(0.6 + 0.5 * n.Y - 0.3 * n.Z - 0.2 * math.abs(n.X), 0, 1)
		t = math.floor(t * 6 + 0.5) / 6
		local id = cache[t]
		if not id then
			id = em:AddColor(darkMul:Lerp(Color3.new(1, 1, 1), t), 1)
			cache[t] = id
		end
		em:SetFaceColors(f, { id, id, id })
	end
end

local function toPart(b, name)
	local mp = AS:CreateMeshPartAsync(Content.fromObject(b.em))
	mp.Name = name
	mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch, mp.CastShadow = true, false, false, false, false
	mp.Material = Enum.Material.Neon
	-- where the mesh's own origin sits relative to the part centre
	mp:SetAttribute("OriginOffset", -(b.minV + b.maxV) / 2)
	return mp
end

return { buildHead = buildHead, buildFlameHead = buildFlameHead, shade = shade, toPart = toPart }
