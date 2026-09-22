--!strict
-- Owns the round state machine and the 300s LIVE clock. Nothing may pause or extend that clock.
-- Lobby start is gated by Day/Night ready pads on the elevated VIPLobby deck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)

local Remotes = require(script.Parent.Remotes)
local MapService = require(script.Parent.MapService)
local LobbyService = require(script.Parent.LobbyService)
local TeamService = require(script.Parent.TeamService)
local SpawnService = require(script.Parent.SpawnService)
local LoadoutService = require(script.Parent.LoadoutService)
local WeaponService = require(script.Parent.WeaponService)
local CombatService = require(script.Parent.CombatService)
local CaptureService = require(script.Parent.CaptureService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local RoundService = {}

local state = Enums.RoundState.Lobby
local roundNumber = 0
local timeRemaining = 0
local lobbyCountdown = 0
local ending = false
local heartbeatConn: RBXScriptConnection? = nil
local broadcastAccum = 0
local BROADCAST_INTERVAL = 0.25

-- Which ready pad armed the current lobby countdown (nil = waiting for a zone).
local pendingMode: LobbyService.LobbyMode? = nil
-- Roster captured when LIVE begins (players standing in the armed zone, capped at 10).
local matchRoster: { Player } = {}

local function broadcastRound()
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
			banner = string.format(
				"Stand in DAY or NIGHT ready pad · Night %d  Day %d  (need %d–%d)",
				nightN,
				dayN,
				minN,
				maxN
			)
		end
	end
	Remotes.get(Net.RoundState):FireAllClients({
		state = state,
		timeRemaining = math.max(timeRemaining, 0),
		roundNumber = roundNumber,
		objectiveBanner = banner,
		lobbyMode = pendingMode,
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
	for _, player in Players:GetPlayers() do
		WeaponService.pushPlayerState(player)
	end
end

local function respawnPlayer(player: Player)
	player:LoadCharacter()
end

local function returnEveryoneToLobby()
	LobbyService.applyLobbyLighting()
	pendingMode = nil
	lobbyCountdown = 0
	table.clear(matchRoster)
	for _, player in Players:GetPlayers() do
		if not player.Character then
			respawnPlayer(player)
		end
	end
	task.wait(0.4)
	for _, player in Players:GetPlayers() do
		SpawnService.teleportToLobby(player)
	end
end

local function prepareMatchPlayers(players: { Player })
	for _, player in players do
		if not player.Character then
			respawnPlayer(player)
		end
	end
	task.wait(0.5)
	for _, player in players do
		if player.Character then
			SpawnService.prepareCharacter(player)
			LoadoutService.grant(player)
			WeaponService.pushPlayerState(player)
		end
	end
end

function RoundService.getState(): string
	return state
end

function RoundService.getTimeRemaining(): number
	return timeRemaining
end

local function enterRoundEnd(resolution: ObjectiveService.Resolution)
	if ending then
		return
	end
	ending = true
	state = Enums.RoundState.RoundEnd
	CombatService.setRoundLive(false)
	CaptureService.stopMonitoring()
	timeRemaining = GameConfig.RoundEndSeconds

	Remotes.get(Net.RoundEnded):FireAllClients({
		winnerSide = resolution.winnerSide,
		reason = resolution.reason,
		message = resolution.message,
	})
	broadcastRound()
	print(
		string.format(
			"[RoundService] Round %d ended: %s (%s)",
			roundNumber,
			resolution.reason,
			resolution.message
		)
	)
end

local function beginLive(mode: LobbyService.LobbyMode, players: { Player })
	ending = false
	roundNumber += 1
	ObjectiveService.resetFlags()
	WeaponService.reset()
	LoadoutService.clear()
	CaptureService.reset()

	matchRoster = table.clone(players)
	TeamService.assignForRound(players)
	LobbyService.applyMatchLighting(mode)
	prepareMatchPlayers(players)

	state = Enums.RoundState.Live
	timeRemaining = GameConfig.RoundDurationSeconds
	pendingMode = nil
	lobbyCountdown = 0
	CombatService.setRoundLive(true)
	CaptureService.startMonitoring()
	broadcastRound()
	pushAllPlayerStates()

	local prez = TeamService.getPresident()
	print(
		string.format(
			"[RoundService] Round %d LIVE (%s) — President=%s, players=%d",
			roundNumber,
			mode,
			if prez then prez.Name else "?",
			#players
		)
	)
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

function RoundService.step(dt: number)
	if state == Enums.RoundState.Lobby then
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
			-- Re-sample at go-time so leavers aren't teleported; cap at 10.
			local roster = LobbyService.takeMatchRoster(mode)
			if #roster < GameConfig.MinPlayersToStart then
				pendingMode = nil
				lobbyCountdown = 0
				timeRemaining = 0
				broadcastRound()
				return
			end
			beginLive(mode, roster)
		end
		return
	end

	if state == Enums.RoundState.RoundEnd then
		timeRemaining -= dt
		broadcastRoundThrottled(dt)
		if timeRemaining <= 0 then
			-- Slice 0: loop forever, no match score / side swap.
			state = Enums.RoundState.Lobby
			ending = false
			CombatService.setRoundLive(false)
			CaptureService.reset()
			TeamService.reset()
			returnEveryoneToLobby()
			broadcastRound()
		end
		return
	end

	-- LIVE or CAPTURE: 300s clock always ticks
	if state == Enums.RoundState.Live or state == Enums.RoundState.Capture then
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
	if state ~= Enums.RoundState.Live and state ~= Enums.RoundState.Capture then
		return
	end
	WeaponService.pushPlayerState(victim)

	if TeamService.getRole(victim) == Enums.Role.President then
		ObjectiveService.noticePresidentDeath(killer)
		local resolution = ObjectiveService.evaluate(timeRemaining)
		if resolution then
			enterRoundEnd(resolution)
		end
	else
		local resolution = ObjectiveService.evaluate(timeRemaining)
		if resolution then
			enterRoundEnd(resolution)
		end
	end
end

function RoundService.onPlayerRemoving(player: Player)
	if state ~= Enums.RoundState.Live and state ~= Enums.RoundState.Capture then
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

function RoundService.init()
	-- Greybox + MapValidator + Lobby run in Bootstrap.server before this init.
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
		if state == Enums.RoundState.Live or state == Enums.RoundState.Capture then
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
	WeaponService.setAmmoChangedCallback(function(player)
		WeaponService.pushPlayerState(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if state == Enums.RoundState.Lobby or state == Enums.RoundState.RoundEnd then
				task.defer(function()
					SpawnService.teleportToLobby(player)
				end)
				return
			end
			-- Late join mid-round: spectator only (slice 0 — no mid-round join to teams).
		end)
		broadcastRound()
	end)

	Players.PlayerRemoving:Connect(function(player)
		RoundService.onPlayerRemoving(player)
	end)

	-- Already-present players (Studio soft restart) land on the lobby deck.
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			if state == Enums.RoundState.Lobby or state == Enums.RoundState.RoundEnd then
				task.defer(function()
					SpawnService.teleportToLobby(player)
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
			"[RoundService] %s lobby ready (Day/Night pads, min=%d max=%d per zone).",
			GameConfig.GameName,
			GameConfig.MinPlayersToStart,
			GameConfig.MaxPlayersPerLobbyZone
		)
	)
end

return RoundService
