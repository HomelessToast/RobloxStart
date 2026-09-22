--!strict
-- Per-gun fire feel: unique recoil, punchy short SFX, visible tracers.
-- Kick tiers stay economy-coherent (expensive guns still better via damage/ROF/
-- accuracy; SMG softest kick, LMG/sniper heaviest — see vip-economy-weapons.md).

local WeaponDefs = require(script.Parent.WeaponDefs)
local WeaponVisuals = require(script.Parent.WeaponVisuals)

export type FireFeel = {
	soundId: string,
	volume: number,
	playbackSpeed: number,
	-- Hard stop so long boom assets don't ring out every shot.
	maxDuration: number,
	kickDegrees: number,
	tracerWidth: number,
	tracerColor: Color3,
	muzzleBrightness: number,
}

local WeaponAudio = {}

-- Short classic library shots (not explosion beds). Volumes kept low for 3rd-person.
-- Sniper uses the same proven M16 Free punch as ARs (lower pitch) — prior sniper
-- asset id was silent / unavailable in playtest.
local SFX = {
	Pistol = "rbxassetid://131070686",
	SMG = "rbxassetid://142274259",
	Shotgun = "rbxassetid://376568231",
	Assault = "rbxassetid://153230626", -- M16 Free ~1s punch
	LMG = "rbxassetid://153230626",
	Sniper = "rbxassetid://153230626",
}

local CLASS_BASE: { [WeaponVisuals.VisualClass]: FireFeel } = {
	Pistol = {
		soundId = SFX.Pistol,
		volume = 0.1,
		playbackSpeed = 1.25,
		maxDuration = 0.11,
		kickDegrees = 1.4,
		tracerWidth = 0.22,
		tracerColor = Color3.fromRGB(255, 235, 140),
		muzzleBrightness = 2.2,
	},
	SMG = {
		soundId = SFX.SMG,
		volume = 0.07,
		playbackSpeed = 1.45,
		maxDuration = 0.08,
		kickDegrees = 0.55,
		tracerWidth = 0.2,
		tracerColor = Color3.fromRGB(255, 220, 110),
		muzzleBrightness = 1.8,
	},
	Shotgun = {
		soundId = SFX.Shotgun,
		volume = 0.12,
		playbackSpeed = 1.05,
		maxDuration = 0.14,
		kickDegrees = 2.7,
		tracerWidth = 0.32,
		tracerColor = Color3.fromRGB(255, 200, 100),
		muzzleBrightness = 3.5,
	},
	Assault = {
		soundId = SFX.Assault,
		volume = 0.08,
		playbackSpeed = 1.15,
		maxDuration = 0.1,
		kickDegrees = 0.9,
		tracerWidth = 0.26,
		tracerColor = Color3.fromRGB(255, 245, 170),
		muzzleBrightness = 2.4,
	},
	LMG = {
		soundId = SFX.LMG,
		volume = 0.1,
		playbackSpeed = 0.95,
		maxDuration = 0.11,
		kickDegrees = 1.6,
		tracerWidth = 0.3,
		tracerColor = Color3.fromRGB(255, 215, 120),
		muzzleBrightness = 2.8,
	},
	Sniper = {
		soundId = SFX.Sniper,
		volume = 0.16,
		playbackSpeed = 0.78, -- lower pitch = heavier crack, still short cut
		maxDuration = 0.16,
		kickDegrees = 3.2,
		tracerWidth = 0.34,
		tracerColor = Color3.fromRGB(255, 250, 200),
		muzzleBrightness = 4,
	},
}

--[[
	Per-weapon kick (degrees) — distinct silhouettes, economy-coherent:
	- Softest: SMGs (cheap spray, controllable)
	- Pistols: snappy; P2 better control than P0/P1; Deagle hard; Pernach soft spray
	- ARs: mid; control variants (M16/AK74) softer than power (M4/AKM)
	- LMG: heavier than SMG/AR (pay for mag + DPS, eat recoil)
	- Sniper: hardest single-shot punch (pay for damage/precision)
]]
local WEAPON_KICK: { [string]: number } = {
	-- Good pistols
	M9 = 1.45,
	M1911 = 1.85,
	M17 = 1.15,
	Deagle = 3.3,
	-- Good primaries
	MP5 = 0.5,
	M1014 = 2.85,
	M16A4 = 0.72,
	M4A1 = 0.88,
	M249 = 1.7,
	M24 = 3.55,
	-- Terror pistols
	Makarov = 1.5,
	TT33 = 1.75,
	Grach = 1.2,
	Pernach = 0.8,
	-- Terror primaries
	Bizon = 0.58,
	Saiga12 = 2.55,
	AKM = 1.35,
	AK74M = 0.95,
	RPK = 1.55,
	SVD = 2.45,
}

-- Subtle per-gun tracer / volume / pitch overrides (tier identity without volume boom).
local WEAPON_OVERRIDES: {
	[string]: {
		volume: number?,
		playbackSpeed: number?,
		tracerWidth: number?,
		tracerColor: Color3?,
	},
} =
	{
		Deagle = { volume = 0.12, playbackSpeed = 0.95, tracerWidth = 0.28 },
		Pernach = { volume = 0.07, playbackSpeed = 1.4, tracerWidth = 0.18 },
		MP5 = { volume = 0.065, playbackSpeed = 1.5 },
		Bizon = { volume = 0.065, playbackSpeed = 1.4 },
		M16A4 = { playbackSpeed = 1.2, tracerColor = Color3.fromRGB(200, 255, 180) },
		M4A1 = { playbackSpeed = 1.25 },
		AKM = { playbackSpeed = 1.05, tracerColor = Color3.fromRGB(255, 200, 90) },
		AK74M = { playbackSpeed = 1.12, tracerColor = Color3.fromRGB(220, 255, 160) },
		M249 = { volume = 0.1, playbackSpeed = 0.92 },
		RPK = { volume = 0.1, playbackSpeed = 0.9 },
		M24 = { volume = 0.17, playbackSpeed = 0.75, tracerWidth = 0.38 },
		SVD = { volume = 0.15, playbackSpeed = 0.82, tracerWidth = 0.36 },
		M1014 = { volume = 0.13 },
		Saiga12 = { volume = 0.12, playbackSpeed = 1.1 },
	}

local function shallowCopy(feel: FireFeel): FireFeel
	return {
		soundId = feel.soundId,
		volume = feel.volume,
		playbackSpeed = feel.playbackSpeed,
		maxDuration = feel.maxDuration,
		kickDegrees = feel.kickDegrees,
		tracerWidth = feel.tracerWidth,
		tracerColor = feel.tracerColor,
		muzzleBrightness = feel.muzzleBrightness,
	}
end

function WeaponAudio.feelFor(weaponId: string): FireFeel
	local def = WeaponDefs.get(weaponId)
	local class: WeaponVisuals.VisualClass = if def
		then WeaponVisuals.visualClass(def)
		else "Assault"
	local feel = shallowCopy(CLASS_BASE[class])

	local kick = WEAPON_KICK[weaponId]
	if kick ~= nil then
		feel.kickDegrees = kick
	end

	local ov = WEAPON_OVERRIDES[weaponId]
	if ov then
		if ov.volume ~= nil then
			feel.volume = ov.volume
		end
		if ov.playbackSpeed ~= nil then
			feel.playbackSpeed = ov.playbackSpeed
		end
		if ov.tracerWidth ~= nil then
			feel.tracerWidth = ov.tracerWidth
		end
		if ov.tracerColor ~= nil then
			feel.tracerColor = ov.tracerColor
		end
	end

	return feel
end

return WeaponAudio
