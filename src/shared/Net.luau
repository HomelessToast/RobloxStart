--!strict

-- Remote names. Payload shapes are documented beside each name; server validates.

local Net = {
	RoundState = "RoundState", -- Server → all: { state, timeRemaining, scores? }
	CaptureState = "CaptureState", -- Server → all: capture snapshot
	RoundEnded = "RoundEnded", -- Server → all: { winnerSide, reason, message }
	HudBanner = "HudBanner", -- Server → all: { text, kind }
	FireShot = "FireShot", -- Client → server: { origin, direction }
	PlayerState = "PlayerState", -- Server → player: { side, role, alive, ammo, reserve }
}

return Net
