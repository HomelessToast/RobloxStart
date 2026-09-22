--!strict
-- Fire sounds + kick magnitude by visual class. Uses classic free Roblox library
-- SoundIds (public toolbox / engine commons). Fail-soft if an ID is unavailable.

local WeaponDefs = require(script.Parent.WeaponDefs)
local WeaponVisuals = require(script.Parent.WeaponVisuals)

export type FireFeel = {
	soundId: string,
	volume: number,
	playbackSpeed: number,
	kickDegrees: number,
	tracerWidth: number,
	tracerColor: Color3,
	muzzleBrightness: number,
}

local WeaponAudio = {}

-- Playtest: volumes ~1/3 prior; kick ~1/3 prior (was too loud / brutal).
local CLASS_FEEL: { [WeaponVisuals.VisualClass]: FireFeel } = {
	Pistol = {
		soundId = "rbxassetid://131212918",
		volume = 0.22,
		playbackSpeed = 1.15,
		kickDegrees = 1.0,
		tracerWidth = 0.08,
		tracerColor = Color3.fromRGB(255, 220, 120),
		muzzleBrightness = 3,
	},
	SMG = {
		soundId = "rbxassetid://142274259",
		volume = 0.18,
		playbackSpeed = 1.35,
		kickDegrees = 0.7,
		tracerWidth = 0.07,
		tracerColor = Color3.fromRGB(255, 200, 90),
		muzzleBrightness = 2.5,
	},
	Shotgun = {
		soundId = "rbxassetid://376568231",
		volume = 0.28,
		playbackSpeed = 0.95,
		kickDegrees = 2.0,
		tracerWidth = 0.12,
		tracerColor = Color3.fromRGB(255, 180, 80),
		muzzleBrightness = 5,
	},
	Assault = {
		soundId = "rbxassetid://165969964",
		volume = 0.2,
		playbackSpeed = 1.05,
		kickDegrees = 0.9,
		tracerWidth = 0.09,
		tracerColor = Color3.fromRGB(255, 230, 140),
		muzzleBrightness = 3.5,
	},
	LMG = {
		soundId = "rbxassetid://165969964",
		volume = 0.24,
		playbackSpeed = 0.9,
		kickDegrees = 1.2,
		tracerWidth = 0.1,
		tracerColor = Color3.fromRGB(255, 200, 100),
		muzzleBrightness = 4,
	},
	Sniper = {
		soundId = "rbxassetid://458755748",
		volume = 0.28,
		playbackSpeed = 0.85,
		kickDegrees = 2.2,
		tracerWidth = 0.11,
		tracerColor = Color3.fromRGB(255, 240, 180),
		muzzleBrightness = 6,
	},
}

function WeaponAudio.feelFor(weaponId: string): FireFeel
	local def = WeaponDefs.get(weaponId)
	local class: WeaponVisuals.VisualClass = if def
		then WeaponVisuals.visualClass(def)
		else "Assault"
	return CLASS_FEEL[class]
end

return WeaponAudio
