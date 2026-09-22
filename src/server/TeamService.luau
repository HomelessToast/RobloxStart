--!strict
-- Slice 0: hard-coded assignment. First good player is President; rest fill 4 BG + 5 T.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)

export type Assignment = {
	side: string,
	role: string,
}

local TeamService = {}

local assignments: { [Player]: Assignment } = {}
local president: Player? = nil

local function sortPlayers(list: { Player }): { Player }
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function TeamService.reset()
	table.clear(assignments)
	president = nil
end

function TeamService.assignForRound(players: { Player })
	TeamService.reset()
	local sorted = sortPlayers(table.clone(players))

	-- Alternate into Good / Terrorist seats: seats 1..5 good (1=President), 6..10 terrorist.
	for index, player in sorted do
		if index <= 5 then
			local role = if index == 1 then Enums.Role.President else Enums.Role.Bodyguard
			assignments[player] = {
				side = Enums.Side.Good,
				role = role,
			}
			if role == Enums.Role.President then
				president = player
			end
		else
			assignments[player] = {
				side = Enums.Side.Terrorist,
				role = Enums.Role.Terrorist,
			}
		end
	end

	-- With only 2 players: P1 President (Good), P2 Terrorist.
	-- With 3+: fill bodyguards before overflowing to terrorists (already handled by index).
end

function TeamService.getAssignment(player: Player): Assignment
	return assignments[player]
		or {
			side = Enums.Side.Spectator,
			role = Enums.Role.Unassigned,
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

function TeamService.clearPlayer(player: Player)
	if president == player then
		president = nil
	end
	assignments[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	-- RoundService / ObjectiveService observe disconnect; we only clear after round handles it.
	-- Keep assignment until RoundService calls clear/reset.
	if not player then
		return
	end
end)

return TeamService
