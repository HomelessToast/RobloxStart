--!strict
--[[
	Round + match state machine.

	  LOBBY → BUY → LIVE ⇄ CAPTURE → ROUND_END → INTERMISSION → BUY → LIVE …
	                                          └→ MATCH_END → LOBBY

	Lobby start is gated by Day/Night ready pads (LobbyService). Mid-match
	rounds auto-continue with the same roster after INTERMISSION — players are
	teleported back to the armed ready pad between rounds, then onto the map
	for BUY (frozen) before LIVE.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)

local Remotes = require(script.Parent.Remotes)
local MapService = require(script.Parent.MapService)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local TeamService = require(script.Parent.TeamService)
local SpawnService = require(script.Parent.SpawnService)
local LoadoutService = require(script.Parent.LoadoutService)
local WeaponService = require(script.Parent.WeaponService)
local CombatService = require(script.Parent.CombatService)
local CaptureService = require(script.Parent.CaptureService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local EconomyService = require(script.Parent.EconomyService)
local BuyService = require(script.Parent.BuyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local AbilityService = require(script.Parent.AbilityService)
local AppearanceService = require(script.Parent.AppearanceService)
local WeaponVisuals = require(ReplicatedStorage.Shared.WeaponVisuals)

local RoundService = {}

local state = Enums.RoundState.Lobby
local timeRemaining = 0
local lobbyCountdown = 0
local ending = false
local transitioning = false -- true while a yielding transition (beginLive / match start) runs
local heartbeatConn: RBXScriptConnection? = nil
local broadcastAccum = 0
local BROADCAST_INTERVAL = 0.25
local lastAnnouncement: string? = nil

-- Which ready pad armed the current lobby countdown (nil = waiting for a zone).
local pendingMode: LobbyService.LobbyMode? = nil
-- Last committed round resolution (shown through ROUND_END / INTERMISSION).
local lastResolution: ObjectiveService.Resolution? = nil
local lastCommit: MatchService.RoundCommit? = nil
local lastEconomySummary = ""

local function announce(text: string, kind: string?)
	lastAnnouncement = text
	Remotes.get(Net.HudBanner):FireAllClients({
		text = text,
		kind = kind or "info",
	})
end

local function broadcastRound()
	local match = MatchService.snapshot()
	local roundNumber = match.roundIndex
	local banner = ObjectiveService.objectiveBanner(timeRemaining, state)

	if state == Enums.RoundState.Lobby then
		local nightN = #LobbyService.getPlayersInZone("Night")
		local dayN = #LobbyService.getPlayersInZone("Day")
		local minN = GameConfig.MinPlayersToStart
		local maxN = GameConfig.MaxPlayersPerLobbyZone
		if pendingMode then
			banner = string.format(
				"%s READY — match starts in %ds (%d/%d)",
				string.upper(pendingMode),
				math.max(0, math.ceil(lobbyCountdown)),
				#LobbyService.getPlayersInZone(pendingMode),
				maxN
			)
		else
			local debugHint = if GameConfig.Debug.SoloPlaytestPadEnabled
				then " · or DEBUG pad (solo)"
				else ""
			banner = string.format(
				"Stand in DAY or NIGHT ready pad · Night %d  Day %d  (need %d–%d)%s",
				nightN,
				dayN,
				minN,
				maxN,
				debugHint
			)
		end
	elseif state == Enums.RoundState.Buy then
		banner = string.format(
			"BUY PHASE — %ds · Score %s · X for shop",
			math.max(0, math.ceil(timeRemaining)),
			match.scoreLine
		)
	elseif state == Enums.RoundState.RoundEnd and lastResolution then
		banner = string.format(
			"ROUND OVER — %s  ·  Score %s",
			lastResolution.message,
			match.scoreLine
		)
	elseif state == Enums.RoundState.Intermission then
		local sideNote = if MatchService.didSidesSwapThisRound() or (roundNumber >= 1)
			then "Teams swap sides"
			else "Opening sides"
		banner = string.format(
			"Round %d · %s · Score %s (first to %d)",
			roundNumber,
			sideNote,
			match.scoreLine,
			GameConfig.MatchWinsNeeded
		)
	elseif state == Enums.RoundState.MatchEnd then
		local winner = if lastCommit and lastCommit.matchWinner
			then string.format("Team %s", lastCommit.matchWinner)
			else "—"
		banner = string.format("MATCH OVER — %s wins  %s", winner, match.scoreLine)
	end

	Remotes.get(Net.RoundState):FireAllClients({
		state = state,
		timeRemaining = math.max(timeRemaining, 0),
		roundNumber = roundNumber,
		objectiveBanner = banner,
		lobbyMode = match.lobbyMode or pendingMode,
		scoreLine = match.scoreLine,
		winsA = match.winsA,
		winsB = match.winsB,
		winsNeeded = match.winsNeeded,
		sideA = match.sideA,
		sideB = match.sideB,
		announcement = lastAnnouncement,
	})
end

local function broadcastRoundThrottled(dt: number, force: boolean?)
	broadcastAccum += dt
	if force or broadcastAccum >= BROADCAST_INTERVAL then
		broadcastAccum = 0
		broadcastRound()
	end
end

local function pushAllPlayerStates()
	for _, player in MatchService.getRoster() do
		WeaponService.pushPlayerState(player)
		EconomyService.push(player)
	end
end

--[[
	Matthew: guns + role skins despawn after each round.
	Clears hotbar/ammo/visuals and restores default avatar before lobby /
	intermission. BUY re-grants via prepareBuyPlayers.
]]
local function stripGearForLobby(players: { Player }?)
	local list = players or Players:GetPlayers()
	LoadoutService.clear()
	WeaponService.reset()
	for _, player in list do
		local character = player.Character
		if character then
			WeaponVisuals.clearFromCharacter(character)
			character:SetAttribute("Side", Enums.Side.Spectator)
			character:SetAttribute("Role", Enums.Role.Unassigned)
			character:SetAttribute("WeaponId", "")
		end
		AppearanceService.restoreAvatar(player)
		WeaponService.pushPlayerState(player)
	end
end

local function respawnPlayer(player: Player)
	player:LoadCharacter()
end

-- Yielding teleports run off Heartbeat so the round clock never stalls mid-step.
local function teleportRosterToLobbyPad(mode: LobbyService.LobbyMode?)
	stripGearForLobby()
	task.spawn(function()
		for _, player in Players:GetPlayers() do
			if not player.Character then
				respawnPlayer(player)
			end
		end
		task.wait(0.4)
		for _, player in Players:GetPlayers() do
			SpawnService.setFrozen(player, false)
			SpawnService.teleportToReadyPad(player, mode)
			-- teleportToReadyPad restores avatar again; ensure no leftover gun weld.
			if player.Character then
				WeaponVisuals.clearFromCharacter(player.Character)
			end
			WeaponService.pushPlayerState(player)
		end
	end)
end

local function returnEveryoneToLobbySpawn()
	LobbyService.applyLobbyLighting()
	pendingMode = nil
	lobbyCountdown = 0
	BuyService.setOpen(false)
	stripGearForLobby()
	task.spawn(function()
		for _, player in Players:GetPlayers() do
			if not player.Character then
				respawnPlayer(player)
			end
		end
		task.wait(0.4)
		for _, player in Players:GetPlayers() do
			SpawnService.setFrozen(player, false)
			SpawnService.teleportToLobby(player)
			if player.Character then
				WeaponVisuals.clearFromCharacter(player.Character)
			end
			WeaponService.pushPlayerState(player)
		end
	end)
end

local function unfreezeRoster()
	for _, player in MatchService.getRoster() do
		SpawnService.setFrozen(player, false)
	end
end

local function prepareBuyPlayers(players: { Player })
	-- Called only from beginBuy, which is itself deferred off Heartbeat.
	for _, player in players do
		if not player.Character then
			respawnPlayer(player)
		end
	end
	task.wait(0.5)
	PlayerStateService.resetAllArmor()
	LoadoutService.clear()
	for _, player in players do
		if player.Character then
			local teamId = TeamService.getTeamId(player)
			if teamId then
				EconomyService.setTeam(player, teamId)
			end
			PlayerStateService.resetArmor(player)
			SpawnService.prepareCharacter(player)
			LoadoutService.grant(player)
			SpawnService.setFrozen(player, true)
			WeaponService.pushPlayerState(player)
			EconomyService.push(player)
		end
	end
end

function RoundService.getState(): string
	return state
end

function RoundService.getTimeRemaining(): number
	return timeRemaining
end

local function enterMatchEnd()
	state = Enums.RoundState.MatchEnd
	ending = false
	CombatService.setRoundLive(false)
	BuyService.setOpen(false)
	CaptureService.stopMonitoring()
	stripGearForLobby()
	timeRemaining = GameConfig.MatchEndSeconds

	local match = MatchService.snapshot()
	local winnerLabel = if lastCommit and lastCommit.matchWinner
		then string.format("Team %s", lastCommit.matchWinner)
		else "—"
	Remotes.get(Net.MatchEnded):FireAllClients({
		winnerTeam = if lastCommit then lastCommit.matchWinner else nil,
		scoreLine = match.scoreLine,
		winsA = match.winsA,
		winsB = match.winsB,
	})
	announce(string.format("MATCH OVER — %s wins (%s)", winnerLabel, match.scoreLine), "warning")
	teleportRosterToLobbyPad(match.lobbyMode :: LobbyService.LobbyMode?)
	broadcastRound()
	print(string.format("[RoundService] Match end: %s (%s)", winnerLabel, match.scoreLine))
end

local function enterIntermission()
	state = Enums.RoundState.Intermission
	ending = false
	CombatService.setRoundLive(false)
	CaptureService.stopMonitoring()
	CaptureService.reset()
	stripGearForLobby(MatchService.getRoster())
	timeRemaining = GameConfig.IntermissionSeconds

	-- Advance round index now so HUD / side mapping show the *upcoming* round.
	if not MatchService.beginNextRound() then
		enterMatchEnd()
		return
	end

	local match = MatchService.snapshot()
	local mode = match.lobbyMode :: LobbyService.LobbyMode?
	local swapText = if MatchService.getRoundIndex() == 1
		then string.format("Round %d — Team A Good · Team B Terrorist", match.roundIndex)
		else string.format(
			"Round %d — sides swapped · A=%s  B=%s · Score %s",
			match.roundIndex,
			match.sideA,
			match.sideB,
			match.scoreLine
		)
	announce(swapText, "info")
	teleportRosterToLobbyPad(mode)
	broadcastRound()
end

local function enterRoundEnd(resolution: ObjectiveService.Resolution)
	if ending then
		return
	end
	ending = true
	state = Enums.RoundState.RoundEnd
	CombatService.setRoundLive(false)
	BuyService.setOpen(false)
	CaptureService.stopMonitoring()
	unfreezeRoster()
	-- Strip guns/skins immediately so they don't linger into lobby pad time.
	stripGearForLobby(MatchService.getRoster())
	timeRemaining = GameConfig.RoundEndSeconds
	lastResolution = resolution

	local commit = MatchService.commitRoundWin(resolution.winnerSide)
	lastCommit = commit
	local match = MatchService.snapshot()

	local deltas = EconomyService.settleRound({
		winnerSide = resolution.winnerSide,
		reason = resolution.reason,
		presidentKiller = nil,
		captureWasActiveOnPresidentDeath = false,
		aliveBodyguardsOnCapture = if resolution.reason
				== Enums.RoundEndReason.CaptureComplete
			then TeamService.getAliveBodyguards()
			else nil,
	})
	local parts = {}
	for player, delta in deltas do
		table.insert(
			parts,
			string.format("%s %s%d", player.Name, if delta >= 0 then "+" else "", delta)
		)
	end
	lastEconomySummary = table.concat(parts, " · ")
	if lastEconomySummary == "" then
		lastEconomySummary = "No cash changes"
	end

	Remotes.get(Net.RoundEnded):FireAllClients({
		winnerSide = resolution.winnerSide,
		reason = resolution.reason,
		message = resolution.message,
		scoreLine = match.scoreLine,
		winningTeam = commit.winningTeam,
		winsA = commit.winsA,
		winsB = commit.winsB,
		matchOver = commit.matchOver,
		economySummary = lastEconomySummary,
	})
	announce(
		string.format(
			"%s · Score %s · %s",
			resolution.message,
			match.scoreLine,
			lastEconomySummary
		),
		"warning"
	)

	-- Matthew: round over → teleport everyone back to lobby (ready pad).
	local mode = match.lobbyMode :: LobbyService.LobbyMode?
	teleportRosterToLobbyPad(mode)
	broadcastRound()
	pushAllPlayerStates()
	print(
		string.format(
			"[RoundService] Round %d ended: %s (%s) score=%s matchOver=%s | %s",
			match.roundIndex,
			resolution.reason,
			resolution.message,
			match.scoreLine,
			tostring(commit.matchOver),
			lastEconomySummary
		)
	)
end

local function beginLive()
	state = Enums.RoundState.Live
	timeRemaining = GameConfig.RoundDurationSeconds
	BuyService.setOpen(false)
	AbilityService.resetAllForRound()
	unfreezeRoster()
	pendingMode = nil
	lobbyCountdown = 0
	CombatService.setRoundLive(true)
	CaptureService.startMonitoring()
	transitioning = false
	broadcastRound()
	pushAllPlayerStates()

	local prez = TeamService.getPresident()
	local match = MatchService.snapshot()
	announce(
		string.format(
			"Round %d LIVE · Score %s · President %s",
			match.roundIndex,
			match.scoreLine,
			if prez then prez.Name else "?"
		),
		"info"
	)
	print(
		string.format(
			"[RoundService] Round %d LIVE (%s) — President=%s, A=%s B=%s score=%s players=%d",
			match.roundIndex,
			tostring(MatchService.getLobbyMode()),
			if prez then prez.Name else "?",
			match.sideA,
			match.sideB,
			match.scoreLine,
			#MatchService.getRoster()
		)
	)
end

local function beginBuy()
	transitioning = true
	ending = false
	lastAnnouncement = nil
	ObjectiveService.resetFlags()
	WeaponService.reset()
	CaptureService.reset()
	CombatService.setRoundLive(false)
	BuyService.setOpen(false)
	AbilityService.interruptAll()

	local players = MatchService.getRoster()
	if #players < GameConfig.MinPlayersToStart then
		MatchService.reset()
		TeamService.reset()
		state = Enums.RoundState.Lobby
		pendingMode = nil
		lobbyCountdown = 0
		timeRemaining = 0
		transitioning = false
		returnEveryoneToLobbySpawn()
		announce("Not enough players — back to lobby", "break")
		broadcastRound()
		return
	end

	TeamService.assignForRound(players)
	local mode = MatchService.getLobbyMode()
	if mode == "Day" or mode == "Night" then
		LobbyService.applyMatchLighting(mode)
	end
	prepareBuyPlayers(players)

	state = Enums.RoundState.Buy
	timeRemaining = GameConfig.BuyPhaseSeconds
	pendingMode = nil
	lobbyCountdown = 0
	BuyService.setOpen(true)
	transitioning = false
	broadcastRound()
	pushAllPlayerStates()

	local match = MatchService.snapshot()
	announce(
		string.format(
			"BUY — Round %d · Score %s · %ds",
			match.roundIndex,
			match.scoreLine,
			GameConfig.BuyPhaseSeconds
		),
		"info"
	)
	print(
		string.format(
			"[RoundService] Round %d BUY (%ds) — players=%d score=%s",
			match.roundIndex,
			GameConfig.BuyPhaseSeconds,
			#players,
			match.scoreLine
		)
	)
end

local function startMatchFromLobby(mode: LobbyService.LobbyMode, players: { Player })
	transitioning = true
	MatchService.beginMatch(players, mode)
	if not MatchService.beginNextRound() then
		MatchService.reset()
		transitioning = false
		return
	end
	pendingMode = nil
	lobbyCountdown = 0
	beginBuy()
end

--[[
	TEMP debug solo playtest — walk-on pad in LobbyService.
	Skips min-player gate, keeps the normal 30s BUY picture UI (no auto-M4A1),
	grants Debug.GrantCash so Matthew can buy freely, suppresses empty-team wins.
	Remove with GameConfig.Debug + LobbyService DEBUG_* builders.
]]
local function startDebugSoloFromLobby(players: { Player })
	transitioning = true
	ending = false
	lastAnnouncement = nil
	ObjectiveService.resetFlags()
	WeaponService.reset()
	CaptureService.reset()
	CombatService.setRoundLive(false)
	BuyService.setOpen(false)
	AbilityService.interruptAll()

	local modeRaw = GameConfig.Debug.LobbyMode
	local mode: LobbyService.LobbyMode = if modeRaw == "Day" then "Day" else "Night"

	local ok, err = pcall(function()
		MatchService.beginMatch(players, mode)
		MatchService.setDebugSolo(true)
		if not MatchService.beginNextRound() then
			MatchService.reset()
			transitioning = false
			return
		end
		pendingMode = nil
		lobbyCountdown = 0

		TeamService.assignDebugSolo(players, GameConfig.Debug.Side)
		LobbyService.applyMatchLighting(mode)

		local grantCash = GameConfig.Debug.GrantCash
		for _, player in players do
			local teamId = TeamService.getTeamId(player)
			if teamId then
				EconomyService.setTeam(player, teamId)
			end
			EconomyService.setCash(player, grantCash)
		end

		-- Same BUY path as live matches: freeze at spawn, default pistol, 30s menu.
		prepareBuyPlayers(players)

		state = Enums.RoundState.Buy
		timeRemaining = GameConfig.BuyPhaseSeconds
		BuyService.setOpen(true)
		transitioning = false
		broadcastRound()
		pushAllPlayerStates()

		announce(
			string.format(
				"DEBUG SOLO BUY — $%d · pick a gun (%ds) · Day/Night pads still for real matches",
				grantCash,
				GameConfig.BuyPhaseSeconds
			),
			"warning"
		)
		print(
			string.format(
				"[RoundService] DEBUG solo BUY (%ds) cash=%d players=%d",
				GameConfig.BuyPhaseSeconds,
				grantCash,
				#players
			)
		)
	end)
	if not ok then
		warn("[RoundService] DEBUG solo start failed: " .. tostring(err))
		MatchService.reset()
		TeamService.reset()
		state = Enums.RoundState.Lobby
		pendingMode = nil
		lobbyCountdown = 0
		timeRemaining = 0
		transitioning = false
		CombatService.setRoundLive(false)
		BuyService.setOpen(false)
		broadcastRound()
	end
end

local function pickArmedZone(): (LobbyService.LobbyMode?, { Player })
	local minN = GameConfig.MinPlayersToStart
	local nightPlayers = LobbyService.getPlayersInZone("Night")
	local dayPlayers = LobbyService.getPlayersInZone("Day")
	local nightReady = #nightPlayers >= minN
	local dayReady = #dayPlayers >= minN

	-- Prefer the pad that already owns the countdown; otherwise the fuller pad.
	if pendingMode == "Night" and nightReady then
		return "Night", nightPlayers
	end
	if pendingMode == "Day" and dayReady then
		return "Day", dayPlayers
	end
	if nightReady and dayReady then
		if #nightPlayers >= #dayPlayers then
			return "Night", nightPlayers
		end
		return "Day", dayPlayers
	end
	if nightReady then
		return "Night", nightPlayers
	end
	if dayReady then
		return "Day", dayPlayers
	end
	return nil, {}
end

local function isMatchPlayState(): boolean
	return state == Enums.RoundState.Live or state == Enums.RoundState.Capture
end

function RoundService.step(dt: number)
	if transitioning then
		broadcastRoundThrottled(dt)
		return
	end

	if state == Enums.RoundState.Lobby then
		-- Ignore pad arming while a match is somehow still marked active.
		if MatchService.isActive() then
			MatchService.reset()
		end

		-- TEMP: magenta DEBUG pad — solo-friendly immediate LIVE (does not touch Day/Night).
		if GameConfig.Debug.SoloPlaytestPadEnabled then
			local debugPlayers = LobbyService.getPlayersInDebugZone()
			if #debugPlayers >= 1 then
				pendingMode = nil
				lobbyCountdown = 0
				timeRemaining = 0
				transitioning = true
				task.spawn(function()
					startDebugSoloFromLobby(debugPlayers)
				end)
				return
			end
		end

		local mode, _ = pickArmedZone()
		if not mode then
			pendingMode = nil
			lobbyCountdown = 0
			timeRemaining = 0
			broadcastRoundThrottled(dt)
			return
		end

		if pendingMode ~= mode then
			pendingMode = mode
			lobbyCountdown = GameConfig.LobbyCountdownSeconds
		end

		lobbyCountdown -= dt
		timeRemaining = lobbyCountdown
		broadcastRoundThrottled(dt)

		if lobbyCountdown <= 0 then
			local roster = LobbyService.takeMatchRoster(mode)
			if #roster < GameConfig.MinPlayersToStart then
				pendingMode = nil
				lobbyCountdown = 0
				timeRemaining = 0
				broadcastRound()
				return
			end
			pendingMode = nil
			lobbyCountdown = 0
			transitioning = true
			task.spawn(function()
				startMatchFromLobby(mode, roster)
			end)
		end
		return
	end

	if state == Enums.RoundState.Buy then
		timeRemaining -= dt
		broadcastRoundThrottled(dt)
		if timeRemaining <= 0 then
			beginLive()
		end
		return
	end

	if state == Enums.RoundState.RoundEnd then
		timeRemaining -= dt
		broadcastRoundThrottled(dt)
		if timeRemaining <= 0 then
			if lastCommit and lastCommit.matchOver then
				enterMatchEnd()
			else
				enterIntermission()
			end
		end
		return
	end

	if state == Enums.RoundState.Intermission then
		timeRemaining -= dt
		broadcastRoundThrottled(dt)
		if timeRemaining <= 0 then
			transitioning = true
			task.spawn(beginBuy)
		end
		return
	end

	if state == Enums.RoundState.MatchEnd then
		timeRemaining -= dt
		broadcastRoundThrottled(dt)
		if timeRemaining <= 0 then
			MatchService.reset()
			TeamService.reset()
			lastResolution = nil
			lastCommit = nil
			lastAnnouncement = nil
			lastEconomySummary = ""
			ending = false
			BuyService.setOpen(false)
			state = Enums.RoundState.Lobby
			timeRemaining = 0
			returnEveryoneToLobbySpawn()
			announce("Scores cleared — stand in a ready pad to queue", "info")
			broadcastRound()
		end
		return
	end

	-- LIVE or CAPTURE: 300s clock always ticks
	if isMatchPlayState() then
		timeRemaining -= dt

		if CaptureService.isActive() then
			state = Enums.RoundState.Capture
		elseif state == Enums.RoundState.Capture and not CaptureService.isActive() then
			state = Enums.RoundState.Live
		end

		local resolution = ObjectiveService.evaluate(timeRemaining)
		if resolution then
			enterRoundEnd(resolution)
			return
		end

		broadcastRoundThrottled(dt)
	end
end

function RoundService.onPlayerDied(victim: Player, killer: Player?)
	if not isMatchPlayState() then
		return
	end
	WeaponService.pushPlayerState(victim)

	if TeamService.getRole(victim) == Enums.Role.President then
		ObjectiveService.noticePresidentDeath(killer)
	end
	local resolution = ObjectiveService.evaluate(timeRemaining)
	if resolution then
		enterRoundEnd(resolution)
	end
end

function RoundService.onPlayerRemoving(player: Player)
	if not isMatchPlayState() then
		TeamService.clearPlayer(player)
		return
	end

	if TeamService.getRole(player) == Enums.Role.President then
		ObjectiveService.noticePresidentDisconnect()
		local resolution = ObjectiveService.evaluate(timeRemaining)
		if resolution then
			enterRoundEnd(resolution)
		end
	else
		TeamService.clearPlayer(player)
		local resolution = ObjectiveService.evaluate(timeRemaining)
		if resolution then
			enterRoundEnd(resolution)
		end
	end
end

local function shouldParkInLobby(): boolean
	return state == Enums.RoundState.Lobby
		or state == Enums.RoundState.RoundEnd
		or state == Enums.RoundState.Intermission
		or state == Enums.RoundState.MatchEnd
end

function RoundService.init()
	assert(
		MapService.getFolder(),
		"[RoundService] VIPMap missing — Bootstrap must build the map first"
	)
	assert(
		LobbyService.getFolder(),
		"[RoundService] VIPLobby missing — Bootstrap must build the lobby first"
	)
	CaptureService.setRoundRemainingGetter(function()
		return timeRemaining
	end)
	CaptureService.setCompletedCallback(function()
		if isMatchPlayState() then
			local resolution = ObjectiveService.evaluate(timeRemaining)
			if resolution then
				enterRoundEnd(resolution)
			end
		end
	end)
	CombatService.setDeathCallback(function(victim, killer)
		RoundService.onPlayerDied(victim, killer)
	end)
	CaptureService.init()
	CombatService.init()
	BuyService.init()
	WeaponService.init()
	WeaponService.setBuyOpenGetter(function()
		return BuyService.isOpen()
	end)
	BuyService.setPurchaseCallback(function(player)
		WeaponService.pushPlayerState(player)
		EconomyService.push(player)
	end)
	WeaponService.setAmmoChangedCallback(function(player)
		WeaponService.pushPlayerState(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if shouldParkInLobby() then
				task.defer(function()
					local mode = MatchService.getLobbyMode()
					if mode == "Day" or mode == "Night" then
						SpawnService.teleportToReadyPad(player, mode)
					else
						SpawnService.teleportToLobby(player)
					end
				end)
			end
		end)
		EconomyService.push(player)
		broadcastRound()
	end)

	Players.PlayerRemoving:Connect(function(player)
		RoundService.onPlayerRemoving(player)
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			if shouldParkInLobby() then
				task.defer(function()
					local mode = MatchService.getLobbyMode()
					if mode == "Day" or mode == "Night" then
						SpawnService.teleportToReadyPad(player, mode)
					else
						SpawnService.teleportToLobby(player)
					end
				end)
			end
		end)
		if player.Character then
			SpawnService.teleportToLobby(player)
		end
	end

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		RoundService.step(dt)
	end)

	broadcastRound()
	print(
		string.format(
			"[RoundService] %s ready — bo%d first to %d, buy=%ds, Day/Night pads (min=%d max=%d).",
			GameConfig.GameName,
			GameConfig.MaxRoundsInMatch,
			GameConfig.MatchWinsNeeded,
			GameConfig.BuyPhaseSeconds,
			GameConfig.MinPlayersToStart,
			GameConfig.MaxPlayersPerLobbyZone
		)
	)
end

return RoundService
