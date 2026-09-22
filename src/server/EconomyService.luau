--!strict
-- Cash ledger. Server-owned; HUD is a mirror. Cash persists; loadouts do not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(script.Parent.Remotes)
local TeamService = require(script.Parent.TeamService)

local EconomyService = {}

local cash: { [Player]: number } = {}
-- Loss streak tracks the persistent *team* through side swaps. Slice uses
-- seat-band identity: lowest-half UserIds = TeamA, rest = TeamB once assigned.
local lossStreakByTeam: { [string]: number } = { A = 0, B = 0 }
local teamOfPlayer: { [Player]: string } = {}

local function clampCash(amount: number): number
	return math.clamp(math.floor(amount + 0.5), 0, GameConfig.Economy.CashCap)
end

local function ensurePlayer(player: Player)
	if cash[player] == nil then
		cash[player] = GameConfig.Economy.StartingCash
	end
	if teamOfPlayer[player] == nil then
		teamOfPlayer[player] = "A"
	end
end

function EconomyService.setTeam(player: Player, teamId: string)
	ensurePlayer(player)
	teamOfPlayer[player] = teamId
end

function EconomyService.getCash(player: Player): number
	ensurePlayer(player)
	return cash[player] :: number
end

function EconomyService.setCash(player: Player, amount: number): number
	ensurePlayer(player)
	cash[player] = clampCash(amount)
	EconomyService.push(player)
	return cash[player] :: number
end

function EconomyService.getLossStreak(teamId: string): number
	return lossStreakByTeam[teamId] or 0
end

function EconomyService.addCash(player: Player, delta: number, _reason: string?): number
	ensurePlayer(player)
	cash[player] = clampCash((cash[player] :: number) + delta)
	EconomyService.push(player)
	return cash[player] :: number
end

function EconomyService.trySpend(player: Player, amount: number): boolean
	ensurePlayer(player)
	if (cash[player] :: number) < amount then
		return false
	end
	cash[player] = clampCash((cash[player] :: number) - amount)
	EconomyService.push(player)
	return true
end

function EconomyService.refund(player: Player, amount: number)
	EconomyService.addCash(player, amount, "refund")
end

function EconomyService.push(player: Player)
	ensurePlayer(player)
	local teamId = teamOfPlayer[player] or "A"
	Remotes.get(Net.EconomyState):FireClient(player, {
		cash = cash[player],
		lossStreak = lossStreakByTeam[teamId] or 0,
	})
end

function EconomyService.pushAll()
	for _, player in Players:GetPlayers() do
		EconomyService.push(player)
	end
end

local function lossBonus(streak: number): number
	local ladder = GameConfig.Economy.LossBonuses
	local index = math.clamp(streak, 1, #ladder)
	return ladder[index]
end

export type SettleContext = {
	winnerSide: string,
	reason: string,
	presidentKiller: Player?,
	captureWasActiveOnPresidentDeath: boolean?,
	aliveBodyguardsOnCapture: { Player }?,
}

function EconomyService.settleRound(ctx: SettleContext): { [Player]: number }
	local deltas: { [Player]: number } = {}
	local function credit(player: Player, amount: number)
		if amount == 0 then
			return
		end
		deltas[player] = (deltas[player] or 0) + amount
		EconomyService.addCash(player, amount, "settle")
	end

	local eco = GameConfig.Economy

	-- Team win / loss bonuses + streak update
	local winningTeams: { [string]: boolean } = {}
	local losingTeams: { [string]: boolean } = {}

	for _, player in Players:GetPlayers() do
		ensurePlayer(player)
		local side = TeamService.getSide(player)
		if side ~= Enums.Side.Spectator then
			local teamId = teamOfPlayer[player] or "A"
			if side == ctx.winnerSide then
				winningTeams[teamId] = true
				credit(player, eco.WinBonus)
			else
				losingTeams[teamId] = true
			end

			-- Survival bonus
			if TeamService.hasLivingBody(player) then
				credit(player, eco.SurvivalBonus)
				if TeamService.getRole(player) == Enums.Role.President then
					credit(player, eco.PresidentSurvivalBonus)
				end
			end
		end
	end

	for teamId in losingTeams do
		if not winningTeams[teamId] then
			local nextStreak = (lossStreakByTeam[teamId] or 0) + 1
			lossStreakByTeam[teamId] = nextStreak
			local bonus = lossBonus(nextStreak)
			for _, player in Players:GetPlayers() do
				if teamOfPlayer[player] == teamId then
					credit(player, bonus)
				end
			end
		end
	end

	for teamId in winningTeams do
		lossStreakByTeam[teamId] = 0
	end

	-- Capture completion bodyguard bonus
	if ctx.reason == Enums.RoundEndReason.CaptureComplete and ctx.aliveBodyguardsOnCapture then
		for _, player in ctx.aliveBodyguardsOnCapture do
			credit(player, eco.BodyguardCaptureBonus)
		end
	end

	-- President kill bonuses (applied at death time too — settle only if not yet paid)
	-- Kill rewards are paid live via EconomyService.onKill; settle handles round bonuses only.

	return deltas
end

function EconomyService.onKill(
	killer: Player?,
	victim: Player,
	opts: {
		victimWasPresident: boolean,
		captureActive: boolean,
	}?
)
	if not killer or killer == victim then
		-- Suicide / fall: penalty, no killer credit
		if victim then
			EconomyService.addCash(victim, -GameConfig.Economy.SuicidePenalty, "suicide")
		end
		return
	end

	local eco = GameConfig.Economy
	local payout = eco.KillReward
	if opts and opts.victimWasPresident then
		payout += eco.PresidentKillBonus
		if opts.captureActive then
			payout += eco.CaptureBreakKillBonus
		end
	end
	EconomyService.addCash(killer, payout, "kill")
end

function EconomyService.clearPlayer(player: Player)
	cash[player] = nil
	teamOfPlayer[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	ensurePlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Keep cash across brief reconnects within the session? Slice: clear.
	EconomyService.clearPlayer(player)
end)

for _, player in Players:GetPlayers() do
	ensurePlayer(player)
end

return EconomyService
