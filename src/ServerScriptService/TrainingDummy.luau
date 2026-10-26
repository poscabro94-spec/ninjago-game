-- TrainingDummy v1.0  (ModuleScript in ServerScriptService)
-- Dummies to hit: stand still, show their health, heal after 4s without being hit, get put back
-- if knocked far away, and come back 3s after they die. Infinite ones can't die.
-- Used by GoldenWeaponsServer (the one by the spawn) and the menu (spawned in front of you).

local Players = game:GetService("Players")

local Dummy = {}

local SKIN = Color3.fromRGB(190, 160, 110)
local CLOTH = Color3.fromRGB(150, 110, 70)
local INFINITE_CLOTH = Color3.fromRGB(70, 110, 160)

-- opts: infinite = true, setup = function(model) (runs again each time it comes back)
function Dummy.spawn(at, lookAt, opts)
	opts = opts or {}
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = SKIN
	desc.TorsoColor = opts.infinite and INFINITE_CLOTH or CLOTH
	desc.LeftArmColor, desc.RightArmColor = SKIN, SKIN
	desc.LeftLegColor, desc.RightLegColor = desc.TorsoColor, desc.TorsoColor
	local ok, dummy = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not dummy then
		warn("[TrainingDummy] couldn't make a dummy:", dummy)
		return nil
	end
	local name = opts.infinite and "Infinite Dummy" or "Training Dummy"
	dummy.Name = name
	local hum = dummy:FindFirstChildOfClass("Humanoid")
	local hp = opts.infinite and math.huge or 200
	hum.MaxHealth, hum.Health = hp, hp
	hum.DisplayName = name
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.WalkSpeed, hum.JumpPower = 0, 0
	hum.BreakJointsOnDeath = false
	local animate = dummy:FindFirstChild("Animate")
	if animate then animate:Destroy() end

	-- stand on the ground at `at`, facing lookAt
	local root = dummy:WaitForChild("HumanoidRootPart")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { dummy }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
	local y = (hit and hit.Position.Y or at.Y) + hum.HipHeight + root.Size.Y / 2
	local pos = Vector3.new(at.X, y, at.Z)
	local face = Vector3.new(lookAt.X, y, lookAt.Z)
	if (face - pos).Magnitude < 0.1 then face = pos + Vector3.new(0, 0, -1) end
	local home = CFrame.lookAt(pos, face)
	dummy:PivotTo(home)
	if opts.setup then opts.setup(dummy) end
	dummy.Parent = workspace
	pcall(function() root:SetNetworkOwner(nil) end)

	task.spawn(function()
		while dummy.Parent and hum.Health > 0 do
			task.wait(0.5)
			local last = dummy:GetAttribute("LastHit") or 0
			if os.clock() - last > 4 and hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
			if root.Parent and (root.Position - home.Position).Magnitude > 40 then dummy:PivotTo(home) end
		end
	end)
	hum.Died:Connect(function()
		task.wait(3)
		if not dummy.Parent then return end -- removed meanwhile
		dummy:Destroy()
		Dummy.spawn(at, lookAt, opts)
	end)
	return dummy
end

return Dummy
