--!strict
-- Owns the round state machine and the 300s LIVE clock. Nothing may pause or extend that clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)

local Remotes = require(script.Parent.Remotes)
local MapService = require(script.Parent.MapService)
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

local function broadcastRound()
	local banner = ObjectiveService.objectiveBanner(timeRemaining, state)
	Remotes.get(Net.RoundState):FireAllClients({
		state = state,
		timeRemaining = math.max(timeRemaining, 0),
		roundNumber = roundNumber,
		objectiveBanner = banner,
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

local function prepareAllPlayers()
	for _, player in Players:GetPlayers() do
		if not player.Character then
			respawnPlayer(player)
		end
	end
	-- Wait briefly for characters
	task.wait(0.5)
	for _, player in Players:GetPlayers() do
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

local function beginLive()
	ending = false
	roundNumber += 1
	ObjectiveService.resetFlags()
	WeaponService.reset()
	LoadoutService.clear()
	CaptureService.reset()

	local players = Players:GetPlayers()
	TeamService.assignForRound(players)
	prepareAllPlayers()

	state = Enums.RoundState.Live
	timeRemaining = GameConfig.RoundDurationSeconds
	CombatService.setRoundLive(true)
	CaptureService.startMonitoring()
	broadcastRound()
	pushAllPlayerStates()

	local prez = TeamService.getPresident()
	print(
		string.format(
			"[RoundService] Round %d LIVE — President=%s, players=%d",
			roundNumber,
			if prez then prez.Name else "?",
			#players
		)
	)
end

local function tryStartFromLobby()
	local count = #Players:GetPlayers()
	if count < GameConfig.MinPlayersToStart then
		lobbyCountdown = 0
		timeRemaining = 0
		state = Enums.RoundState.Lobby
		broadcastRound()
		return
	end

	if lobbyCountdown <= 0 then
		lobbyCountdown = GameConfig.LobbyCountdownSeconds
	end
end

function RoundService.step(dt: number)
	if state == Enums.RoundState.Lobby then
		local count = #Players:GetPlayers()
		if count < GameConfig.MinPlayersToStart then
			lobbyCountdown = 0
			timeRemaining = 0
			broadcastRoundThrottled(dt)
			return
		end

		if lobbyCountdown <= 0 then
			lobbyCountdown = GameConfig.LobbyCountdownSeconds
		end

		lobbyCountdown -= dt
		timeRemaining = lobbyCountdown
		broadcastRoundThrottled(dt)

		if lobbyCountdown <= 0 then
			beginLive()
		end
		return
	end

	if state == Enums.RoundState.RoundEnd then
		timeRemaining -= dt
		broadcastRoundThrottled(dt)
		if timeRemaining <= 0 then
			-- Slice 0: loop forever, no match score / side swap.
			state = Enums.RoundState.Lobby
			lobbyCountdown = GameConfig.LobbyCountdownSeconds
			ending = false
			CombatService.setRoundLive(false)
			CaptureService.reset()
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
	-- Greybox + MapValidator run in Bootstrap.server before this init so the
	-- map is visible even if remotes / round wiring fail later.
	assert(
		MapService.getFolder(),
		"[RoundService] VIPMap missing — Bootstrap must build the map first"
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
			if state == Enums.RoundState.Live or state == Enums.RoundState.Capture then
				-- Late join mid-round: spectator only (slice 0 — no mid-round join to teams).
				return
			end
		end)
		tryStartFromLobby()
		broadcastRound()
	end)

	Players.PlayerRemoving:Connect(function(player)
		RoundService.onPlayerRemoving(player)
	end)

	if #Players:GetPlayers() > 0 then
		tryStartFromLobby()
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
			"[RoundService] %s slice 0 ready (min players=%d).",
			GameConfig.GameName,
			GameConfig.MinPlayersToStart
		)
	)
end

return RoundService
