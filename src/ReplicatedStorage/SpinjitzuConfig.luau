-- SpinjitzuConfig v15.4  (ModuleScript in ReplicatedStorage)

local Config = {}

-- Each element: main colour + highlight (the yellow-ish bands)
Config.Presets = {
	-- Color = main colour, Highlight = bright bands, Deep = dark streaks (optional)
	-- Sounds = { Start, Loop, End }: wind-up, seamless loop while spinning, stop sound (asset ids)
	-- SoundId = one sound for elements without Sounds (looped by time position, see below); "" for no sound
	-- Sparks = "sparkle" | "embers" | "droplets" | "electric" | "dust" | "snow"
	-- Base = "fire" | "water" | "lightning" | "earth" | "ice"   (element extras)
	-- Glow / Band / LightBrightness optionally override the defaults below
	-- DragonMembrane / DragonBone / DragonHead / DragonGlow / DragonFlame optionally set the dragon's colours
	Energy = {
		Color = Color3.fromRGB(35, 235, 10), Highlight = Color3.fromRGB(215, 245, 35),
		Sounds = { Start = "78556963713691", Loop = "89882806971818", End = "99341603228804" },
		Sparks = "sparkle",
		DragonMembrane = Color3.fromRGB(255, 245, 45), DragonBone = Color3.fromRGB(185, 225, 20),
		DragonHead = Color3.fromRGB(160, 255, 40), DragonGlow = Color3.fromRGB(110, 255, 220),
		DragonFlame = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 255, 130)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(90, 255, 90)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 225, 215)),
		}),
	},
	Fire = {
		Color = Color3.fromRGB(255, 85, 10), Highlight = Color3.fromRGB(255, 200, 45), Deep = Color3.fromRGB(195, 20, 0),
		Sounds = { Start = "76928178554365", Loop = "71894695368576", End = "90408709963452" },
		Sparks = "embers", Base = "fire", Glow = 0.6, Band = 0.8, LightBrightness = 6,
		DragonMembrane = Color3.fromRGB(255, 205, 40), DragonBone = Color3.fromRGB(255, 120, 20),
	},
	Water = {
		Color = Color3.fromRGB(20, 150, 255), Highlight = Color3.fromRGB(130, 230, 255), Deep = Color3.fromRGB(0, 70, 190),
		Sounds = { Start = "73198328334630", Loop = "103526698126061", End = "70536334014186" },
		Sparks = "droplets", Base = "water", Glow = 0.5, Band = 0.6, LightBrightness = 4,
	},
	Lightning = {
		Color = Color3.fromRGB(20, 150, 255), Highlight = Color3.fromRGB(130, 225, 255), Deep = Color3.fromRGB(0, 55, 185),
		Sounds = { Start = "115630403946895", Loop = "81234467851579", End = "126141400807685" },
		Sparks = "electric", Base = "lightning", Glow = 0.6, Band = 0.7, LightBrightness = 6,
	},
	Earth = {
		Color = Color3.fromRGB(170, 105, 30), Highlight = Color3.fromRGB(230, 165, 60), Deep = Color3.fromRGB(100, 58, 15),
		Sounds = { Start = "102881755586389", Loop = "71119344253011", End = "77038400882262" },
		Sparks = "dust", Base = "earth", Glow = 0.15, Band = 0.6, LightBrightness = 3,
	},
	Ice = {
		Color = Color3.fromRGB(175, 228, 250), Highlight = Color3.fromRGB(232, 247, 255), Deep = Color3.fromRGB(120, 200, 240),
		Sounds = { Start = "74227630958155", Loop = "110744932507680", End = "134665037382213" },
		Sparks = "snow", Base = "ice", Glow = 0.45, Band = 0.6, LightBrightness = 3,
	},
	-- the combined Tornado of Creation (blue bottom -> orange -> gold -> white top)
	Creation = {
		Color = Color3.fromRGB(255, 190, 80), Highlight = Color3.fromRGB(255, 245, 220), Deep = Color3.fromRGB(205, 115, 35),
		SoundId = "95671962797578", Sparks = "sparkle", Base = "creation", Glow = 0.3, Band = 0.3, LightBrightness = 6,
		Gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 160, 255)),
			ColorSequenceKeypoint.new(0.22, Color3.fromRGB(120, 210, 255)),
			ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 120, 35)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 150, 45)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 200, 80)),
			ColorSequenceKeypoint.new(0.9, Color3.fromRGB(255, 235, 170)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 252, 240)),
		}),
	},
	Golden    = { Color = Color3.fromRGB(255, 165, 15), Highlight = Color3.fromRGB(255, 235, 120), SoundId = "95671962797578" },
	Shadow    = { Color = Color3.fromRGB(115, 35, 225), Highlight = Color3.fromRGB(210, 150, 255), SoundId = "95671962797578" },
}

-- >>> PICK THE ELEMENT <<<
Config.Element = "Energy"

-- Or set your own colours (leave nil to use the preset above)
Config.CustomColor = nil       -- e.g. Color3.fromRGB(255, 0, 150)
Config.CustomHighlight = nil   -- nil = auto (lighter version of the colour)

Config.Keybind = Enum.KeyCode.Q
Config.CycleKey = Enum.KeyCode.E            -- switch element
Config.ElementOrder = { "Energy", "Fire", "Water", "Lightning", "Earth", "Ice" }

-- Test bot: a dummy that loops Spinjitzu (6s on, 1s off) so you can watch it. Set false to remove.
Config.TestBot = true
Config.TestBotElements = { "Energy", "Fire", "Water", "Lightning", "Earth", "Ice" } -- one bot per element, side by side
Config.TestBotPosition = Vector3.new(0, 0, 20)
Config.HideCharacter = true    -- player is invisible inside the tornado
Config.MuteFootsteps = true    -- no running sounds while spinning
Config.SpeedMultiplier = 2     -- walk speed multiplier while spinning

-- Dragon (R): Spinjitzu -> dragon appears and you rise straight up -> free flight. R again to drop out.
-- Flying: WASD = move (where the camera looks, so look up/down to climb/dive), Space = up, Ctrl = down
Config.DragonKey = Enum.KeyCode.R
Config.DragonSpinTime = 2       -- seconds of Spinjitzu before the dragon appears
Config.DragonRiseTime = 3       -- seconds going straight up before you can move
Config.DragonRiseHeight = 35    -- studs it rises in that time
Config.DragonFlySpeed = 50      -- studs/s
Config.DragonUpKey = Enum.KeyCode.Space
Config.DragonDownKey = Enum.KeyCode.LeftControl
Config.DragonScale = 1
Config.DragonWingScale = 1.8    -- wing size on top of DragonScale
Config.DragonHeadScale = 1.0
Config.DragonHeadStyle = "flame" -- "flame" (like the Roblox game) or "plated" (the blocky show-style head)    -- head size on top of DragonScale
Config.DragonMeshHead = true    -- smooth mesh head (built in code); false = old part head
Config.DragonFlapSpeed = 6      -- wing beat speed while flying
Config.DragonBot = true         -- a bot that demos the dragon on a loop

-- Tornado of Creation (T): needs 4 players close together on Fire, Earth, Lightning and Ice.
-- They start Spinjitzu in this order, come together and merge into one huge tornado.
Config.CreationKey = Enum.KeyCode.T
Config.CreationElements = { "Fire", "Earth", "Lightning", "Ice" } -- spin order
Config.CreationRange = 40         -- studs: how close the other 3 must be
Config.CreationStagger = 0.8      -- seconds between each ninja starting
Config.CreationGatherTime = 1.2   -- seconds for the 4 tornadoes to come together
Config.CreationTime = 10          -- seconds the big tornado lasts
Config.CreationScale = 4          -- size of the big tornado
Config.CreationBot = true         -- 4 bots that demo it on a loop


-- Sound: elements with Sounds play Start, then Loop until Spinjitzu is turned off, then End.
-- A single SoundId plays from the start, loops [SoundLoopStart -> SoundEndStart] while active,
-- and jumps to SoundEndStart (the "stop" part) when Spinjitzu is turned off.
Config.SoundId = "95671962797578" -- fallback for custom colours and presets without Sounds
Config.SoundVolume = 0.4
Config.SoundRange = 80         -- studs until it's silent for other players
Config.SoundEndStart = 5.5     -- where the stopping sound begins
Config.SoundLoopStart = 1.0    -- where the loop jumps back to (skips the wind-up at the start)
Config.SoundFadeOut = 0.12     -- Start/Loop fade out this fast when the End sound kicks in

-- Shape (studs, scaled by character size). Narrow at the ground, wide at the top.
Config.Height = 9
Config.BottomRadius = 0.25
Config.TopRadius = 6.2
Config.FunnelCurve = 1.0       -- 1 = straight cone; <1 = rounder, fuller sides
Config.TopRound = 0.05         -- how much the top edge rounds inward
Config.BodySlices = 40         -- layers of the solid fuzzy body
Config.Rings = 70              -- streak rings on the surface

-- Motion
Config.SpinSpeed = 16           -- radians/sec (bottom spins faster than top)
Config.SpinDirection = 1        -- 1 or -1
Config.CharacterSpinSpeed = 22
Config.Sway = 0.5               -- how much the tornado snakes around (studs at the top)
Config.FadeInTime = 0.3
Config.FadeOutTime = 0.5        -- matches the ~0.5s stop sound
Config.WindupTime = 0.5         -- you spin visibly for this long before the tornado forms
Config.LeanAngle = 0.3          -- max tilt (radians) toward the direction you're moving
Config.LeanFullSpeed = 30       -- speed (studs/s) at which the tilt is at max
Config.LeanSmoothing = 6        -- how quickly the tilt follows your movement

-- Look
Config.Glow = 0.35             -- additive glow (raise toward 1 for dark/night maps)
Config.Brightness = 1.3
Config.Density = 1             -- particle amount multiplier
Config.ParticleBudget = 14000  -- max particles on screen; far/crowded tornadoes thin out so none get cut off
Config.Streaks = 22            -- fast spinning energy trails
Config.Sparkles = 30           -- sparkle emitters flinging sparkles off the tornado
Config.LightBrightness = 4
Config.LightRange = 14

-- resolved colours (don't edit)
local preset = Config.Presets[Config.Element] or Config.Presets.Energy
Config.Color = Config.CustomColor or preset.Color
Config.HighlightColor = Config.CustomHighlight or (Config.CustomColor and Config.CustomColor:Lerp(Color3.new(1, 1, 0.6), 0.5)) or preset.Highlight

return Config
