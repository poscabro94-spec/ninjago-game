-- DragonMerge v1.0  (ModuleScript in ReplicatedStorage)
-- The Rising Dragon merge: 3 or 4 dragons fly in close, lock into a ring (wings spread round it,
-- tip to tip: a triangle with 3) and spin round the way they're flying until they crash into
-- something. The server runs it (DragonMergeServer); this is the shared maths, so the server and
-- every client put each dragon in exactly the same spot.
--
-- A merge is a Configuration in ReplicatedStorage.DragonMerges with attributes
--   Center, Dir (where it flies), Angle (how far round it has spun), Speed, Spin, Stamp (server
--   time of those), Leader (UserId of who steers)
-- and an ObjectValue child per dragon (Value = the character, attribute Slot). Each member
-- character has MergeFrom (its CFrame when it joined) + MergeAt (when): it swoops into place.

local Merge = {}

Merge.Radius = 6.5    -- studs from the middle to each dragon
Merge.Spin = 5        -- radians a second
Merge.FormTime = 0.9  -- seconds to swoop into place

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- the merge's state right now (moved on from the last update)
function Merge.state(cfg, now)
	local stamp = cfg:GetAttribute("Stamp") or now
	local center, dir = cfg:GetAttribute("Center"), cfg:GetAttribute("Dir")
	if typeof(center) ~= "Vector3" or typeof(dir) ~= "Vector3" then return nil end
	local dt = math.clamp(now - stamp, 0, 0.5)
	return {
		center = center + dir * (cfg:GetAttribute("Speed") or 0) * dt,
		dir = dir,
		angle = (cfg:GetAttribute("Angle") or 0) + (cfg:GetAttribute("Spin") or Merge.Spin) * dt,
	}
end

-- a dragon's spot in the ring: the column (root +Y) along the way it flies, your front facing the
-- middle, wings out round the ring
function Merge.slotCF(st, slot, count, scale)
	local dir = st.dir
	local ref = math.abs(dir.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local a = dir:Cross(ref).Unit
	local b = dir:Cross(a).Unit
	local th = st.angle + (slot - 1) / count * math.pi * 2
	local out = a * math.cos(th) + b * math.sin(th)
	return CFrame.fromMatrix(st.center + out * Merge.Radius * scale, dir:Cross(out), dir, out)
end

-- where a member's root goes now (swooping in from where it joined)
function Merge.memberCF(cfg, member, slot, count, now)
	local st = Merge.state(cfg, now)
	if not st then return nil end
	local okS, scale = pcall(function() return member:GetScale() end)
	local cf = Merge.slotCF(st, slot, count, okS and scale or 1)
	local from, at = member:GetAttribute("MergeFrom"), member:GetAttribute("MergeAt")
	if typeof(from) == "CFrame" and typeof(at) == "number" then
		local f = smooth((now - at) / Merge.FormTime)
		if f < 1 then cf = from:Lerp(cf, f) end
	end
	return cf
end

-- the members of a merge: { { character, slot } }, in slot order
function Merge.members(cfg)
	local list = {}
	for _, v in ipairs(cfg:GetChildren()) do
		if v:IsA("ObjectValue") and v.Value then table.insert(list, { v.Value, v:GetAttribute("Slot") or 1 }) end
	end
	table.sort(list, function(x, y) return x[2] < y[2] end)
	return list
end

return Merge
