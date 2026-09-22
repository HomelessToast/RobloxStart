--!strict

local Enums = {}

Enums.RoundState = {
	Lobby = "LOBBY",
	Buy = "BUY",
	Live = "LIVE",
	Capture = "CAPTURE",
	RoundEnd = "ROUND_END",
	Intermission = "INTERMISSION",
	MatchEnd = "MATCH_END",
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

Enums.PurchaseResult = {
	Ok = "OK",
	NotBuyPhase = "NOT_BUY_PHASE",
	CannotAfford = "CANNOT_AFFORD",
	WrongSide = "WRONG_SIDE",
	PresidentPrimaryLocked = "PRESIDENT_PRIMARY_LOCKED",
	UnknownItem = "UNKNOWN_ITEM",
	AlreadyOwned = "ALREADY_OWNED",
	HotbarFull = "HOTBAR_FULL",
	Dead = "DEAD",
}

Enums.ArmorId = {
	None = "None",
	Light = "Light",
	Heavy = "Heavy",
}

return Enums
