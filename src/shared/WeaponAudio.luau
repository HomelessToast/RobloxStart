--!strict
-- Per-gun fire feel: unique recoil, punchy short SFX, physical bullet VFX.
-- Kick is intentionally minimal (Matthew); small per-gun deltas remain.
-- Bullet VFX is client-only (muzzle velocity + gravity drop); damage stays hitscan.

local WeaponDefs = require(script.Parent.WeaponDefs)
local WeaponVisuals = require(script.Parent.WeaponVisuals)

export type FireFeel = {
	soundId: string,
	volume: number,
	playbackSpeed: number,
	-- Hard stop so long boom assets don't ring out every shot.
	maxDuration: number,
	kickDegrees: number,
	-- Square bullet size (studs) — was laser tracer width.
	bulletSize: number,
	bulletColor: Color3,
	-- Client projectile ballistics (studs / sec, studs / sec^2 downward).
	muzzleVelocity: number,
	bulletGravity: number,
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

--[[
	Class ballistics (client VFX only):
	- SMG: fast + flat (easy to track spray)
	- Sniper: slower flight + heavier drop (arc readable at range)
	- Shotgun: slow pellets, more drop
]]
local CLASS_BASE: { [WeaponVisuals.VisualClass]: FireFeel } = {
	Pistol = {
		soundId = SFX.Pistol,
		volume = 0.1,
		playbackSpeed = 1.25,
		maxDuration = 0.11,
		kickDegrees = 0.28,
		bulletSize = 0.18,
		bulletColor = Color3.fromRGB(255, 235, 140),
		muzzleVelocity = 520,
		bulletGravity = 145,
		muzzleBrightness = 2.2,
	},
	SMG = {
		soundId = SFX.SMG,
		volume = 0.07,
		playbackSpeed = 1.45,
		maxDuration = 0.08,
		kickDegrees = 0.12,
		bulletSize = 0.15,
		bulletColor = Color3.fromRGB(255, 220, 110),
		muzzleVelocity = 780,
		bulletGravity = 70,
		muzzleBrightness = 1.8,
	},
	Shotgun = {
		soundId = SFX.Shotgun,
		volume = 0.12,
		playbackSpeed = 1.05,
		maxDuration = 0.14,
		kickDegrees = 0.6,
		bulletSize = 0.2,
		bulletColor = Color3.fromRGB(255, 200, 100),
		muzzleVelocity = 360,
		bulletGravity = 175,
		muzzleBrightness = 3.5,
	},
	Assault = {
		soundId = SFX.Assault,
		volume = 0.08,
		playbackSpeed = 1.15,
		maxDuration = 0.1,
		kickDegrees = 0.2,
		bulletSize = 0.17,
		bulletColor = Color3.fromRGB(255, 245, 170),
		muzzleVelocity = 680,
		bulletGravity = 115,
		muzzleBrightness = 2.4,
	},
	LMG = {
		soundId = SFX.LMG,
		volume = 0.1,
		playbackSpeed = 0.95,
		maxDuration = 0.11,
		kickDegrees = 0.3,
		bulletSize = 0.19,
		bulletColor = Color3.fromRGB(255, 215, 120),
		muzzleVelocity = 620,
		bulletGravity = 125,
		muzzleBrightness = 2.8,
	},
	Sniper = {
		soundId = SFX.Sniper,
		volume = 0.16,
		playbackSpeed = 0.78, -- lower pitch = heavier crack, still short cut
		maxDuration = 0.16,
		kickDegrees = 0.75,
		bulletSize = 0.22,
		bulletColor = Color3.fromRGB(255, 250, 200),
		muzzleVelocity = 560,
		bulletGravity = 220,
		muzzleBrightness = 4,
	},
}

--[[
	Per-weapon kick (degrees) — Matthew: minimal recoil, still mildly distinct.
	Sniper/shotgun/Deagle slightly punchier; SMG/AR nearly flat.
]]
local WEAPON_KICK: { [string]: number } = {
	-- Good pistols
	M9 = 0.28,
	M1911 = 0.32,
	M17 = 0.22,
	Deagle = 0.55,
	-- Good primaries
	MP5 = 0.1,
	M1014 = 0.62,
	M16A4 = 0.16,
	M4A1 = 0.2,
	M249 = 0.3,
	M24 = 0.8,
	-- Terror pistols
	Makarov = 0.3,
	TT33 = 0.32,
	Grach = 0.24,
	Pernach = 0.14,
	-- Terror primaries
	Bizon = 0.12,
	Saiga12 = 0.58,
	AKM = 0.26,
	AK74M = 0.18,
	RPK = 0.28,
	SVD = 0.7,
}

-- Subtle per-gun overrides (SFX + bullet identity).
local WEAPON_OVERRIDES: {
	[string]: {
		volume: number?,
		playbackSpeed: number?,
		bulletSize: number?,
		bulletColor: Color3?,
		muzzleVelocity: number?,
		bulletGravity: number?,
	},
} =
	{
		Deagle = { volume = 0.12, playbackSpeed = 0.95, bulletSize = 0.22, muzzleVelocity = 480 },
		Pernach = {
			volume = 0.07,
			playbackSpeed = 1.4,
			bulletSize = 0.14,
			muzzleVelocity = 700,
			bulletGravity = 85,
		},
		MP5 = { volume = 0.065, playbackSpeed = 1.5, muzzleVelocity = 820, bulletGravity = 60 },
		Bizon = { volume = 0.065, playbackSpeed = 1.4, muzzleVelocity = 800, bulletGravity = 65 },
		M16A4 = { playbackSpeed = 1.2, bulletColor = Color3.fromRGB(200, 255, 180) },
		M4A1 = { playbackSpeed = 1.25 },
		AKM = { playbackSpeed = 1.05, bulletColor = Color3.fromRGB(255, 200, 90) },
		AK74M = { playbackSpeed = 1.12, bulletColor = Color3.fromRGB(220, 255, 160) },
		M249 = { volume = 0.1, playbackSpeed = 0.92 },
		RPK = { volume = 0.1, playbackSpeed = 0.9 },
		M24 = {
			volume = 0.17,
			playbackSpeed = 0.75,
			bulletSize = 0.24,
			muzzleVelocity = 540,
			bulletGravity = 240,
		},
		SVD = {
			volume = 0.15,
			playbackSpeed = 0.82,
			bulletSize = 0.23,
			muzzleVelocity = 580,
			bulletGravity = 210,
		},
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
		bulletSize = feel.bulletSize,
		bulletColor = feel.bulletColor,
		muzzleVelocity = feel.muzzleVelocity,
		bulletGravity = feel.bulletGravity,
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
		if ov.bulletSize ~= nil then
			feel.bulletSize = ov.bulletSize
		end
		if ov.bulletColor ~= nil then
			feel.bulletColor = ov.bulletColor
		end
		if ov.muzzleVelocity ~= nil then
			feel.muzzleVelocity = ov.muzzleVelocity
		end
		if ov.bulletGravity ~= nil then
			feel.bulletGravity = ov.bulletGravity
		end
	end

	return feel
end

return WeaponAudio
