--!strict
--[[
	Owns best-of-7 match score and persistent Team A / Team B identity.

	Side swap (§8.2): sides alternate every round.
	  Round 1,3,5,7 → Team A = Good, Team B = Terrorist
	  Round 2,4,6   → Team A = Terrorist, Team B = Good

	First team to MatchWinsNeeded (4) round wins takes the match.
	Economy cash (when present) must travel with the team id, not the side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)

local MatchService = {}

export type TeamId = "A" | "B"

local matchActive = false
local roundIndex = 0 -- 1..MaxRoundsInMatch within an active match
local winsA = 0
local winsB = 0
local roster: { Player } = {}
local teamA: { Player } = {}
local teamB: { Player } = {}
-- President rotation cursor per persistent team (advances when that team plays Good).
local prezCursorA = 1
local prezCursorB = 1
local lobbyMode: string? = nil -- "Day" | "Night"
-- TEMP: set by RoundService debug solo pad; cleared in reset().
local debugSolo = false

local function sortByUserId(list: { Player }): { Player }
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

local function pruneList(list: { Player }): { Player }
	local kept = {}
	for _, player in list do
		if player.Parent then
			table.insert(kept, player)
		end
	end
	return kept
end

function MatchService.reset()
	matchActive = false
	roundIndex = 0
	winsA = 0
	winsB = 0
	table.clear(roster)
	table.clear(teamA)
	table.clear(teamB)
	prezCursorA = 1
	prezCursorB = 1
	lobbyMode = nil
	debugSolo = false
end

function MatchService.isActive(): boolean
	return matchActive
end

--- TEMP debug solo playtest — empty enemy team must not auto-end the round.
function MatchService.isDebugSolo(): boolean
	return debugSolo
end

function MatchService.setDebugSolo(enabled: boolean)
	debugSolo = enabled
end

function MatchService.getRoundIndex(): number
	return roundIndex
end

function MatchService.getWins(): (number, number)
	return winsA, winsB
end

function MatchService.getScoreLine(): string
	return string.format("%d–%d", winsA, winsB)
end

function MatchService.getLobbyMode(): string?
	return lobbyMode
end

function MatchService.getRoster(): { Player }
	return pruneList(roster)
end

function MatchService.getTeamPlayers(teamId: TeamId): { Player }
	if teamId == "A" then
		return pruneList(teamA)
	end
	return pruneList(teamB)
end

--[[
	Odd rounds: A=Good / B=Terrorist. Even rounds: sides swapped.
]]
function MatchService.getSideForTeam(teamId: TeamId): string
	local aIsGood = (roundIndex % 2) == 1
	if teamId == "A" then
		return if aIsGood then Enums.Side.Good else Enums.Side.Terrorist
	end
	return if aIsGood then Enums.Side.Terrorist else Enums.Side.Good
end

function MatchService.getTeamForSide(side: string): TeamId?
	if MatchService.getSideForTeam("A") == side then
		return "A"
	end
	if MatchService.getSideForTeam("B") == side then
		return "B"
	end
	return nil
end

function MatchService.didSidesSwapThisRound(): boolean
	return roundIndex > 1
end

--- Split roster into persistent Team A / Team B once at match start.
function MatchService.beginMatch(players: { Player }, mode: string)
	MatchService.reset()
	matchActive = true
	lobbyMode = mode
	roster = sortByUserId(table.clone(players))

	-- First half → A, second half → B (odd leftover goes to A).
	local n = #roster
	local split = math.ceil(n / 2)
	for i, player in roster do
		if i <= split then
			table.insert(teamA, player)
		else
			table.insert(teamB, player)
		end
	end

	print(
		string.format(
			"[MatchService] Match start (%s): Team A=%d, Team B=%d, first to %d",
			mode,
			#teamA,
			#teamB,
			GameConfig.MatchWinsNeeded
		)
	)
end

--- Advance to the next round index inside an active match. Returns false if match cannot continue.
function MatchService.beginNextRound(): boolean
	if not matchActive then
		return false
	end
	if roundIndex >= GameConfig.MaxRoundsInMatch then
		return false
	end
	if winsA >= GameConfig.MatchWinsNeeded or winsB >= GameConfig.MatchWinsNeeded then
		return false
	end
	roundIndex += 1
	-- Drop disconnected players from seating lists but keep the match going.
	teamA = pruneList(teamA)
	teamB = pruneList(teamB)
	roster = pruneList(roster)
	return true
end

export type RoundCommit = {
	winningTeam: TeamId,
	winsA: number,
	winsB: number,
	matchOver: boolean,
	matchWinner: TeamId?,
}

function MatchService.commitRoundWin(winnerSide: string): RoundCommit
	local teamId = MatchService.getTeamForSide(winnerSide)
	if not teamId then
		-- Degenerate: no mapped team (should not happen mid-match).
		teamId = "A"
	end
	if teamId == "A" then
		winsA += 1
	else
		winsB += 1
	end

	local matchWinner: TeamId? = nil
	local matchOver = false
	if winsA >= GameConfig.MatchWinsNeeded then
		matchOver = true
		matchWinner = "A"
	elseif winsB >= GameConfig.MatchWinsNeeded then
		matchOver = true
		matchWinner = "B"
	elseif roundIndex >= GameConfig.MaxRoundsInMatch then
		-- First-to-4 across ≤7 rounds cannot tie; treat higher score as winner.
		matchOver = true
		if winsA > winsB then
			matchWinner = "A"
		elseif winsB > winsA then
			matchWinner = "B"
		end
	end

	return {
		winningTeam = teamId,
		winsA = winsA,
		winsB = winsB,
		matchOver = matchOver,
		matchWinner = matchWinner,
	}
end

--[[
	President pick among the Good side for the current round.
	Rule (documented for Matthew):
	  • Solo Good player → they are President.
	  • Otherwise rotate by UserId order within the persistent team that is Good,
	    advancing the cursor each time that team plays Good.
]]
function MatchService.pickPresident(goodPlayers: { Player }): Player?
	local sorted = sortByUserId(table.clone(goodPlayers))
	if #sorted == 0 then
		return nil
	end
	if #sorted == 1 then
		return sorted[1]
	end

	local goodTeam = MatchService.getTeamForSide(Enums.Side.Good)
	local cursor = if goodTeam == "B" then prezCursorB else prezCursorA
	-- Wrap into 1..n
	local index = ((cursor - 1) % #sorted) + 1
	local chosen = sorted[index]

	if goodTeam == "B" then
		prezCursorB = index + 1
	else
		prezCursorA = index + 1
	end
	return chosen
end

function MatchService.snapshot()
	return {
		active = matchActive,
		roundIndex = roundIndex,
		winsA = winsA,
		winsB = winsB,
		scoreLine = MatchService.getScoreLine(),
		sideA = if matchActive and roundIndex > 0
			then MatchService.getSideForTeam("A")
			else Enums.Side.Spectator,
		sideB = if matchActive and roundIndex > 0
			then MatchService.getSideForTeam("B")
			else Enums.Side.Spectator,
		lobbyMode = lobbyMode,
		winsNeeded = GameConfig.MatchWinsNeeded,
	}
end

return MatchService
