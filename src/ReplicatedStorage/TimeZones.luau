-- TimeZones v1.0  (ModuleScript in ReplicatedStorage)
-- Bubbles of stopped time (Time Blades): parts in workspace.TimeZones with a Radius attribute
-- (the server adds + removes them). Beams that run into one stop at its edge (server damage +
-- every client's drawing use clip()).

local TimeZones = {}

-- the folder (server: made if missing)
function TimeZones.folder()
	local f = workspace:FindFirstChild("TimeZones")
	if not f then
		f = Instance.new("Folder")
		f.Name = "TimeZones"
		f.Parent = workspace
	end
	return f
end

-- how far a ray from origin along dir (unit) gets before it runs into stopped time (at most
-- range), and whether it did. Rays that start inside a bubble aren't stopped by that one.
function TimeZones.clip(origin, dir, range)
	local f = workspace:FindFirstChild("TimeZones")
	if not f then return range, false end
	local clipped = false
	for _, z in ipairs(f:GetChildren()) do
		local r = z:IsA("BasePart") and z:GetAttribute("Radius")
		if r then
			local m = origin - z.Position
			local c = m:Dot(m) - r * r
			local b = m:Dot(dir)
			if c > 0 and b < 0 then -- outside, heading toward it
				local disc = b * b - c
				if disc > 0 then
					local t = -b - math.sqrt(disc)
					if t < range then range, clipped = t, true end
				end
			end
		end
	end
	return range, clipped
end

return TimeZones
