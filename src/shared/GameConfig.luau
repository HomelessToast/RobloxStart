--!strict
-- Tunables for VIP. Capture duration and sprint speed also define map geometry.
-- Economy + armor: grounded in design doc §4 / §5.2 (see docs/vip-economy-weapons.md).

local GameConfig = {
	GameName = "VIP",

	-- Match / round — best of 7 (first to 4), sides alternate every round (§8.2)
	MinPlayersToStart = 2,
	MaxPlayersPerLobbyZone = 10, -- day and night ready pads each cap at 10 (5v5)
	LobbyCountdownSeconds = 5,
	BuyPhaseSeconds = 30, -- Matthew: 30s buy window with picture menu
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

	-- Side swap is owned by MatchService (§8.2); kept here as documentation.
	SideSwapEveryRound = true,

	--[[
		Elevated VIP briefing lobby (south of the city, high Y).
		City arena ≈ X±450 / Z −540…200 / walls ~148 — lobby sits further south
		and above so the greybox stays visible below + north in the distance.
		Compact pad; Day and Night ready zones share one platform.
		Owned by LobbyService — do not relocate from weapons/economy work.
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

	--[[
		TEMP / DEV-ONLY — solo playtest pad on the lobby deck.
		Matthew: walk onto it to skip matchmaking and jump into BUY (same 30s gun UI).
		Kill-switch: set Enabled = false (pad is not built; RoundService ignores it).
		Remove this block + LobbyService debug builders + RoundService debug start for prod.
	]]
	Debug = {
		SoloPlaytestPadEnabled = true,
		-- North edge of deck (toward city), in the center gap between Day/Night pads.
		ZoneLocalOffset = Vector3.new(0, 0, -17),
		ZoneSize = Vector3.new(10, 12, 10),
		-- Lighting for the debug match (does not arm Day/Night ready pads).
		LobbyMode = "Night",
		-- Seat as Good bodyguard so full Good arsenal is legal; no President / empty-team auto-wins.
		Side = "Good",
		-- Huge cash (clamped to Economy.CashCap) so solo debug can buy freely.
		GrantCash = 12000,
	},

	-- Combat
	FriendlyFire = false,
	StartingHealth = 100,
	MaxHealth = 100,
	MaxShotDistance = 800,
	HitValidationSlopStuds = 12,

	-- Sniper ADS (client): hold RMB → FOV zoom + scope overlay. LMB still fires.
	SniperAds = {
		Fov = 18,
		TweenIn = 0.12,
		TweenOut = 0.1,
		DefaultFovFallback = 70,
	},

	-- Armor (§5.2) — damage pool, not % reduction
	Armor = {
		BodyAbsorbFraction = 0.6, -- [A] primary combat dial; also in Ballistics
		Light = {
			id = "Light",
			displayName = "Light Armor",
			price = 650,
			pool = 50,
			hasHelmet = false,
		},
		Heavy = {
			id = "Heavy",
			displayName = "Heavy Armor + Helmet",
			price = 1050,
			pool = 100,
			hasHelmet = true,
		},
	},

	-- Economy (§4.2) — cash is the only thing that persists across rounds
	Economy = {
		StartingCash = 900,
		CashCap = 12000,
		WinBonus = 3000,
		-- Loss streak ladder (per team, resets on a win). Steeper than CS because
		-- nothing carries and sides alternate — no salvaged rifles.
		LossBonuses = { 1600, 2300, 3000, 3700, 4200 },
		KillReward = 300, -- flat, all weapons
		PresidentKillBonus = 900, -- on top of KillReward → $1,200 total for VIP kill
		CaptureBreakKillBonus = 400, -- [A] killing President inside an active capture
		SurvivalBonus = 200, -- [A] material incentive when gear doesn't carry
		BodyguardCaptureBonus = 400, -- alive bodyguard when capture completes
		PresidentSurvivalBonus = 500, -- offsets pistol-only earning ceiling
		SuicidePenalty = 300,
		TeamKillPenalty = 500, -- N/A while FriendlyFire=false; kept for config completeness
		Utility = {
			Smoke = 250,
			Flash = 250,
			Frag = 350,
		},
	},

	-- Movement (map parameter). SprintSpeed × CaptureDuration = contest radius R.
	-- Changing SprintSpeed invalidates MapMetrics / greybox geometry.
	SprintSpeed = 22,
	WalkSpeed = 16,

	-- Sprint stamina — every character. Server-owned; client sends intent.
	-- Client plays RunAnimation* while MovementState.sprinting + moving.
	Sprint = {
		MaxStamina = 100,
		DrainPerSecond = 16, -- ~6.25s continuous sprint
		RegenPerSecond = 14, -- ~7.1s empty → full
		RegenDelaySeconds = 0.4, -- pause after releasing sprint before regen
		MinStaminaToStart = 8, -- cannot start a sprint below this
		-- Official Roblox Animate run clips (Movement priority overlay).
		RunAnimationR15 = "rbxassetid://507767714",
		RunAnimationR6 = "rbxassetid://180426354",
		RunAnimSpeed = 1.2, -- slightly snappier than default run
	},

	-- Dodge / roll (Q) — unified for all characters (was President-only in design §5.3).
	-- Server: upright AlignOrientation + LinearVelocity on locked flat axis.
	-- Client: procedural forward-roll AnimationTrack (HRP never pitches).
	-- See docs/vip-movement.md.
	Dodge = {
		Distance = 55, -- studs horizontal (covers §7.5 open-ground gaps ≤60)
		Duration = 0.45, -- travel window; client rolls one somersault over this
		RecoverySeconds = 0.3, -- cannot fire until recovery ends
		CooldownSeconds = 30, -- starts on activation; HUD bottom-left shows remaining
		GroundRayLength = 4, -- must be near ground to roll
		-- Horizontal force cap as multiples of AssemblyMass (finite ⇒ no wall fling).
		MaxForcePerMass = 9000,
	},

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
}

return GameConfig
