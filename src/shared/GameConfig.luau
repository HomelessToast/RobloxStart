--!strict
-- Tunables for VIP slice 0. Capture duration and sprint speed also define map geometry.

local GameConfig = {
	GameName = "VIP",

	-- Match / round (slice 0: endless rounds, no bo7 / side swap yet)
	MinPlayersToStart = 2,
	LobbyCountdownSeconds = 5,
	RoundEndSeconds = 7,
	RoundDurationSeconds = 300,
	CaptureDurationSeconds = 30,
	-- Last viable entry is strictly before this remaining time (t=270 → 30s left).
	CaptureEntryDeadlineRemaining = 30,
	LastEntryWarningRemaining = 35,

	-- Combat
	FriendlyFire = false,
	StartingHealth = 100,
	MaxHealth = 100,
	FireRateSeconds = 0.18,
	MaxShotDistance = 800,
	HitValidationSlopStuds = 12,

	-- Movement (map parameter)
	SprintSpeed = 22,
	WalkSpeed = 16,

	-- Greybox layout (studs). Straight-line targets approximating §7.4 path distances.
	Map = {
		SafeHouseSeparation = 800, -- ~770 straight-line ≈ 1000 path with friction
		HouseHalfSeparation = 400,
		GoodSpawnZ = -480,
		TerroristSpawnZ = 40,
		FloorY = 0,
		CaptureSize = Vector3.new(48, 24, 48),
		HouseInteriorSize = Vector3.new(56, 20, 56),
	},

	-- Slice 0 weapons: one P0 per side, no buy / economy
	Weapons = {
		GoodPistol = {
			id = "M9",
			displayName = "M9 Beretta",
			damage = 28,
			magazine = 15,
			reserve = 60,
		},
		TerroristPistol = {
			id = "Makarov",
			displayName = "Makarov PM",
			damage = 30,
			magazine = 8,
			reserve = 48,
		},
	},
}

return GameConfig
