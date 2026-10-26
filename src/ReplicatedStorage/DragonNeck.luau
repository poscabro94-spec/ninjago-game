-- DragonNeck v1.0  (ModuleScript in ReplicatedStorage)
-- Where the Rising Dragon's neck + head go when it looks somewhere (it looks where your power
-- goes). Shared by the dragon (SpinjitzuDragon) and the powers (ElementPowers.DragonMouth), so the
-- beam always comes out of the mouth wherever the head is. Everything in root space, unscaled.

local DragonNeck = {}

-- [character] = the mouth's world position this frame, from the dragon you can see (client only)
DragonNeck.Live = setmetatable({}, { __mode = "k" })

-- each neck joint (+ the head, last) as { pos = Vector3, rot = CFrame }: the turn that points the
-- head along `look` (a direction, nil = straight up the column), spread over the joints
function DragonNeck.Bend(M, look)
	local axis, theta = nil, 0
	if look and look.Magnitude > 1e-3 then
		local u = look.Unit
		local c = Vector3.yAxis:Cross(u)
		if c.Magnitude > 1e-4 then
			axis = c.Unit
			theta = math.min(math.acos(math.clamp(u.Y, -1, 1)), M.NeckMaxBend)
		end
	end
	local J, out, turned = M.NeckJoints, {}, 0
	local pos = J[1]
	for i, w in ipairs(M.NeckBend) do
		turned += w * theta
		if i > 1 then pos += out[i - 1].rot:VectorToWorldSpace(J[i] - J[i - 1]) end
		out[i] = { pos = pos, rot = axis and CFrame.fromAxisAngle(axis, turned) or CFrame.identity }
	end
	return out
end

-- the mouth with the neck bent that way
function DragonNeck.Mouth(M, look)
	local chain = DragonNeck.Bend(M, look)
	local head = chain[#chain]
	return head.pos + head.rot:VectorToWorldSpace(M.Mouth - M.NeckTop)
end

-- which way the head should look to face a world point (root space)
function DragonNeck.LookAt(M, rootCF, scale, point)
	return rootCF:VectorToObjectSpace(point - rootCF:PointToWorldSpace(M.NeckTop * scale))
end

return DragonNeck
