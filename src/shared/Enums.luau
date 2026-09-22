--!strict

local Enums = {}

Enums.RoundState = {
	Lobby = "LOBBY",
	Live = "LIVE",
	Capture = "CAPTURE",
	RoundEnd = "ROUND_END",
}

Enums.Side = {
	Good = "Good",
	Terrorist = "Terrorist",
	Spectator = "Spectator",
}

Enums.Role = {
	President = "President",
	Bodyguard = "Bodyguard",
	Terrorist = "Terrorist",
	Unassigned = "Unassigned",
}

Enums.RoundEndReason = {
	PresidentDeath = "PRESIDENT_DEATH",
	PresidentDisconnect = "PRESIDENT_DISCONNECT",
	TerroristsWiped = "TERRORISTS_WIPED",
	TimerExpired = "TIMER_EXPIRED",
	CaptureComplete = "CAPTURE_COMPLETE",
}

Enums.CaptureState = {
	Idle = "IDLE",
	Active = "ACTIVE",
	TooLate = "TOO_LATE",
	Broken = "BROKEN",
	Complete = "COMPLETE",
}

Enums.SafeHouseId = {
	A = "A",
	B = "B",
}

return Enums
