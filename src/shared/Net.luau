--!strict

-- Remote names. Payload shapes are documented beside each name; server validates.

local Net = {
	RoundState = "RoundState", -- Server → all: round + match score snapshot
	CaptureState = "CaptureState", -- Server → all: capture snapshot
	RoundEnded = "RoundEnded", -- Server → all: { winnerSide, reason, message, scoreLine, winningTeam, economySummary? }
	MatchEnded = "MatchEnded", -- Server → all: { winnerTeam, scoreLine, winsA, winsB }
	HudBanner = "HudBanner", -- Server → all: { text, kind }
	FireShot = "FireShot", -- Client → server: { origin, direction }
	WeaponFired = "WeaponFired", -- Server → all: { shooter, weaponId, origin, endPos, headshot? }
	PlayerState = "PlayerState", -- Server → player: loadout / cash / armor mirror
	BuyRequest = "BuyRequest", -- Client → server: { kind: "Weapon"|"Armor", id: string }
	BuyResult = "BuyResult", -- Server → player: { result, id?, cash?, message? }
	EconomyState = "EconomyState", -- Server → player: { cash, lossStreak }
	SelectWeapon = "SelectWeapon", -- Client → server: { slot: number } (1-based hotbar)
	ReloadRequest = "ReloadRequest", -- Client → server: {}
	SprintIntent = "SprintIntent", -- Client → server: { sprinting: boolean }
	DodgeRequest = "DodgeRequest", -- Client → server: {} (facing from character)
	MovementState = "MovementState", -- Server → player: stamina + dodge cooldown mirror
}

return Net
