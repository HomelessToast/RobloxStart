--!strict

export type Side = "Good" | "Terrorist" | "Spectator"
export type Role = "President" | "Bodyguard" | "Terrorist" | "Unassigned"
export type RoundState = "LOBBY" | "LIVE" | "CAPTURE" | "ROUND_END" | "INTERMISSION" | "MATCH_END"
export type RoundEndReason =
	"PRESIDENT_DEATH"
	| "PRESIDENT_DISCONNECT"
	| "TERRORISTS_WIPED"
	| "TIMER_EXPIRED"
	| "CAPTURE_COMPLETE"
export type CaptureState = "IDLE" | "ACTIVE" | "TOO_LATE" | "BROKEN" | "COMPLETE"
export type SafeHouseId = "A" | "B"

export type RoundSnapshot = {
	state: RoundState,
	timeRemaining: number,
	roundNumber: number,
	objectiveBanner: string,
	scoreLine: string?,
	winsA: number?,
	winsB: number?,
	winsNeeded: number?,
	sideA: string?,
	sideB: string?,
	lobbyMode: string?,
	announcement: string?,
}

export type CaptureSnapshot = {
	state: CaptureState,
	safeHouseId: SafeHouseId?,
	timeRemaining: number,
	progress: number, -- 0..1 while active
}

export type RoundEndPayload = {
	winnerSide: Side,
	reason: RoundEndReason,
	message: string,
}

export type PlayerStatePayload = {
	side: Side,
	role: Role,
	alive: boolean,
	ammo: number,
	reserve: number,
	weaponName: string,
}

return {}
