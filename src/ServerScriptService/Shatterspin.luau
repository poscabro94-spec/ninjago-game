-- Shatterspin v1.0  (ModuleScript in ServerScriptService)
-- Shatterspin (X): a red + black, destructive Spinjitzu. Faster than Spinjitzu, it wrecks anyone
-- it touches (damage + flung away), throws loose things around, and nothing can hurt you while
-- it's on. Lasts ShatterTime seconds, then ShatterCooldown before you can do it again.
-- The only counter: on the Rising Dragon, hold your beam on them for DragonLockTime seconds to lock
-- on (the beam does nothing else to them), then fly straight into them. That breaks it: a big hit,
-- they're thrown and can't Shatterspin for a while; you land.
-- Used by SpinjitzuServer (start / stop / unlock) and ElementPowersServer (beamTick).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("SpinjitzuConfig"))
local Status = require(script.Parent:WaitForChild("StatusEffects"))
local HitEffects = require(script.Parent:WaitForChild("HitEffects"))

local Shatter = {}
Shatter.onCounter = nil -- function(rider): set by SpinjitzuServer (lands the dragon)

local RED = Color3.fromRGB(235, 20, 30)
local HIT = { -- how its hits look (HitEffects)
	HitColor = RED, HitTextColor = Color3.fromRGB(255, 70, 70),
	Sounds = {
		Hit = { "rbxassetid://115899453415449", "rbxassetid://77794845234498" },
		Final = "rbxassetid://73278613369675", Zap = "rbxassetid://9114277757",
	},
}

local active = {}    -- [character] = { humanoid, token, look = { element, color, highlight }, speed }
local hitAt = {}     -- [victim] = os.clock() of its last Shatterspin hit
local acquiring = {} -- [rider] = { target, t, seen }
local locks = {}     -- [rider] = target

local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

function Shatter.isOn(model)
	return model ~= nil and active[model] ~= nil
end

-- returns why it can't start (a message), or nil
function Shatter.start(character, humanoid)
	if active[character] then return nil end
	local now = workspace:GetServerTimeNow()
	local ready = character:GetAttribute("ShatterReady") or 0
	if ready > now then
		return ("Shatterspin: ready in %ds"):format(math.ceil(ready - now))
	end
	local token = (character:GetAttribute("ShatterToken") or 0) + 1
	local preset = Config.Presets.Shatter
	active[character] = {
		humanoid = humanoid, token = token, speed = humanoid.WalkSpeed,
		look = {
			element = character:GetAttribute("SpinjitzuElement"),
			color = character:GetAttribute("SpinjitzuColor"),
			highlight = character:GetAttribute("SpinjitzuHighlight"),
		},
	}
	character:SetAttribute("ShatterToken", token)
	character:SetAttribute("SpinjitzuElement", "Shatter")
	character:SetAttribute("SpinjitzuColor", preset.Color)
	character:SetAttribute("SpinjitzuHighlight", preset.Highlight)
	character:SetAttribute("Shatterspin", true)
	character:SetAttribute("SpinjitzuActive", true)
	humanoid.WalkSpeed = active[character].speed * (Config.ShatterSpeed or 2.6)
	-- nothing hurts you (every hit goes through TakeDamage, which a ForceField blocks)
	local shield = Instance.new("ForceField")
	shield.Name = "ShatterShield"
	shield.Visible = false
	shield.Parent = character
	task.delay(Config.ShatterTime or 8, function()
		local st = active[character]
		if st and st.token == token then Shatter.stop(character) end
	end)
	return nil
end

-- broken = countered by a dragon (longer cooldown)
function Shatter.stop(character, broken)
	local st = active[character]
	if not st then return end
	active[character] = nil
	local shield = character:FindFirstChild("ShatterShield")
	if shield then shield:Destroy() end
	if st.humanoid.Parent then st.humanoid.WalkSpeed = st.speed end
	character:SetAttribute("Shatterspin", nil)
	character:SetAttribute("SpinjitzuActive", false)
	character:SetAttribute("SpinjitzuElement", st.look.element)
	character:SetAttribute("SpinjitzuColor", st.look.color)
	character:SetAttribute("SpinjitzuHighlight", st.look.highlight)
	local wait = broken and (Config.ShatterBrokenCooldown or 20) or (Config.ShatterCooldown or 12)
	character:SetAttribute("ShatterReady", workspace:GetServerTimeNow() + wait)
	-- anyone locked onto them loses the lock
	for rider, target in pairs(locks) do
		if target == character then Shatter.unlock(rider) end
	end
end

----------------------------------------------------------------------------------------
-- lock-on (Rising Dragon riders)
----------------------------------------------------------------------------------------

-- (rider's "DragonLocking" ObjectValue = who it's locking onto, "DragonLock" = locked on)
local function setValue(rider, name, target)
	local v = rider:FindFirstChild(name)
	if not target then
		if v then v:Destroy() end
		return
	end
	if not v then
		v = Instance.new("ObjectValue")
		v.Name = name
		v.Parent = rider
	end
	v.Value = target
end

local function stopAcquiring(rider)
	acquiring[rider] = nil
	rider:SetAttribute("LockProgress", nil)
	setValue(rider, "DragonLocking", nil)
end

function Shatter.unlock(rider)
	locks[rider] = nil
	stopAcquiring(rider)
	setValue(rider, "DragonLock", nil)
end

local function onDragon(rider)
	local phase = rider:GetAttribute("DragonPhase")
	return phase == "rise" or phase == "fly"
end

-- a dragon rider's beam is on `target` for another `dt` seconds
function Shatter.beamTick(rider, target, dt)
	if not active[target] or not onDragon(rider) or locks[rider] == target then return end
	local now = os.clock()
	local a = acquiring[rider]
	if a and a.target == target and now - a.seen < 0.45 then
		a.t += dt
	else
		a = { target = target, t = dt }
		acquiring[rider] = a
	end
	a.seen = now
	local need = Config.DragonLockTime or 1
	rider:SetAttribute("LockProgress", math.min(1, a.t / need))
	setValue(rider, "DragonLocking", target)
	if a.t >= need then
		stopAcquiring(rider)
		locks[rider] = target
		setValue(rider, "DragonLock", target)
	end
end

local function boom(pos, color)
	local function part(shape, size, col, alpha)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Material = Enum.Material.Neon
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size, p.Color, p.Transparency = size, col, alpha
		p.Parent = workspace
		Debris:AddItem(p, 1)
		return p
	end
	local ball = part(Enum.PartType.Ball, Vector3.new(3, 3, 3), Color3.new(1, 1, 1), 0)
	ball.CFrame = CFrame.new(pos)
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(22, 22, 22), Transparency = 1, Color = color }):Play()
	for i, c in ipairs({ color, RED }) do
		local ring = part(Enum.PartType.Cylinder, Vector3.new(0.3, 3, 3), c, 0.1)
		ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, i * 1.1, math.pi / 2 + (i - 1.5) * 0.6)
		TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.3, 40, 40), Transparency = 1 }):Play()
	end
end

-- you flew into them: Shatterspin broken
local function counter(rider, target)
	Shatter.unlock(rider)
	local rRoot, tRoot = rootOf(rider), rootOf(target)
	local hum = target:FindFirstChildOfClass("Humanoid")
	Shatter.stop(target, true)
	if not (rRoot and tRoot and hum) then return end
	local color = rider:GetAttribute("SpinjitzuColor") or Color3.new(1, 1, 1)
	boom(tRoot.Position, color)
	hum:TakeDamage(Config.ShatterCounterDamage or 40)
	target:SetAttribute("LastHit", os.clock())
	HitEffects.show({ HitColor = color, HitTextColor = color, Sounds = HIT.Sounds }, tRoot, target, Config.ShatterCounterDamage or 40, true)
	Status.blast(target, rRoot.Position, 110)
	if Shatter.onCounter then Shatter.onCounter(rider) end
end

----------------------------------------------------------------------------------------
-- every frame: Shatterspinners wreck what's around them; locked riders that reach their target
----------------------------------------------------------------------------------------

local tickAt = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	-- riders: lost the lock / still acquiring / rammed them
	for rider, a in pairs(acquiring) do
		if now - a.seen > 0.45 or not rider.Parent then stopAcquiring(rider) end
	end
	for rider, target in pairs(locks) do
		local rRoot, tRoot = rootOf(rider), rootOf(target)
		if not rider.Parent or not onDragon(rider) or not active[target] or not rRoot or not tRoot then
			Shatter.unlock(rider)
		elseif (rRoot.Position - tRoot.Position).Magnitude <= (Config.DragonRamRange or 9) * rider:GetScale() then
			counter(rider, target)
		end
	end

	if now - tickAt < 0.15 then return end
	tickAt = now
	for character, st in pairs(active) do
		local root = rootOf(character)
		if not character.Parent or not root or st.humanoid.Health <= 0 then
			Shatter.stop(character)
		else
			local radius = (Config.ShatterRadius or 10) * character:GetScale()
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local done = {}
			for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, radius, params)) do
				local model = part:FindFirstAncestorOfClass("Model")
				local hum = Status.target(model, character)
				if hum and not done[model] then
					done[model] = true
					if now - (hitAt[model] or 0) >= 0.5 then
						hitAt[model] = now
						local tRoot = rootOf(model)
						local dmg = Config.ShatterDamage or 9
						hum:TakeDamage(dmg)
						model:SetAttribute("LastHit", now)
						if tRoot then
							HitEffects.show(HIT, tRoot, model, dmg, false)
							Status.blast(model, root.Position, 85)
						end
					end
				elseif not hum and not part.Anchored and not done[part.AssemblyRootPart] and not model then
					-- loose things get flung
					done[part.AssemblyRootPart] = true
					local away = part.Position - root.Position
					away = Vector3.new(away.X, 0, away.Z)
					away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
					part.AssemblyLinearVelocity = away * 70 + Vector3.new(0, 45, 0)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		active[player.Character] = nil
		Shatter.unlock(player.Character)
	end
end)

return Shatter
