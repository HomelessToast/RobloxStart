--!strict
--[[
	Persistent Team A / Team B come from MatchService. This module maps those
	teams onto Good / Terrorist for the current round and assigns the President.

	President rule (slice match flow):
	  • If only one player is on the Good/VIP side → that player is President.
	  • Otherwise rotate among the Good side by stable UserId order (cursor
	    owned by MatchService per persistent team so each side shares the role
	    fairly across the bo7).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local MatchService = require(script.Parent.MatchService)

export type Assignment = {
	side: string,
	role: string,
	teamId: string?, -- "A" | "B" while a match is active
}

local TeamService = {}

local assignments: { [Player]: Assignment } = {}
local president: Player? = nil

function TeamService.reset()
	table.clear(assignments)
	president = nil
end

--- Assign sides/roles for the current MatchService round index.
function TeamService.assignForRound(_players: { Player })
	TeamService.reset()

	local function seat(teamId: MatchService.TeamId)
		local side = MatchService.getSideForTeam(teamId)
		local members = MatchService.getTeamPlayers(teamId)
		for _, player in members do
			if side == Enums.Side.Good then
				assignments[player] = {
					side = Enums.Side.Good,
					role = Enums.Role.Bodyguard, -- President overwritten below
					teamId = teamId,
				}
			else
				assignments[player] = {
					side = Enums.Side.Terrorist,
					role = Enums.Role.Terrorist,
					teamId = teamId,
				}
			end
		end
	end

	seat("A")
	seat("B")

	local goodPlayers = TeamService.getPlayersOnSide(Enums.Side.Good)
	local chosen = MatchService.pickPresident(goodPlayers)
	if chosen then
		local existing = assignments[chosen]
		if existing then
			existing.role = Enums.Role.President
			president = chosen
		end
	end
end

function TeamService.getAssignment(player: Player): Assignment
	return assignments[player]
		or {
			side = Enums.Side.Spectator,
			role = Enums.Role.Unassigned,
			teamId = nil,
		}
end

function TeamService.getSide(player: Player): string
	return TeamService.getAssignment(player).side
end

function TeamService.getRole(player: Player): string
	return TeamService.getAssignment(player).role
end

function TeamService.getPresident(): Player?
	if president and president.Parent then
		return president
	end
	return nil
end

function TeamService.getPlayersOnSide(side: string): { Player }
	local result = {}
	for player, assignment in assignments do
		if player.Parent and assignment.side == side then
			table.insert(result, player)
		end
	end
	return result
end

function TeamService.isAliveCharacter(player: Player): boolean
	local character = player.Character
	if not character then
		-- Not spawned yet — do not treat as eliminated (avoids false wipe on round start).
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function TeamService.hasLivingBody(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function TeamService.getTeamId(player: Player): string?
	return TeamService.getAssignment(player).teamId
end

function TeamService.getAliveBodyguards(): { Player }
	local result = {}
	for player, assignment in assignments do
		if
			player.Parent
			and assignment.role == Enums.Role.Bodyguard
			and TeamService.hasLivingBody(player)
		then
			table.insert(result, player)
		end
	end
	return result
end

function TeamService.clearPlayer(player: Player)
	if president == player then
		president = nil
	end
	assignments[player] = nil
end

return TeamService
