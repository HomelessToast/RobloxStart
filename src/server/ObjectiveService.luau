--!strict
--[[
	Win matrix resolution order (§2.1), evaluated every tick:
	1. President death → Terrorists
	2. President disconnect → Terrorists
	3. All terrorists eliminated → Good
	4. Round timer expires → Terrorists (beats capture completion same tick)
	5. Capture completes → Good
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local TeamService = require(script.Parent.TeamService)
local CaptureService = require(script.Parent.CaptureService)

local ObjectiveService = {}

export type Resolution = {
	winnerSide: string,
	reason: string,
	message: string,
}

local presidentDied = false
local presidentDisconnected = false
local killerOfPresident: Player? = nil

function ObjectiveService.resetFlags()
	presidentDied = false
	presidentDisconnected = false
	killerOfPresident = nil
end

function ObjectiveService.noticePresidentDeath(killer: Player?)
	presidentDied = true
	killerOfPresident = killer
end

function ObjectiveService.noticePresidentDisconnect()
	presidentDisconnected = true
end

local function livingOnSide(side: string): number
	local count = 0
	for _, player in TeamService.getPlayersOnSide(side) do
		if TeamService.isAliveCharacter(player) then
			count += 1
		end
	end
	return count
end

function ObjectiveService.evaluate(roundRemaining: number): Resolution?
	-- 1. President death
	if presidentDied then
		local extra = if killerOfPresident
			then string.format(" (killed by %s)", killerOfPresident.Name)
			else ""
		return {
			winnerSide = Enums.Side.Terrorist,
			reason = Enums.RoundEndReason.PresidentDeath,
			message = "President eliminated — Terrorists win" .. extra,
		}
	end

	-- 2. President disconnect
	if presidentDisconnected then
		return {
			winnerSide = Enums.Side.Terrorist,
			reason = Enums.RoundEndReason.PresidentDisconnect,
			message = "President disconnected — Terrorists win",
		}
	end

	local prez = TeamService.getPresident()
	if not prez then
		return {
			winnerSide = Enums.Side.Terrorist,
			reason = Enums.RoundEndReason.PresidentDisconnect,
			message = "President missing — Terrorists win",
		}
	end
	-- Only resolve death once the President has a body in the world.
	if prez.Character and not TeamService.hasLivingBody(prez) then
		return {
			winnerSide = Enums.Side.Terrorist,
			reason = Enums.RoundEndReason.PresidentDeath,
			message = "President eliminated — Terrorists win",
		}
	end

	-- 3. Terrorists wiped (players still spawning count as alive)
	if livingOnSide(Enums.Side.Terrorist) <= 0 then
		return {
			winnerSide = Enums.Side.Good,
			reason = Enums.RoundEndReason.TerroristsWiped,
			message = "All terrorists eliminated — Good wins",
		}
	end

	-- 4. Timer expiry (beats capture completion on the same tick)
	if roundRemaining <= 0 then
		return {
			winnerSide = Enums.Side.Terrorist,
			reason = Enums.RoundEndReason.TimerExpired,
			message = "300s expired — Terrorists win (including mid-capture)",
		}
	end

	-- 5. Capture complete
	if CaptureService.isComplete() then
		return {
			winnerSide = Enums.Side.Good,
			reason = Enums.RoundEndReason.CaptureComplete,
			message = "Safe house secured — Good wins",
		}
	end

	return nil
end

function ObjectiveService.objectiveBanner(roundRemaining: number, roundState: string): string
	if roundState == Enums.RoundState.RoundEnd then
		return "ROUND OVER"
	end
	if roundRemaining <= GameConfig.CaptureEntryDeadlineRemaining then
		return "ELIMINATE — capture no longer possible"
	end
	if CaptureService.isActive() then
		return "HOLD — capture in progress"
	end
	return "ESCORT — reach a safe house before t=270"
end

return ObjectiveService
