--!strict
--[[
	Elevated VIP briefing lobby — compact deck south/above the city so the
	greybox stays visible below and in the distance.

	Two ready zones on the same pad:
	  Night (west) — match keeps evening/dark city + streetlights
	  Day   (east) — match switches Lighting to bright daytime

	Additive only: does not touch VIPMap anchors or MapValidator ribbons.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapService = require(script.Parent.MapService)

local LobbyService = {}

export type LobbyMode = "Night" | "Day"

local lobbyFolder: Folder? = nil
local nightZone: BasePart? = nil
local dayZone: BasePart? = nil
local spawnPad: BasePart? = nil

local COLOR = {
	deck = Color3.fromRGB(72, 74, 80),
	deckAccent = Color3.fromRGB(55, 58, 64),
	rail = Color3.fromRGB(120, 122, 128),
	metal = Color3.fromRGB(48, 50, 56),
	console = Color3.fromRGB(36, 40, 48),
	glass = Color3.fromRGB(90, 140, 180),
	nightFloor = Color3.fromRGB(40, 48, 78),
	nightGlow = Color3.fromRGB(90, 130, 220),
	dayFloor = Color3.fromRGB(210, 185, 95),
	dayGlow = Color3.fromRGB(255, 220, 120),
	sign = Color3.fromRGB(230, 232, 238),
	warn = Color3.fromRGB(200, 160, 60),
}

type LightingPreset = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ColorShift_Top: Color3,
	ColorShift_Bottom: Color3,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
}

-- Night = current city evening mood (must match MapService.configureCityAtmosphere).
local NIGHT_LIGHTING: LightingPreset = {
	ClockTime = 20.25,
	Brightness = 1.1,
	Ambient = Color3.fromRGB(42, 46, 58),
	OutdoorAmbient = Color3.fromRGB(58, 62, 72),
	ColorShift_Top = Color3.fromRGB(40, 50, 80),
	ColorShift_Bottom = Color3.fromRGB(20, 22, 28),
	EnvironmentDiffuseScale = 0.35,
	EnvironmentSpecularScale = 0.25,
}

local DAY_LIGHTING: LightingPreset = {
	ClockTime = 14.0,
	Brightness = 2.4,
	Ambient = Color3.fromRGB(140, 140, 145),
	OutdoorAmbient = Color3.fromRGB(170, 170, 175),
	ColorShift_Top = Color3.fromRGB(255, 250, 240),
	ColorShift_Bottom = Color3.fromRGB(200, 200, 210),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 0.85,
}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = if canCollide == nil then true else canCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.Concrete
	p.Color = color
	p.Parent = parent
	return p
end

local function billboard(parent: BasePart, text: string, offsetY: number?, textColor: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(240, 48)
	gui.StudsOffset = Vector3.new(0, offsetY or 6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = textColor or COLOR.sign
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.Parent = gui
end

local function applyLightingTable(preset: LightingPreset)
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.ColorShift_Top = preset.ColorShift_Top
	Lighting.ColorShift_Bottom = preset.ColorShift_Bottom
	Lighting.EnvironmentDiffuseScale = preset.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = preset.EnvironmentSpecularScale
	Lighting.GlobalShadows = true
end

local function deckTopY(): number
	local cfg = GameConfig.Lobby
	return cfg.Center.Y + cfg.DeckThickness * 0.5
end

local function zoneWorldCFrame(localOffset: Vector3): CFrame
	local cfg = GameConfig.Lobby
	local top = deckTopY()
	return CFrame.new(
		cfg.Center.X + localOffset.X,
		top + cfg.ReadyZoneSize.Y * 0.5,
		cfg.Center.Z + localOffset.Z
	)
end

local function buildReadyZone(
	parent: Folder,
	mode: LobbyMode,
	localOffset: Vector3,
	floorColor: Color3,
	glowColor: Color3
): BasePart
	local cfg = GameConfig.Lobby
	local top = deckTopY()
	local floor = part(
		parent,
		mode .. "ReadyFloor",
		Vector3.new(cfg.ReadyZoneSize.X, 0.4, cfg.ReadyZoneSize.Z),
		CFrame.new(cfg.Center.X + localOffset.X, top + 0.25, cfg.Center.Z + localOffset.Z),
		floorColor,
		Enum.Material.Metal
	)
	floor.Material = Enum.Material.Neon
	floor.Color = floorColor

	-- Soft volume (non-colliding) used for standing detection.
	local volume = part(
		parent,
		mode .. "ReadyZone",
		cfg.ReadyZoneSize,
		zoneWorldCFrame(localOffset),
		glowColor,
		Enum.Material.ForceField,
		false
	)
	volume.Transparency = 0.75
	volume.CanQuery = true
	volume:SetAttribute("LobbyMode", mode)
	CollectionService:AddTag(volume, "LobbyReadyZone")

	local pillar = part(
		parent,
		mode .. "SignPost",
		Vector3.new(1.2, 10, 1.2),
		CFrame.new(cfg.Center.X + localOffset.X, top + 5, cfg.Center.Z + localOffset.Z - 12),
		COLOR.metal,
		Enum.Material.Metal
	)
	local sign = part(
		parent,
		mode .. "Sign",
		Vector3.new(14, 4, 0.6),
		CFrame.new(cfg.Center.X + localOffset.X, top + 11, cfg.Center.Z + localOffset.Z - 12),
		COLOR.console,
		Enum.Material.SmoothPlastic
	)
	local caption = if mode == "Night"
		then "NIGHT OPS  ·  evening city"
		else "DAY OPS  ·  daylight city"
	billboard(sign, caption, 3, glowColor)
	billboard(floor, string.upper(mode) .. " READY", 5, glowColor)

	-- Briefing light over each pad
	local lamp = part(
		parent,
		mode .. "Overhead",
		Vector3.new(4, 0.6, 4),
		CFrame.new(cfg.Center.X + localOffset.X, top + 14, cfg.Center.Z + localOffset.Z),
		glowColor,
		Enum.Material.Neon,
		false
	)
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = 28
	light.Brightness = if mode == "Night" then 1.4 else 2.2
	light.Color = glowColor
	light.Shadows = false
	light.Parent = lamp

	-- Corner chevrons so the pad reads as a briefing square
	for _, corner in
		{
			Vector3.new(-1, 0, -1),
			Vector3.new(1, 0, -1),
			Vector3.new(-1, 0, 1),
			Vector3.new(1, 0, 1),
		}
	do
		local hx = cfg.ReadyZoneSize.X * 0.5 - 1.5
		local hz = cfg.ReadyZoneSize.Z * 0.5 - 1.5
		part(
			parent,
			mode .. "Chevron",
			Vector3.new(3, 0.5, 3),
			CFrame.new(
				cfg.Center.X + localOffset.X + corner.X * hx,
				top + 0.4,
				cfg.Center.Z + localOffset.Z + corner.Z * hz
			),
			glowColor,
			Enum.Material.Neon,
			false
		).CanCollide =
			false
	end

	pillar.Parent = parent
	return volume
end

local function buildRails(parent: Folder)
	local cfg = GameConfig.Lobby
	local top = deckTopY()
	local sx, sz = cfg.PlatformSize.X, cfg.PlatformSize.Z
	local h = cfg.RailHeight
	local t = 0.6
	local cy = top + h * 0.5
	part(
		parent,
		"RailN",
		Vector3.new(sx, h, t),
		CFrame.new(cfg.Center.X, cy, cfg.Center.Z - sz * 0.5),
		COLOR.rail,
		Enum.Material.Metal
	)
	part(
		parent,
		"RailS",
		Vector3.new(sx, h, t),
		CFrame.new(cfg.Center.X, cy, cfg.Center.Z + sz * 0.5),
		COLOR.rail,
		Enum.Material.Metal
	)
	part(
		parent,
		"RailW",
		Vector3.new(t, h, sz),
		CFrame.new(cfg.Center.X - sx * 0.5, cy, cfg.Center.Z),
		COLOR.rail,
		Enum.Material.Metal
	)
	part(
		parent,
		"RailE",
		Vector3.new(t, h, sz),
		CFrame.new(cfg.Center.X + sx * 0.5, cy, cfg.Center.Z),
		COLOR.rail,
		Enum.Material.Metal
	)
end

local function buildProps(parent: Folder)
	local cfg = GameConfig.Lobby
	local top = deckTopY()
	-- Central briefing console (between day/night pads)
	local console = part(
		parent,
		"BriefingConsole",
		Vector3.new(10, 3, 6),
		CFrame.new(cfg.Center.X, top + 1.5, cfg.Center.Z - 2),
		COLOR.console,
		Enum.Material.Metal
	)
	billboard(console, "VIP  ·  BRIEFING DECK", 5, COLOR.warn)

	part(
		parent,
		"MapHolo",
		Vector3.new(8, 0.2, 5),
		CFrame.new(cfg.Center.X, top + 3.4, cfg.Center.Z - 2),
		COLOR.glass,
		Enum.Material.Neon,
		false
	).Transparency =
		0.35

	-- Side crates / radio props (greybox)
	for i, offset in
		{
			Vector3.new(-34, 0, 8),
			Vector3.new(34, 0, 8),
			Vector3.new(-34, 0, -10),
			Vector3.new(34, 0, -10),
		}
	do
		part(
			parent,
			"Crate" .. i,
			Vector3.new(4, 3, 4),
			CFrame.new(cfg.Center.X + offset.X, top + 1.5, cfg.Center.Z + offset.Z),
			COLOR.metal,
			Enum.Material.Wood
		)
	end

	-- Edge floodlights looking toward the city (north)
	for i, xOff in { -28, 0, 28 } do
		local pole = part(
			parent,
			"FloodPole" .. i,
			Vector3.new(1, 12, 1),
			CFrame.new(cfg.Center.X + xOff, top + 6, cfg.Center.Z - cfg.PlatformSize.Z * 0.5 + 2),
			COLOR.metal,
			Enum.Material.Metal
		)
		local head = part(
			parent,
			"FloodHead" .. i,
			Vector3.new(3, 1, 2),
			pole.CFrame * CFrame.new(0, 6, -1),
			COLOR.warn,
			Enum.Material.Neon,
			false
		)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 55
		spot.Range = 90
		spot.Brightness = 2
		spot.Color = Color3.fromRGB(255, 230, 190)
		spot.Shadows = false
		spot.Parent = head
	end
end

function LobbyService.applyLobbyLighting()
	-- Lobby deck uses the evening mood (city visible below with streetlights).
	applyLightingTable(NIGHT_LIGHTING)
end

function LobbyService.applyMatchLighting(mode: LobbyMode)
	if mode == "Day" then
		applyLightingTable(DAY_LIGHTING)
	else
		applyLightingTable(NIGHT_LIGHTING)
	end
end

function LobbyService.getFolder(): Folder?
	return lobbyFolder or Workspace:FindFirstChild("VIPLobby") :: Folder?
end

function LobbyService.getReadyZone(mode: LobbyMode): BasePart?
	if mode == "Day" then
		return dayZone
	end
	return nightZone
end

function LobbyService.getSpawnCFrame(): CFrame
	local cfg = GameConfig.Lobby
	local top = deckTopY()
	local o = cfg.SpawnLocalOffset
	return CFrame.new(cfg.Center.X + o.X, top + 4, cfg.Center.Z + o.Z)
end

function LobbyService.pointInZone(point: Vector3, mode: LobbyMode): boolean
	local zone = LobbyService.getReadyZone(mode)
	if not zone then
		return false
	end
	return MapService.pointInPart(point, zone)
end

function LobbyService.getPlayersInZone(mode: LobbyMode): { Player }
	local zone = LobbyService.getReadyZone(mode)
	if not zone then
		return {}
	end
	local found: { Player } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and MapService.pointInPart(root.Position, zone) then
			table.insert(found, player)
		end
	end
	-- Stable order so team seats and the 10-player cap are deterministic.
	table.sort(found, function(a, b)
		return a.UserId < b.UserId
	end)
	return found
end

function LobbyService.takeMatchRoster(mode: LobbyMode): { Player }
	local inZone = LobbyService.getPlayersInZone(mode)
	local cap = GameConfig.MaxPlayersPerLobbyZone
	if #inZone <= cap then
		return inZone
	end
	local roster = {}
	for i = 1, cap do
		roster[i] = inZone[i]
	end
	return roster
end

function LobbyService.build()
	local existing = Workspace:FindFirstChild("VIPLobby")
	if existing then
		existing:Destroy()
	end

	local cfg = GameConfig.Lobby
	local folder = Instance.new("Folder")
	folder.Name = "VIPLobby"
	folder.Parent = Workspace
	lobbyFolder = folder

	part(
		folder,
		"Deck",
		cfg.PlatformSize,
		CFrame.new(cfg.Center),
		COLOR.deck,
		Enum.Material.Concrete
	)
	-- Subtle center stripe so Day/Night halves read
	part(
		folder,
		"DeckStripe",
		Vector3.new(2, cfg.DeckThickness + 0.1, cfg.PlatformSize.Z - 4),
		CFrame.new(cfg.Center),
		COLOR.deckAccent,
		Enum.Material.Metal,
		false
	).CanCollide =
		false

	buildRails(folder)
	nightZone =
		buildReadyZone(folder, "Night", cfg.NightZoneLocalOffset, COLOR.nightFloor, COLOR.nightGlow)
	dayZone = buildReadyZone(folder, "Day", cfg.DayZoneLocalOffset, COLOR.dayFloor, COLOR.dayGlow)
	buildProps(folder)

	-- Arrival pad (south) — default SpawnLocation sits here.
	local spawnOffset = cfg.SpawnLocalOffset
	spawnPad = part(
		folder,
		"LobbySpawnPad",
		Vector3.new(14, 0.5, 10),
		CFrame.new(cfg.Center.X + spawnOffset.X, deckTopY() + 0.3, cfg.Center.Z + spawnOffset.Z),
		COLOR.deckAccent,
		Enum.Material.Metal
	)
	billboard(spawnPad, "LOBBY SPAWN", 4, COLOR.sign)

	local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn and defaultSpawn:IsA("SpawnLocation") then
		defaultSpawn.Enabled = true
		defaultSpawn.Transparency = 1
		defaultSpawn.CanCollide = false
		defaultSpawn.Neutral = true
		defaultSpawn.Duration = 0
		defaultSpawn.Size = Vector3.new(12, 1, 12)
		defaultSpawn.CFrame = LobbyService.getSpawnCFrame() * CFrame.new(0, -3.5, 0)
	end

	LobbyService.applyLobbyLighting()

	print(
		string.format(
			"[LobbyService] VIP briefing deck at %s (Night west / Day east ready pads).",
			tostring(cfg.Center)
		)
	)
	return folder
end

return LobbyService
