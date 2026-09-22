--!strict
-- Tunables for VIP slice 0. Capture duration and sprint speed also define map geometry.

local GameConfig = {
	GameName = "VIP",

	-- Match / round — best of 7 (first to 4), sides alternate every round (§8.2)
	MinPlayersToStart = 2,
	MaxPlayersPerLobbyZone = 10, -- day and night ready pads each cap at 10 (5v5)
	LobbyCountdownSeconds = 5,
	RoundEndSeconds = 7,
	IntermissionSeconds = 10, -- lobby pad + side-swap announce between rounds
	MatchEndSeconds = 20, -- final scoreboard, then clear scores → lobby queue
	MatchWinsNeeded = 4, -- first to 4
	MaxRoundsInMatch = 7,
	RoundDurationSeconds = 300,
	CaptureDurationSeconds = 30,
	-- Last viable entry is strictly before this remaining time (t=270 → 30s left).
	CaptureEntryDeadlineRemaining = 30,
	LastEntryWarningRemaining = 35,

	--[[
		Elevated VIP briefing lobby (south of the city, high Y).
		City arena ≈ X±450 / Z −540…200 / walls ~148 — lobby sits further south
		and above so the greybox stays visible below + north in the distance.
		Compact pad; Day and Night ready zones share one platform.
	]]
	Lobby = {
		Center = Vector3.new(0, 185, -1050),
		PlatformSize = Vector3.new(78, 2, 42),
		DeckThickness = 2,
		RailHeight = 4,
		-- Ready pads sit on the deck; volumes are tall enough for HumanoidRootPart.
		ReadyZoneSize = Vector3.new(28, 12, 28),
		NightZoneLocalOffset = Vector3.new(-18, 0, 0), -- west pad
		DayZoneLocalOffset = Vector3.new(18, 0, 0), -- east pad
		SpawnLocalOffset = Vector3.new(0, 0, 14), -- south edge of deck (arrive outside pads)
	},

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

	-- Greybox layout. Anchor world positions live in MapMetrics; path ribbons
	-- encode §7.4 distances. Capture duration × sprint = contest radius R=660 —
	-- changing either invalidates MapMetrics and requires a map rebuild.
	Map = {
		-- Straight-line A↔B (~770); path ribbon A_to_B targets ~1000 (950–1100).
		SafeHouseSeparation = 770,
		HouseHalfSeparation = 385,
		GoodSpawnZ = -500, -- Motorcade
		TerroristSpawnZ = -50, -- Market Crossroads
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
