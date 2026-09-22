--!strict
--[[
	Builds the metric-correct urban greybox from MapMetrics.

	City-first hierarchy (Matthew):
	  1. Lay a readable orthogonal ROAD GRID first (asphalt faces between parcels)
	  2. Fill BLOCKS between roads with varied-height skyline (low mid → towers)
	  3. Cut a few secondary ALLEYS as costly bypasses
	  4. Place spawns on road centerlines / intersections
	  5. One intentional LOS blocker south of Market (terror) spawn
	Then perimeter walls + discrete ladder snipes on elevated outliers + one
	corner landmark perch. No new game mechanics.

	RoadNetwork visuals: per-block asphalt + curb lips + dashed center marks
	on open street only. Metric arterials stay as walkable reservations
	(contest timing) without stamping diagonal mark/curb ribbons through towers.

	Metric ribbons in MapMetrics stay the distance source of truth; primary
	path corridors remain reserved so contest timing holds on the grid.

	Gameplay wiring (unchanged contracts):
	- Workspace.VIPMap / SafeHouseA|B / CaptureVolume (+ SafeHouseId attribute)
	- MapService.getCaptureVolume / getSpawnCFrame / pointInPart

	Safe-house identity (site-local only — do not move MapAnchors):
	- Consulate (A): open diplomatic plaza — planters, bollards, sparse cover
	- Precinct (B): tighter police courtyard — jersey barriers, denser cover

	City lighting (greybox fixtures only — no new mechanics):
	- Streetlights on road-grid junction curbs (PointLight, Shadows off)
	- Site / entrance sconces at Consulate + Precinct
	- Spawn pool illumination at Motorcade + Market
	Does not move anchors, LOS blocker, perimeter, or sniper ladders.

	Also: MapAnchor tags, CaptureBoundary markers, costly choke bypasses,
	tall city perimeter walls, discrete TrussPart ladder climbs onto selected
	roofs (no rooftop highway), overhead arcade, no lethal VIP falls.
	RoadNetwork / spawn LOS owned elsewhere — do not reshape those here.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local MapMetrics = require(ReplicatedStorage.Shared.MapMetrics)

local MapService = {}

local mapFolder: Folder? = nil

local COLOR = {
	asphalt = Color3.fromRGB(55, 58, 62),
	concrete = Color3.fromRGB(95, 95, 100),
	brick = Color3.fromRGB(110, 100, 95),
	metal = Color3.fromRGB(70, 72, 78),
	wood = Color3.fromRGB(140, 110, 70),
	cover = Color3.fromRGB(85, 85, 90),
	wall = Color3.fromRGB(70, 70, 75),
	facade = Color3.fromRGB(58, 62, 70),
	facadeAccent = Color3.fromRGB(48, 52, 58),
	window = Color3.fromRGB(100, 150, 180),
	marking = Color3.fromRGB(210, 200, 140),
	curb = Color3.fromRGB(120, 120, 118),
	houseA = Color3.fromRGB(40, 90, 140),
	houseB = Color3.fromRGB(140, 70, 40),
	boundary = Color3.fromRGB(255, 220, 60),
	capture = Color3.fromRGB(80, 200, 120),
	good = Color3.fromRGB(50, 120, 220),
	terror = Color3.fromRGB(200, 70, 60),
	glass = Color3.fromRGB(140, 190, 220),
	path = Color3.fromRGB(180, 160, 60),
	choke = Color3.fromRGB(80, 80, 85),
	plaza = Color3.fromRGB(130, 128, 118),
	planter = Color3.fromRGB(70, 88, 62),
	vehicle = Color3.fromRGB(45, 48, 55),
	barrier = Color3.fromRGB(160, 120, 50),
	lamp = Color3.fromRGB(55, 55, 58),
	lampGlow = Color3.fromRGB(255, 230, 170),
}

-- Playable arena AABB (parcel grid ± margin). Perimeter walls seal this volume.
local ARENA = {
	minX = -450,
	maxX = 450,
	minZ = -540,
	maxZ = 200,
	wallHeight = 148,
	wallThickness = 14,
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

local function tagAnchor(instance: Instance, id: string, role: string, safeHouseId: string?)
	instance:SetAttribute("Id", id)
	instance:SetAttribute("Role", role)
	if safeHouseId then
		instance:SetAttribute("SafeHouseId", safeHouseId)
	end
	CollectionService:AddTag(instance, "MapAnchor")
end

local function billboard(parent: BasePart, text: string, offsetY: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, offsetY or 8, 0)
	gui.AlwaysOnTop = true
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
end

local function spawnMarker(
	parent: Folder,
	name: string,
	position: Vector3,
	color: Color3,
	label: string,
	role: string
)
	local floorY = MapMetrics.FloorY
	local p = part(
		parent,
		name,
		Vector3.new(16, 1, 16),
		CFrame.new(position.X, floorY + 0.5, position.Z),
		color,
		Enum.Material.Neon,
		false
	)
	billboard(p, label, 7)
	tagAnchor(p, name, role, nil)
	return p
end

local function pathRibbon(parent: Folder, pathName: string, points: { Vector3 })
	local folder = Instance.new("Folder")
	folder.Name = "Path_" .. pathName
	folder.Parent = parent
	for i, pt in points do
		local wp = part(
			folder,
			string.format("WP_%02d", i),
			Vector3.new(4, 0.4, 4),
			CFrame.new(pt.X, MapMetrics.FloorY + 0.3, pt.Z),
			COLOR.path,
			Enum.Material.Neon,
			false
		)
		wp.Transparency = 0.35
		wp:SetAttribute("PathName", pathName)
		wp:SetAttribute("Index", i)
	end
	-- Thin connector segments (visual only)
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local mid = (a + b) * 0.5
		local len = MapMetrics.straightLine(a, b)
		local seg = part(
			folder,
			string.format("Seg_%02d", i),
			Vector3.new(2, 0.2, math.max(len, 1)),
			CFrame.new(mid.X, MapMetrics.FloorY + 0.25, mid.Z)
				* CFrame.Angles(0, math.atan2(a.X - b.X, a.Z - b.Z), 0),
			COLOR.path,
			Enum.Material.Neon,
			false
		)
		seg.Transparency = 0.65
	end
end

--[[
	Shared capture contracts (do not drift): CaptureVolume + SafeHouseId,
	CaptureBoundary + billboard, MapAnchor at MapMetrics center. Dual entrances
	(south + west). Site identity is plaza vs courtyard massing only.
]]
local function captureContracts(
	folder: Folder,
	id: string,
	center: Vector3,
	displayName: string,
	houseColor: Color3,
	floorSize: Vector3
)
	local cfg = GameConfig.Map
	local floorY = MapMetrics.FloorY

	local floor = part(
		folder,
		"Floor",
		floorSize,
		CFrame.new(center.X, floorY, center.Z),
		houseColor,
		Enum.Material.Slate
	)
	floor:SetAttribute("SafeHouseId", id)

	local stripe = part(
		folder,
		"CaptureBoundary",
		Vector3.new(floorSize.X - 4, 0.25, floorSize.Z - 4),
		CFrame.new(center.X, floorY + 0.65, center.Z),
		COLOR.boundary,
		Enum.Material.Neon,
		false
	)
	stripe:SetAttribute("SafeHouseId", id)
	billboard(stripe, displayName .. " CAPTURE", 10)

	local volume = part(
		folder,
		"CaptureVolume",
		cfg.CaptureSize,
		CFrame.new(center.X, floorY + cfg.CaptureSize.Y / 2, center.Z),
		COLOR.capture,
		Enum.Material.ForceField,
		false
	)
	volume.Transparency = 0.82
	volume:SetAttribute("SafeHouseId", id)

	local anchor = part(
		folder,
		"Anchor",
		Vector3.new(8, 1, 8),
		CFrame.new(center.X, floorY + 0.6, center.Z),
		houseColor,
		Enum.Material.Neon,
		false
	)
	tagAnchor(anchor, displayName, if id == "A" then "SafeHouseA" else "SafeHouseB", id)
end

--[[
	CONSULATE (A) — open diplomatic plaza.
	Breathing room around the pavilion; low planters / bollards / cars as flank
	cover; open center for hold movement; angles in from the plaza rim.
]]
local function buildConsulate(parent: Folder, center: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "SafeHouseA"
	folder.Parent = parent

	local id = Enums.SafeHouseId.A
	local floorY = MapMetrics.FloorY
	local interior = GameConfig.Map.HouseInteriorSize
	local halfX = interior.X / 2
	local halfZ = interior.Z / 2
	local wallH = 14 -- lower pavilion walls than Precinct (open read)
	local wallT = 2

	-- Wide plaza slab (destination clearing, not another canyon block)
	part(
		folder,
		"PlazaPaving",
		Vector3.new(108, 0.5, 96),
		CFrame.new(center.X, floorY + 0.2, center.Z),
		COLOR.plaza,
		Enum.Material.Concrete
	)

	captureContracts(folder, id, center, "CONSULATE", COLOR.houseA, interior)

	-- Pavilion shell: solid north; south + west openings (dual entrances)
	part(
		folder,
		"WallNorth",
		Vector3.new(interior.X, wallH, wallT),
		CFrame.new(center.X, floorY + wallH / 2, center.Z - halfZ),
		COLOR.houseA
	)
	part(
		folder,
		"WallSouthL",
		Vector3.new(interior.X * 0.28, wallH, wallT),
		CFrame.new(center.X - halfX * 0.62, floorY + wallH / 2, center.Z + halfZ),
		COLOR.houseA
	)
	part(
		folder,
		"WallSouthR",
		Vector3.new(interior.X * 0.28, wallH, wallT),
		CFrame.new(center.X + halfX * 0.62, floorY + wallH / 2, center.Z + halfZ),
		COLOR.houseA
	)
	-- East: glass ribbon (embassy read) — still solid collision for hold edges
	part(
		folder,
		"WallEast",
		Vector3.new(wallT, wallH, interior.Z),
		CFrame.new(center.X + halfX, floorY + wallH / 2, center.Z),
		COLOR.glass,
		Enum.Material.Glass
	)
	part(
		folder,
		"WallWestN",
		Vector3.new(wallT, wallH, interior.Z * 0.28),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z - halfZ * 0.62),
		COLOR.houseA
	)
	part(
		folder,
		"WallWestS",
		Vector3.new(wallT, wallH, interior.Z * 0.28),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z + halfZ * 0.62),
		COLOR.houseA
	)
	-- Light canopy (overhead cue without roof highway)
	part(
		folder,
		"PavilionCanopy",
		Vector3.new(interior.X * 0.7, 1.2, interior.Z * 0.55),
		CFrame.new(center.X, floorY + wallH + 0.6, center.Z - 4),
		COLOR.metal,
		Enum.Material.Metal
	)

	-- Interior: sparse cover (open hold — bodyguards use edges, not a bunker)
	part(
		folder,
		"DeskCover",
		Vector3.new(14, 5, 3),
		CFrame.new(center.X - 10, floorY + 2.5, center.Z - 10),
		COLOR.wood,
		Enum.Material.Wood
	)
	part(
		folder,
		"ColumnCover",
		Vector3.new(4, 10, 4),
		CFrame.new(center.X + 12, floorY + 5, center.Z + 4),
		COLOR.concrete
	)

	-- Plaza rim: planters + bollards + cars (flank cover / terror angles)
	local planterOffsets = {
		{ -42, -28 },
		{ -42, 28 },
		{ 42, -28 },
		{ 42, 28 },
		{ -20, -40 },
		{ 20, -40 },
	}
	for i, off in planterOffsets do
		part(
			folder,
			"Planter" .. i,
			Vector3.new(10, 4, 6),
			CFrame.new(center.X + off[1], floorY + 2, center.Z + off[2]),
			COLOR.planter,
			Enum.Material.Grass
		)
	end
	for i = -2, 2 do
		part(
			folder,
			"BollardS" .. i,
			Vector3.new(1.5, 3.5, 1.5),
			CFrame.new(center.X + i * 8, floorY + 1.75, center.Z + 46),
			COLOR.metal,
			Enum.Material.Metal
		)
	end
	-- Greybox vehicles as soft cover on plaza approaches
	part(
		folder,
		"EmbassyCarN",
		Vector3.new(18, 5, 8),
		CFrame.new(center.X - 30, floorY + 2.5, center.Z - 36),
		COLOR.vehicle,
		Enum.Material.Metal
	)
	part(
		folder,
		"EmbassyCarS",
		Vector3.new(18, 5, 8),
		CFrame.new(center.X + 28, floorY + 2.5, center.Z + 34),
		COLOR.vehicle,
		Enum.Material.Metal
	)
	-- Low plaza walls (destination cue, not canyon towers)
	part(
		folder,
		"PlazaWallN",
		Vector3.new(70, 5, 2),
		CFrame.new(center.X, floorY + 2.5, center.Z - 46),
		COLOR.concrete
	)
	part(
		folder,
		"PlazaWallE",
		Vector3.new(2, 5, 50),
		CFrame.new(center.X + 52, floorY + 2.5, center.Z),
		COLOR.concrete
	)

	return folder
end

--[[
	PRECINCT (B) — tighter police courtyard.
	Higher courtyard walls, jersey barriers, parked cruisers — denser cover,
	shorter sightlines, still room to rotate inside the yard.
]]
local function buildPrecinct(parent: Folder, center: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "SafeHouseB"
	folder.Parent = parent

	local id = Enums.SafeHouseId.B
	local floorY = MapMetrics.FloorY
	local interior = GameConfig.Map.HouseInteriorSize
	local halfX = interior.X / 2
	local halfZ = interior.Z / 2
	local wallH = interior.Y -- taller shell than Consulate pavilion
	local wallT = 2.5
	local yardH = 10 -- courtyard enclosure

	-- Courtyard slab (smaller footprint than Consulate plaza — tighter hold)
	part(
		folder,
		"YardPaving",
		Vector3.new(92, 0.5, 84),
		CFrame.new(center.X, floorY + 0.2, center.Z),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)

	captureContracts(folder, id, center, "PRECINCT", COLOR.houseB, interior)

	-- Station shell: solid north + east; south + west gate gaps
	part(
		folder,
		"WallNorth",
		Vector3.new(interior.X, wallH, wallT),
		CFrame.new(center.X, floorY + wallH / 2, center.Z - halfZ),
		COLOR.houseB
	)
	part(
		folder,
		"WallSouthL",
		Vector3.new(interior.X * 0.36, wallH, wallT),
		CFrame.new(center.X - halfX * 0.55, floorY + wallH / 2, center.Z + halfZ),
		COLOR.houseB
	)
	part(
		folder,
		"WallSouthR",
		Vector3.new(interior.X * 0.36, wallH, wallT),
		CFrame.new(center.X + halfX * 0.55, floorY + wallH / 2, center.Z + halfZ),
		COLOR.houseB
	)
	part(
		folder,
		"WallEast",
		Vector3.new(wallT, wallH, interior.Z),
		CFrame.new(center.X + halfX, floorY + wallH / 2, center.Z),
		COLOR.houseB
	)
	part(
		folder,
		"WallWestN",
		Vector3.new(wallT, wallH, interior.Z * 0.36),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z - halfZ * 0.55),
		COLOR.houseB
	)
	part(
		folder,
		"WallWestS",
		Vector3.new(wallT, wallH, interior.Z * 0.36),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z + halfZ * 0.55),
		COLOR.houseB
	)
	-- Flat station roof edge (destination mass, not a rotate deck)
	part(
		folder,
		"StationRoof",
		Vector3.new(interior.X + 2, 2, interior.Z + 2),
		CFrame.new(center.X, floorY + wallH + 1, center.Z),
		COLOR.metal,
		Enum.Material.Metal
	)

	-- Dense interior cover (tighter pistol fight than Consulate)
	part(
		folder,
		"DeskBank",
		Vector3.new(16, 6, 4),
		CFrame.new(center.X - 8, floorY + 3, center.Z - 6),
		COLOR.wood,
		Enum.Material.Wood
	)
	part(
		folder,
		"FilingCover",
		Vector3.new(4, 9, 14),
		CFrame.new(center.X + 14, floorY + 4.5, center.Z + 2),
		COLOR.cover
	)
	part(
		folder,
		"CellBlock",
		Vector3.new(10, 8, 10),
		CFrame.new(center.X + 2, floorY + 4, center.Z - 16),
		COLOR.metal,
		Enum.Material.Metal
	)

	-- Courtyard walls (U-shape: open toward west approach / south gate)
	part(
		folder,
		"YardWallN",
		Vector3.new(88, yardH, 3),
		CFrame.new(center.X, floorY + yardH / 2, center.Z - 40),
		COLOR.wall
	)
	part(
		folder,
		"YardWallE",
		Vector3.new(3, yardH, 78),
		CFrame.new(center.X + 44, floorY + yardH / 2, center.Z),
		COLOR.wall
	)
	part(
		folder,
		"YardWallS_L",
		Vector3.new(28, yardH, 3),
		CFrame.new(center.X - 28, floorY + yardH / 2, center.Z + 40),
		COLOR.wall
	)
	part(
		folder,
		"YardWallS_R",
		Vector3.new(28, yardH, 3),
		CFrame.new(center.X + 28, floorY + yardH / 2, center.Z + 40),
		COLOR.wall
	)

	-- Jersey barriers + parked cruisers (cover mix inside the yard)
	local barriers = {
		{ -24, -22, 0.3 },
		{ -8, -26, -0.2 },
		{ 18, -18, 0.5 },
		{ -22, 18, -0.4 },
		{ 10, 22, 0.2 },
		{ 26, 8, 1.1 },
	}
	for i, b in barriers do
		part(
			folder,
			"Jersey" .. i,
			Vector3.new(10, 4, 2.5),
			CFrame.new(center.X + b[1], floorY + 2, center.Z + b[2]) * CFrame.Angles(0, b[3], 0),
			COLOR.barrier,
			Enum.Material.Concrete
		)
	end
	part(
		folder,
		"CruiserN",
		Vector3.new(16, 5, 7),
		CFrame.new(center.X - 32, floorY + 2.5, center.Z - 12),
		COLOR.vehicle,
		Enum.Material.Metal
	)
	part(
		folder,
		"CruiserS",
		Vector3.new(16, 5, 7),
		CFrame.new(center.X + 30, floorY + 2.5, center.Z + 16) * CFrame.Angles(0, 1.2, 0),
		COLOR.vehicle,
		Enum.Material.Metal
	)
	-- Checkpoint gate posts at south entrance
	part(
		folder,
		"GatePostL",
		Vector3.new(3, 12, 3),
		CFrame.new(center.X - 8, floorY + 6, center.Z + 40),
		COLOR.metal,
		Enum.Material.Metal
	)
	part(
		folder,
		"GatePostR",
		Vector3.new(3, 12, 3),
		CFrame.new(center.X + 8, floorY + 6, center.Z + 40),
		COLOR.metal,
		Enum.Material.Metal
	)

	return folder
end

local function safeHouse(parent: Folder, id: string, center: Vector3, _displayName: string)
	if id == Enums.SafeHouseId.A then
		return buildConsulate(parent, center)
	end
	return buildPrecinct(parent, center)
end

--[[
	Discrete climb: stacked TrussParts (Roblox-climbable). Costly 8–12s ascent —
	roofs are firing decks, not a rotate layer (§7.5).
]]
local function climbLadder(
	parent: Folder,
	name: string,
	base: Vector3,
	height: number,
	facing: Vector3
)
	local floorY = MapMetrics.FloorY
	local dir = Vector3.new(facing.X, 0, facing.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(1, 0, 0)
	else
		dir = dir.Unit
	end
	-- TrussPart max useful segment ≈ 2×2×N; stack 16-stud sections.
	local sectionH = 16
	local sections = math.max(1, math.ceil(height / sectionH))
	for i = 1, sections do
		local h = math.min(sectionH, height - (i - 1) * sectionH)
		if h < 2 then
			break
		end
		local truss = Instance.new("TrussPart")
		truss.Name = name .. "_Seg" .. i
		truss.Size = Vector3.new(2, h, 2)
		truss.Anchored = true
		truss.CanCollide = true
		truss.Material = Enum.Material.Metal
		truss.Color = COLOR.metal
		local cy = floorY + (i - 1) * sectionH + h / 2
		-- Offset slightly off the building face so players can grab it.
		truss.CFrame = CFrame.new(base.X + dir.X * 1.2, cy, base.Z + dir.Z * 1.2)
		truss.Parent = parent
	end
	-- Small roof ledge at the top so you land (isolated deck — no neighbor bridge).
	part(
		parent,
		name .. "_Ledge",
		Vector3.new(10, 1, 8),
		CFrame.new(base.X + dir.X * 4, floorY + height + 0.5, base.Z + dir.Z * 4),
		COLOR.concrete
	)
end

local function vantageBuilding(
	parent: Folder,
	name: string,
	base: Vector3,
	footprint: Vector3,
	floors: number,
	windowFacing: Vector3,
	ladderSide: Vector3
)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	-- Tall enough to match surrounding canyons; rooftop stays isolated (no neighbor bridge).
	local floorH = 16
	local totalH = floors * floorH
	local floorY = MapMetrics.FloorY

	part(
		folder,
		"Shell",
		Vector3.new(footprint.X, totalH, footprint.Z),
		CFrame.new(base.X, floorY + totalH / 2, base.Z),
		COLOR.brick,
		Enum.Material.Brick
	)

	-- Gapped rooftop deck (firing position only — not a rotate highway)
	part(
		folder,
		"Rooftop",
		Vector3.new(footprint.X - 8, 1, footprint.Z - 8),
		CFrame.new(base.X, floorY + totalH + 0.5, base.Z),
		COLOR.metal,
		Enum.Material.Metal
	)

	-- Ladder on one face only — discrete sniper access, not free stair highway.
	local ladderBase = base
		+ Vector3.new(ladderSide.X * (footprint.X / 2 + 1), 0, ladderSide.Z * (footprint.Z / 2 + 1))
	climbLadder(folder, "SniperLadder", ladderBase, totalH, ladderSide)

	local win = part(
		folder,
		"WindowAngle",
		Vector3.new(10, 7, 1.2),
		CFrame.new(
			base.X + windowFacing.X * (footprint.X / 2 + 0.7),
			floorY + floorH * 1.15,
			base.Z + windowFacing.Z * (footprint.Z / 2 + 0.7)
		),
		COLOR.glass,
		Enum.Material.Glass,
		false
	)
	win.Transparency = 0.35
	win:SetAttribute("Vantage", true)

	part(
		folder,
		"Balcony",
		Vector3.new(footprint.X * 0.55, 1, 5),
		CFrame.new(
			base.X + windowFacing.X * (footprint.X / 2 + 2.5),
			floorY + floorH + 0.5,
			base.Z + windowFacing.Z * 3
		),
		COLOR.concrete
	)
end

--[[
	Very tall city-themed perimeter — skyline / facade walls that fully seal the
	arena so you cannot see or walk beyond the playable city.
]]
local function buildPerimeterWalls(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Perimeter"
	folder.Parent = parent

	local floorY = MapMetrics.FloorY
	local h = ARENA.wallHeight
	local t = ARENA.wallThickness
	local midY = floorY + h / 2
	local spanX = ARENA.maxX - ARENA.minX
	local spanZ = ARENA.maxZ - ARENA.minZ
	local cx = (ARENA.minX + ARENA.maxX) * 0.5
	local cz = (ARENA.minZ + ARENA.maxZ) * 0.5

	local function facadeWall(name: string, size: Vector3, cframe: CFrame)
		part(folder, name, size, cframe, COLOR.facade, Enum.Material.Concrete)
		-- Window-strip greybox (city facade read without see-through gaps)
		local alongX = size.X >= size.Z
		local along = if alongX then size.X else size.Z
		local step = 18
		local rows = 6
		for row = 1, rows do
			local wy = floorY + 18 + (row - 1) * (h - 28) / (rows - 1)
			for i = 0, math.floor(along / step) - 1 do
				local offset = -along * 0.5 + step * 0.5 + i * step
				local wx = if alongX then cframe.Position.X + offset else cframe.Position.X
				local wz = if alongX then cframe.Position.Z else cframe.Position.Z + offset
				-- Slight inset toward arena so windows read on the inner face
				local inset = t * 0.35
				if name == "WallNorth" then
					wz += inset
				elseif name == "WallSouth" then
					wz -= inset
				elseif name == "WallEast" then
					wx -= inset
				elseif name == "WallWest" then
					wx += inset
				end
				local pane = part(
					folder,
					name .. "_Win_" .. row .. "_" .. i,
					Vector3.new(8, 6, 0.6),
					CFrame.new(wx, wy, wz),
					COLOR.window,
					Enum.Material.Glass,
					false
				)
				pane.Transparency = 0.45
			end
		end
	end

	-- Four walls (outer faces flush to ARENA AABB)
	facadeWall(
		"WallSouth",
		Vector3.new(spanX + t * 2, h, t),
		CFrame.new(cx, midY, ARENA.minZ - t * 0.5)
	)
	facadeWall(
		"WallNorth",
		Vector3.new(spanX + t * 2, h, t),
		CFrame.new(cx, midY, ARENA.maxZ + t * 0.5)
	)
	facadeWall("WallWest", Vector3.new(t, h, spanZ), CFrame.new(ARENA.minX - t * 0.5, midY, cz))
	facadeWall("WallEast", Vector3.new(t, h, spanZ), CFrame.new(ARENA.maxX + t * 0.5, midY, cz))

	-- Skyline silhouette crowns (varied heights — greybox city rim)
	local crownStep = 40
	for x = ARENA.minX, ARENA.maxX, crownStep do
		local crownH = 12 + (math.abs(math.floor(x * 0.13)) % 5) * 8
		part(
			folder,
			"SkylineS_" .. math.floor(x),
			Vector3.new(crownStep - 4, crownH, t * 0.6),
			CFrame.new(x + crownStep * 0.5, floorY + h + crownH / 2, ARENA.minZ - t * 0.5),
			COLOR.facadeAccent
		)
		part(
			folder,
			"SkylineN_" .. math.floor(x),
			Vector3.new(crownStep - 4, crownH + 4, t * 0.6),
			CFrame.new(x + crownStep * 0.5, floorY + h + (crownH + 4) / 2, ARENA.maxZ + t * 0.5),
			COLOR.facadeAccent
		)
	end
	for z = ARENA.minZ, ARENA.maxZ, crownStep do
		local crownH = 10 + (math.abs(math.floor(z * 0.19)) % 4) * 10
		part(
			folder,
			"SkylineW_" .. math.floor(z),
			Vector3.new(t * 0.6, crownH, crownStep - 4),
			CFrame.new(ARENA.minX - t * 0.5, floorY + h + crownH / 2, z + crownStep * 0.5),
			COLOR.facadeAccent
		)
		part(
			folder,
			"SkylineE_" .. math.floor(z),
			Vector3.new(t * 0.6, crownH + 6, crownStep - 4),
			CFrame.new(ARENA.maxX + t * 0.5, floorY + h + (crownH + 6) / 2, z + crownStep * 0.5),
			COLOR.facadeAccent
		)
	end
end

--[[
	City street hierarchy:
	  1. Orthogonal ROAD GRID — asphalt faces between intersections (parcel edges)
	  2. BLOCKS between roads — dense tall buildings on parcels
	  3. ALLEYS — narrow secondary cuts (costly bypasses)
	  4. Metric arterials — reserved (not visually stamped diagonally)
	  5. One LOS island south of Market on the mid avenue
	Spawns sit on road centerlines / intersections, never inside building mass.
]]

-- Primary street width (asphalt lane you can read from above). Was ~22; now wider.
local ROAD_WIDTH = 32
local ROAD_HALF = ROAD_WIDTH * 0.5
-- Secondary alleys — narrower, costlier than primary streets.
local ALLEY_WIDTH = 12
local ALLEY_HALF = ALLEY_WIDTH * 0.5
-- Metric arterial boulevards (follow path ribbons; keep contest timing walkable).
local ARTERIAL_WIDTH = 28
local ARTERIAL_HALF = ARTERIAL_WIDTH * 0.5

-- N–S road centerlines (studs). Motorcade/Market sit on X=0.
local GRID_XS = { -400, -300, -200, -100, 0, 100, 200, 300, 400 }
-- E–W road centerlines. Includes Z=-500 (Motorcade), Z=-50 (Market), Z=0 (house street).
-- Typical 100-stud centerlines → ~68-stud building footprints after 32-stud roads.
-- Midfield uses 50-stud steps (-100/-50/0/50) for denser blocks around Market/houses.
local GRID_ZS = { -500, -400, -300, -200, -100, -50, 0, 50, 150 }

local function distPointToSegment2D(
	px: number,
	pz: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	local abx = bx - ax
	local abz = bz - az
	local apx = px - ax
	local apz = pz - az
	local abLenSq = abx * abx + abz * abz
	if abLenSq < 1e-6 then
		return math.sqrt(apx * apx + apz * apz)
	end
	local t = math.clamp((apx * abx + apz * abz) / abLenSq, 0, 1)
	local qx = ax + abx * t
	local qz = az + abz * t
	local dx = px - qx
	local dz = pz - qz
	return math.sqrt(dx * dx + dz * dz)
end

local function nearPolyline(px: number, pz: number, points: { Vector3 }, halfWidth: number): boolean
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		if distPointToSegment2D(px, pz, a.X, a.Z, b.X, b.Z) <= halfWidth then
			return true
		end
	end
	return false
end

local function inRect(
	px: number,
	pz: number,
	cx: number,
	cz: number,
	halfW: number,
	halfD: number
): boolean
	return math.abs(px - cx) <= halfW and math.abs(pz - cz) <= halfD
end

local function streetCover(parent: Folder, x: number, z: number, name: string, yaw: number?)
	local cf = CFrame.new(x, MapMetrics.FloorY + 2.5, z)
	if yaw then
		cf *= CFrame.Angles(0, yaw, 0)
	end
	part(parent, name, Vector3.new(8, 5, 3), cf, COLOR.cover)
end

--[[
	Intentional skyline mix (stable hash so rebuilds match). Not uniform towers.
	Buckets (~studs):
	  ~35% low mid-rise  28–44
	  ~35% mid-rise      48–72
	  ~20% tall          76–96
	  ~10% tower        100–116
	Landmark corner is stamped separately at 140 (taller than every parcel).
]]
local function parcelHeight(x: number, z: number): number
	local h = math.abs(math.floor(x * 0.17) + math.floor(z * 0.31) * 7)
	local bucket = h % 20
	if bucket <= 6 then
		return 28 + (h % 5) * 4
	elseif bucket <= 13 then
		return 48 + (h % 7) * 4
	elseif bucket <= 17 then
		return 76 + (h % 6) * 4
	end
	return 100 + (h % 5) * 4
end

type ParcelRecord = {
	cx: number,
	cz: number,
	footX: number,
	footZ: number,
	height: number,
	namePrefix: string,
}

-- Landmark SW corner (between X=-400/−300 and Z=-500/−400). Tallest climbable perch.
local LANDMARK = {
	cx = -350,
	cz = -450,
	footX = 56,
	footZ = 52,
	shellH = 116,
	crownH = 24, -- total 140 — above max parcel tower (116)
}

local function stampTallParcel(
	parent: Folder,
	namePrefix: string,
	cx: number,
	cz: number,
	footX: number,
	footZ: number,
	floorY: number
): number?
	if footX < 10 or footZ < 10 then
		return nil
	end
	local h = parcelHeight(cx, cz)
	local style = (math.abs(math.floor(cx) + math.floor(cz)) % 5)
	local color = if style <= 1
		then COLOR.brick
		elseif style == 2 then COLOR.metal
		else COLOR.concrete
	local mat = if style <= 1
		then Enum.Material.Brick
		elseif style == 2 then Enum.Material.Metal
		else Enum.Material.Concrete

	-- Varied massing inside the parcel; sub-volumes stay inside parcel bounds
	-- so they never spill onto the reserved road corridors.
	if style == 0 and footX >= 36 and footZ >= 36 then
		local half = footX * 0.5
		local h2 = math.max(h - 8, 20)
		part(
			parent,
			namePrefix .. "_A",
			Vector3.new(half, h, footZ),
			CFrame.new(cx - half * 0.5, floorY + h / 2, cz),
			color,
			mat
		)
		part(
			parent,
			namePrefix .. "_B",
			Vector3.new(half, h2, footZ),
			CFrame.new(cx + half * 0.5, floorY + h2 / 2, cz),
			COLOR.concrete,
			Enum.Material.Concrete
		)
	elseif style == 3 and footX >= 36 and footZ >= 36 then
		part(
			parent,
			namePrefix .. "_Main",
			Vector3.new(footX, h, footZ * 0.55),
			CFrame.new(cx, floorY + h / 2, cz - footZ * 0.225),
			color,
			mat
		)
		part(
			parent,
			namePrefix .. "_Wing",
			Vector3.new(footX * 0.55, math.max(h - 12, 16), footZ * 0.45),
			CFrame.new(cx - footX * 0.225, floorY + math.max(h - 12, 16) / 2, cz + footZ * 0.275),
			COLOR.brick,
			Enum.Material.Brick
		)
		part(
			parent,
			namePrefix .. "_Fill",
			Vector3.new(footX * 0.45, math.max(h - 20, 14), footZ * 0.45),
			CFrame.new(cx + footX * 0.275, floorY + math.max(h - 20, 14) / 2, cz + footZ * 0.275),
			COLOR.wall
		)
	else
		part(
			parent,
			namePrefix,
			Vector3.new(footX, h, footZ),
			CFrame.new(cx, floorY + h / 2, cz),
			color,
			mat
		)
	end
	return h
end

-- Ladder face toward the nearest ortho road (street-side climb, not alley guts).
local function nearestRoadFacing(
	cx: number,
	cz: number,
	footX: number,
	footZ: number
): (Vector3, Vector3)
	local bestDist = math.huge
	local facing = Vector3.new(1, 0, 0)
	for _, x in GRID_XS do
		local d = math.abs(cx - x)
		if d < bestDist then
			bestDist = d
			facing = if x >= cx then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0)
		end
	end
	for _, z in GRID_ZS do
		local d = math.abs(cz - z)
		if d < bestDist then
			bestDist = d
			facing = if z >= cz then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
		end
	end
	local base =
		Vector3.new(cx + facing.X * (footX * 0.5 + 1), 0, cz + facing.Z * (footZ * 0.5 + 1))
	return base, facing
end

--[[
	SW-corner landmark — taller than every parcel tower, climbable sniper perch
	with a real height advantage over mid-rises. Isolated deck (no roof bridges).
]]
local function buildLandmarkTower(parent: Folder, floorY: number)
	local folder = Instance.new("Folder")
	folder.Name = "LandmarkCornerSW"
	folder.Parent = parent

	local cx = LANDMARK.cx
	local cz = LANDMARK.cz
	local footX = LANDMARK.footX
	local footZ = LANDMARK.footZ
	local shellH = LANDMARK.shellH
	local crownH = LANDMARK.crownH
	local totalH = shellH + crownH

	part(
		folder,
		"Shell",
		Vector3.new(footX, shellH, footZ),
		CFrame.new(cx, floorY + shellH / 2, cz),
		COLOR.brick,
		Enum.Material.Brick
	)
	-- Stepped crown reads as the skyline landmark from street level.
	part(
		folder,
		"Crown",
		Vector3.new(footX * 0.58, crownH, footZ * 0.58),
		CFrame.new(cx, floorY + shellH + crownH / 2, cz),
		COLOR.metal,
		Enum.Material.Metal
	)
	-- Sniper perch (isolated — no neighbor bridge).
	part(
		folder,
		"SniperPerch",
		Vector3.new(22, 1.2, 18),
		CFrame.new(cx, floorY + totalH + 0.6, cz),
		COLOR.concrete
	)
	-- Parapet cover so the perch has a real hold advantage, not a flat death plate.
	part(
		folder,
		"PerchParapetN",
		Vector3.new(18, 4, 1.5),
		CFrame.new(cx, floorY + totalH + 2.5, cz - 8),
		COLOR.cover
	)
	part(
		folder,
		"PerchParapetE",
		Vector3.new(1.5, 4, 14),
		CFrame.new(cx + 9, floorY + totalH + 2.5, cz),
		COLOR.cover
	)
	local marker = part(
		folder,
		"LandmarkMarker",
		Vector3.new(6, 1, 6),
		CFrame.new(cx, floorY + totalH + 1.5, cz),
		COLOR.boundary,
		Enum.Material.Neon,
		false
	)
	billboard(marker, "LANDMARK PERCH", 6)

	-- Ladder on east face toward city interior (costly climb, discrete access).
	local ladderBase = Vector3.new(cx + footX * 0.5 + 1, 0, cz)
	climbLadder(folder, "LandmarkLadder", ladderBase, totalH, Vector3.new(1, 0, 0))
end

--[[
	Attach TrussPart ladders only to parcels that stand clearly above local
	neighbors — elevated outliers, not every flat roof. Caps count so roofs
	stay discrete snipes (§7.5), not a rotate highway.
]]
local function attachOutlierLadders(parent: Folder, parcels: { ParcelRecord }, floorY: number)
	local NEIGHBOR_R = 150
	local MARGIN = 16 -- must beat local neighbor average by this many studs
	local MIN_HEIGHT = 60 -- low mid-rises never get ladders
	local MAX_LADDERS = 7
	local MIN_SPACING = 90 -- keep snipes discrete across the city

	type Candidate = { parcel: ParcelRecord, advantage: number }
	local candidates: { Candidate } = {}

	for _, p in parcels do
		-- Skip anything too close to the landmark (it owns that corner).
		if math.abs(p.cx - LANDMARK.cx) < 80 and math.abs(p.cz - LANDMARK.cz) < 80 then
			continue
		end
		if p.height < MIN_HEIGHT then
			continue
		end
		local sumN = 0
		local neighborCount = 0
		for _, q in parcels do
			if q ~= p then
				local dx = p.cx - q.cx
				local dz = p.cz - q.cz
				if math.sqrt(dx * dx + dz * dz) <= NEIGHBOR_R then
					neighborCount += 1
					sumN += q.height
				end
			end
		end
		if neighborCount >= 2 then
			local avgN = sumN / neighborCount
			if p.height >= avgN + MARGIN then
				table.insert(candidates, { parcel = p, advantage = p.height - avgN })
			end
		end
	end

	table.sort(candidates, function(a, b)
		if a.advantage == b.advantage then
			return a.parcel.height > b.parcel.height
		end
		return a.advantage > b.advantage
	end)

	local snipes = Instance.new("Folder")
	snipes.Name = "OutlierSnipes"
	snipes.Parent = parent

	local placed: { ParcelRecord } = {}
	for _, c in candidates do
		if #placed >= MAX_LADDERS then
			break
		end
		local p = c.parcel
		local tooClose = false
		for _, other in placed do
			local dx = p.cx - other.cx
			local dz = p.cz - other.cz
			if math.sqrt(dx * dx + dz * dz) < MIN_SPACING then
				tooClose = true
				break
			end
		end
		if tooClose then
			continue
		end

		local folder = Instance.new("Folder")
		folder.Name = p.namePrefix .. "_OutlierSnipe"
		folder.Parent = snipes

		-- Small isolated deck on the roof (no bridges to neighbors).
		local deckX = math.min(p.footX - 6, 14)
		local deckZ = math.min(p.footZ - 6, 12)
		if deckX >= 8 and deckZ >= 8 then
			part(
				folder,
				"SniperDeck",
				Vector3.new(deckX, 1, deckZ),
				CFrame.new(p.cx, floorY + p.height + 0.5, p.cz),
				COLOR.metal,
				Enum.Material.Metal
			)
		end
		local base, facing = nearestRoadFacing(p.cx, p.cz, p.footX, p.footZ)
		climbLadder(folder, "OutlierLadder", base, p.height, facing)
		table.insert(placed, p)
	end
end

--[[
	Road visuals: asphalt decks that live only in open street corridors
	(between parcel edges), with curb lips at the asphalt edge and short
	dashed center marks on open block faces — never continuous neon/curb
	ribbons that pierce building volumes.
]]
local function roadYaw(a: Vector3, b: Vector3): number
	return math.atan2(a.X - b.X, a.Z - b.Z)
end

local function stampAsphaltDeck(
	parent: Folder,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	floorY: number
)
	local len = MapMetrics.straightLine(a, b)
	if len < 1 then
		return
	end
	local mid = (a + b) * 0.5
	local yaw = roadYaw(a, b)
	part(
		parent,
		name,
		Vector3.new(width, 0.35, math.max(len, 1)),
		CFrame.new(mid.X, floorY + 0.18, mid.Z) * CFrame.Angles(0, yaw, 0),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)
end

-- Short dashed center marks on open street only (inset from junctions).
local function stampCenterDashes(
	parent: Folder,
	namePrefix: string,
	a: Vector3,
	b: Vector3,
	floorY: number
)
	local len = MapMetrics.straightLine(a, b)
	-- Need room for junction inset + at least one dash.
	if len < 28 then
		return
	end
	local yaw = roadYaw(a, b)
	local dir = (b - a)
	if dir.Magnitude < 1e-3 then
		return
	end
	dir = dir.Unit
	local inset = 10
	local dashLen = 6
	local gap = 8
	local usable = len - inset * 2
	local stride = dashLen + gap
	local count = math.floor((usable + gap) / stride)
	if count < 1 then
		return
	end
	for i = 0, count - 1 do
		local t = inset + dashLen * 0.5 + i * stride
		if t + dashLen * 0.5 > len - inset then
			break
		end
		local p = a + dir * t
		part(
			parent,
			namePrefix .. "_Dash" .. i,
			Vector3.new(1.0, 0.12, dashLen),
			CFrame.new(p.X, floorY + 0.42, p.Z) * CFrame.Angles(0, yaw, 0),
			COLOR.marking,
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

-- Curb lips along both long edges, stopped short of junctions so they
-- never run through crossing streets or into parcel towers.
local function stampCurbPair(
	parent: Folder,
	namePrefix: string,
	a: Vector3,
	b: Vector3,
	width: number,
	floorY: number
)
	local len = MapMetrics.straightLine(a, b)
	if len < 16 then
		return
	end
	local yaw = roadYaw(a, b)
	local dir = (b - a)
	if dir.Magnitude < 1e-3 then
		return
	end
	dir = dir.Unit
	local inset = 6
	local curbLen = len - inset * 2
	if curbLen < 8 then
		return
	end
	local mid = a + dir * (len * 0.5)
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local edge = width * 0.5 - 0.4
	part(
		parent,
		namePrefix .. "_CurbL",
		Vector3.new(1.2, 0.9, curbLen),
		CFrame.new(mid.X + right.X * edge, floorY + 0.45, mid.Z + right.Z * edge)
			* CFrame.Angles(0, yaw, 0),
		COLOR.curb,
		Enum.Material.Concrete
	)
	part(
		parent,
		namePrefix .. "_CurbR",
		Vector3.new(1.2, 0.9, curbLen),
		CFrame.new(mid.X - right.X * edge, floorY + 0.45, mid.Z - right.Z * edge)
			* CFrame.Angles(0, yaw, 0),
		COLOR.curb,
		Enum.Material.Concrete
	)
end

-- One open-street face between two intersections: asphalt + curbs + dashes.
local function stampStreetFace(
	parent: Folder,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	floorY: number,
	withMarks: boolean
)
	stampAsphaltDeck(parent, name, a, b, width, floorY)
	stampCurbPair(parent, name, a, b, width, floorY)
	if withMarks then
		stampCenterDashes(parent, name, a, b, floorY)
	end
end

-- Axis-aligned grid: stamp per block-face so asphalt stops at parcel edges
-- (junction pads bridge the crossings). No full-map mega-ribbons.
local function stampOrthoGridRoads(parent: Folder, floorY: number)
	for _, x in GRID_XS do
		for j = 1, #GRID_ZS - 1 do
			local z0 = GRID_ZS[j]
			local z1 = GRID_ZS[j + 1]
			stampStreetFace(
				parent,
				string.format("NS_%d_%d", math.floor(x), math.floor(z0)),
				Vector3.new(x, 0, z0),
				Vector3.new(x, 0, z1),
				ROAD_WIDTH,
				floorY,
				true
			)
		end
	end
	for _, z in GRID_ZS do
		for i = 1, #GRID_XS - 1 do
			local x0 = GRID_XS[i]
			local x1 = GRID_XS[i + 1]
			stampStreetFace(
				parent,
				string.format("EW_%d_%d", math.floor(x0), math.floor(z)),
				Vector3.new(x0, 0, z),
				Vector3.new(x1, 0, z),
				ROAD_WIDTH,
				floorY,
				true
			)
		end
	end
end

-- Narrow alleys: asphalt + curbs only (no center marks — too tight to read).
local function stampAlleyPolyline(
	parent: Folder,
	namePrefix: string,
	points: { Vector3 },
	width: number,
	floorY: number
)
	for i = 1, #points - 1 do
		stampStreetFace(
			parent,
			namePrefix .. "_" .. i,
			points[i],
			points[i + 1],
			width,
			floorY,
			false
		)
	end
end

local function buildUrbanMassing(parent: Folder)
	local floorY = MapMetrics.FloorY
	local massing = Instance.new("Folder")
	massing.Name = "UrbanMassing"
	massing.Parent = parent

	local blocksFolder = Instance.new("Folder")
	blocksFolder.Name = "CityBlocks"
	blocksFolder.Parent = massing

	local lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "LanesAndChokes"
	lanesFolder.Parent = massing

	local roadsFolder = Instance.new("Folder")
	roadsFolder.Name = "RoadNetwork"
	roadsFolder.Parent = massing

	local paths = MapMetrics.Paths
	local goodToA = paths.Good_to_A.points
	local goodToB = paths.Good_to_B.points
	local terrorToA = paths.Terror_to_A.points
	local terrorToB = paths.Terror_to_B.points
	local aToB = paths.A_to_B.points
	local midLane = paths.Good_to_Terror.points

	-- Secondary alleys (narrower than primary grid roads) — intentional costly cuts.
	local westAlley = {
		Vector3.new(-250, 0, -450),
		Vector3.new(-250, 0, -350),
		Vector3.new(-250, 0, -250),
		Vector3.new(-250, 0, -150),
		Vector3.new(-250, 0, -50),
	}
	local eastAlley = {
		Vector3.new(250, 0, -450),
		Vector3.new(250, 0, -350),
		Vector3.new(250, 0, -250),
		Vector3.new(250, 0, -150),
		Vector3.new(250, 0, -50),
	}
	local midAlleyW = {
		Vector3.new(-150, 0, -250),
		Vector3.new(-150, 0, -150),
		Vector3.new(-150, 0, -50),
	}
	local midAlleyE = {
		Vector3.new(150, 0, -250),
		Vector3.new(150, 0, -150),
		Vector3.new(150, 0, -50),
	}

	----------------------------------------------------------------
	-- 1. ROAD GRID FIRST — per-block asphalt faces (stop at parcels)
	----------------------------------------------------------------
	stampOrthoGridRoads(roadsFolder, floorY)

	----------------------------------------------------------------
	-- Alleys only as RoadNetwork visuals. Metric arterials stay as
	-- walkable reservations (onArterial) so contest timing holds, but
	-- we do NOT stamp diagonal asphalt/mark/curb ribbons through towers.
	----------------------------------------------------------------
	stampAlleyPolyline(roadsFolder, "Alley_West", westAlley, ALLEY_WIDTH, floorY)
	stampAlleyPolyline(roadsFolder, "Alley_East", eastAlley, ALLEY_WIDTH, floorY)
	stampAlleyPolyline(roadsFolder, "Alley_MidW", midAlleyW, ALLEY_WIDTH, floorY)
	stampAlleyPolyline(roadsFolder, "Alley_MidE", midAlleyE, ALLEY_WIDTH, floorY)

	-- Intersection pads at every grid crossing (reads as street junctions from above).
	local junctionIdx = 0
	for _, x in GRID_XS do
		for _, z in GRID_ZS do
			junctionIdx += 1
			part(
				roadsFolder,
				"Junction_" .. junctionIdx,
				Vector3.new(ROAD_WIDTH + 2, 0.3, ROAD_WIDTH + 2),
				CFrame.new(x, floorY + 0.16, z),
				COLOR.asphalt,
				Enum.Material.Asphalt
			)
		end
	end

	-- Reserved sites: safe-house clearings + approach-vantage footprints
	-- + SW landmark footprint + the single Market LOS blocker island.
	-- Consulate plaza is intentionally larger/more open than Precinct courtyard.
	-- Spawns (Motorcade / Market) are ON the grid roads — no clearPad plaza needed.
	-- Extra sniper pads removed: ladders now attach to elevated parcel outliers.
	local clearPads = {
		{ x = -385, z = 0, hw = 56, hd = 50 }, -- Consulate open plaza
		{ x = 385, z = 0, hw = 50, hd = 46 }, -- Precinct tighter courtyard
		{ x = -150, z = -260, hw = 18, hd = 16 }, -- approach vantages
		{ x = 150, z = -260, hw = 18, hd = 16 },
		{ x = -280, z = -120, hw = 16, hd = 18 },
		{ x = 280, z = -120, hw = 16, hd = 18 },
		{ x = LANDMARK.cx, z = LANDMARK.cz, hw = 36, hd = 34 }, -- SW landmark
		-- One intentional LOS island south of Market on the mid avenue.
		{ x = 0, z = -145, hw = 26, hd = 20 },
	}

	local function onOrthoRoad(px: number, pz: number): boolean
		for _, x in GRID_XS do
			if math.abs(px - x) <= ROAD_HALF then
				return true
			end
		end
		for _, z in GRID_ZS do
			if math.abs(pz - z) <= ROAD_HALF then
				return true
			end
		end
		return false
	end

	local function onAlley(px: number, pz: number): boolean
		return nearPolyline(px, pz, westAlley, ALLEY_HALF)
			or nearPolyline(px, pz, eastAlley, ALLEY_HALF)
			or nearPolyline(px, pz, midAlleyW, ALLEY_HALF)
			or nearPolyline(px, pz, midAlleyE, ALLEY_HALF)
	end

	local function onArterial(px: number, pz: number): boolean
		return nearPolyline(px, pz, midLane, ARTERIAL_HALF)
			or nearPolyline(px, pz, goodToA, ARTERIAL_HALF)
			or nearPolyline(px, pz, goodToB, ARTERIAL_HALF)
			or nearPolyline(px, pz, aToB, ARTERIAL_HALF)
			or nearPolyline(px, pz, terrorToA, ARTERIAL_HALF)
			or nearPolyline(px, pz, terrorToB, ARTERIAL_HALF)
	end

	local function isReserved(px: number, pz: number): boolean
		for _, pad in clearPads do
			if inRect(px, pz, pad.x, pad.z, pad.hw, pad.hd) then
				return true
			end
		end
		return onOrthoRoad(px, pz) or onAlley(px, pz) or onArterial(px, pz)
	end

	----------------------------------------------------------------
	-- 2. FILL BLOCKS between roads — buildings sit on parcels, not roads
	--    Heights vary (low mid → tower); ladders only on elevated outliers.
	----------------------------------------------------------------
	local parcels: { ParcelRecord } = {}
	local function recordParcel(
		namePrefix: string,
		cx: number,
		cz: number,
		footX: number,
		footZ: number,
		h: number?
	)
		if h == nil then
			return
		end
		table.insert(parcels, {
			cx = cx,
			cz = cz,
			footX = footX,
			footZ = footZ,
			height = h,
			namePrefix = namePrefix,
		})
	end

	local idx = 0
	for i = 1, #GRID_XS - 1 do
		for j = 1, #GRID_ZS - 1 do
			local x0 = GRID_XS[i]
			local x1 = GRID_XS[i + 1]
			local z0 = GRID_ZS[j]
			local z1 = GRID_ZS[j + 1]
			-- Parcel inset from road edges so asphalt corridors stay continuous.
			local left = x0 + ROAD_HALF + 1
			local right = x1 - ROAD_HALF - 1
			local south = z0 + ROAD_HALF + 1
			local north = z1 - ROAD_HALF - 1
			local footX = right - left
			local footZ = north - south
			if footX >= 12 and footZ >= 12 then
				local cx = (left + right) * 0.5
				local cz = (south + north) * 0.5

				-- Skip parcels eaten by house yards / landmark / arterials.
				-- If arterial/alley cuts the block, fill leftover lobes when large.
				if isReserved(cx, cz) then
					local subW = footX * 0.48
					local subD = footZ * 0.48
					local offsets = {
						{ cx - footX * 0.25, cz - footZ * 0.25 },
						{ cx + footX * 0.25, cz - footZ * 0.25 },
						{ cx - footX * 0.25, cz + footZ * 0.25 },
						{ cx + footX * 0.25, cz + footZ * 0.25 },
					}
					for _, off in offsets do
						local sx, sz = off[1], off[2]
						if not isReserved(sx, sz) and subW >= 14 and subD >= 14 then
							idx += 1
							local namePrefix = "Block_" .. idx
							local h = stampTallParcel(
								blocksFolder,
								namePrefix,
								sx,
								sz,
								subW,
								subD,
								floorY
							)
							recordParcel(namePrefix, sx, sz, subW, subD, h)
						end
					end
				else
					idx += 1
					local namePrefix = "Block_" .. idx
					local h =
						stampTallParcel(blocksFolder, namePrefix, cx, cz, footX, footZ, floorY)
					recordParcel(namePrefix, cx, cz, footX, footZ, h)
				end
			end
		end
	end

	----------------------------------------------------------------
	-- SW-corner landmark (taller than every parcel) + outlier ladders.
	-- Ladders only on buildings that beat local neighbors — discrete snipes.
	----------------------------------------------------------------
	buildLandmarkTower(blocksFolder, floorY)
	attachOutlierLadders(blocksFolder, parcels, floorY)

	----------------------------------------------------------------
	-- Exactly ONE building in front of Market (terror) spawn that
	-- breaks direct LOS down the mid avenue to Motorcade (good).
	-- Spawn stays on the road at (0, -50); this island sits south
	-- of it on X=0 so the round-start stare is blocked. Players
	-- flank via adjacent N–S streets — not a wall of buildings.
	----------------------------------------------------------------
	do
		local losH = 72
		local losW = 48 -- wider than ROAD_WIDTH so spawn jitter (±14 X) cannot peek past
		local losD = 36
		local losZ = -145 -- between Market (-50) and Motorcade (-500)
		part(
			blocksFolder,
			"TerrorSpawnLOSBlocker",
			Vector3.new(losW, losH, losD),
			CFrame.new(0, floorY + losH / 2, losZ),
			COLOR.concrete,
			Enum.Material.Concrete
		)
	end

	----------------------------------------------------------------
	-- Chokes / arcade / street cover on primary avenues (not open fields)
	----------------------------------------------------------------
	part(
		lanesFolder,
		"CanalBridgeChokeL",
		Vector3.new(34, 28, 24),
		CFrame.new(-28, floorY + 14, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"CanalBridgeChokeR",
		Vector3.new(34, 28, 24),
		CFrame.new(28, floorY + 14, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"CanalDeck",
		Vector3.new(22, 1, 28),
		CFrame.new(0, floorY + 0.5, -300),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)

	part(
		lanesFolder,
		"WestLaneChokeL",
		Vector3.new(22, 30, 18),
		CFrame.new(-130, floorY + 15, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"WestLaneChokeR",
		Vector3.new(22, 30, 18),
		CFrame.new(-70, floorY + 15, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"EastLaneChokeL",
		Vector3.new(22, 30, 18),
		CFrame.new(70, floorY + 15, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"EastLaneChokeR",
		Vector3.new(22, 30, 18),
		CFrame.new(130, floorY + 15, -300),
		COLOR.choke
	)

	part(
		lanesFolder,
		"SouthBlvdChokeW",
		Vector3.new(28, 36, 20),
		CFrame.new(-200, floorY + 18, -280),
		COLOR.choke
	)
	part(
		lanesFolder,
		"SouthBlvdChokeE",
		Vector3.new(28, 36, 20),
		CFrame.new(200, floorY + 18, -280),
		COLOR.choke
	)

	for i = -3, 3 do
		part(
			lanesFolder,
			"ArcadePillar" .. i,
			Vector3.new(3, 14, 3),
			CFrame.new(i * 12, floorY + 7, -340),
			COLOR.concrete
		)
	end
	part(
		lanesFolder,
		"ArcadeRoof",
		Vector3.new(88, 2, 22),
		CFrame.new(0, floorY + 15, -340),
		COLOR.metal,
		Enum.Material.Metal
	)

	for i = 1, 8 do
		local z = -480 + i * 50
		streetCover(lanesFolder, -12, z, "MidCoverL" .. i)
		streetCover(lanesFolder, 12, z, "MidCoverR" .. i)
	end
	for i = 1, 5 do
		local t = i / 6
		local ax = goodToA[1].X + (goodToA[#goodToA].X - goodToA[1].X) * t
		local az = goodToA[1].Z + (goodToA[#goodToA].Z - goodToA[1].Z) * t
		local bx = goodToB[1].X + (goodToB[#goodToB].X - goodToB[1].X) * t
		local bz = goodToB[1].Z + (goodToB[#goodToB].Z - goodToB[1].Z) * t
		streetCover(lanesFolder, ax + 10, az, "WestLaneCover" .. i, 0.4)
		streetCover(lanesFolder, bx - 10, bz, "EastLaneCover" .. i, -0.4)
	end
end

local function buildVantages(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Vantages"
	folder.Parent = parent

	-- Four approach/window angles onto main routes; no dual-house oversights.
	-- Extra city snipes live on elevated parcel outliers + SW landmark (massing).
	-- Access is discrete TrussPart ladders (not free stair ramps across roofs).
	vantageBuilding(
		folder,
		"VantageWestApproach",
		Vector3.new(-150, 0, -260),
		Vector3.new(30, 0, 28),
		4,
		Vector3.new(1, 0, 0),
		Vector3.new(1, 0, 0) -- ladder on street-facing east face
	)
	vantageBuilding(
		folder,
		"VantageEastApproach",
		Vector3.new(150, 0, -260),
		Vector3.new(30, 0, 28),
		4,
		Vector3.new(-1, 0, 0),
		Vector3.new(-1, 0, 0)
	)
	vantageBuilding(
		folder,
		"VantageNearConsulate",
		Vector3.new(-280, 0, -120),
		Vector3.new(28, 0, 30),
		5,
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1)
	)
	vantageBuilding(
		folder,
		"VantageNearPrecinct",
		Vector3.new(280, 0, -120),
		Vector3.new(28, 0, 30),
		5,
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1)
	)
end

--[[
	Evening atmosphere so street / site lights actually matter in canyons.
	City-first mood only — no gameplay change.
]]
local function configureCityAtmosphere()
	Lighting.ClockTime = 20.25
	Lighting.Brightness = 1.1
	Lighting.Ambient = Color3.fromRGB(42, 46, 58)
	Lighting.OutdoorAmbient = Color3.fromRGB(58, 62, 72)
	Lighting.ColorShift_Top = Color3.fromRGB(40, 50, 80)
	Lighting.ColorShift_Bottom = Color3.fromRGB(20, 22, 28)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.GlobalShadows = true
end

local WARM_LIGHT = Color3.fromRGB(255, 228, 185)
local COOL_SITE = Color3.fromRGB(210, 230, 255)
local SPAWN_LIGHT = Color3.fromRGB(255, 210, 160)

local function attachPointLight(
	host: BasePart,
	range: number,
	brightness: number,
	color: Color3
): PointLight
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Shadows = false -- perf: city count is moderate; shadow casters explode cost
	light.Parent = host
	return light
end

-- Greybox lamp post on a curb (pole + neon head + PointLight).
local function streetLamp(parent: Folder, name: string, x: number, z: number)
	local floorY = MapMetrics.FloorY
	local poleH = 16
	part(
		parent,
		name .. "_Pole",
		Vector3.new(0.7, poleH, 0.7),
		CFrame.new(x, floorY + poleH / 2, z),
		COLOR.lamp,
		Enum.Material.Metal
	)
	local head = part(
		parent,
		name .. "_Head",
		Vector3.new(2.2, 1.1, 2.2),
		CFrame.new(x, floorY + poleH + 0.35, z),
		COLOR.lampGlow,
		Enum.Material.Neon,
		false
	)
	head.Transparency = 0.12
	attachPointLight(head, 52, 1.3, WARM_LIGHT)
end

-- Compact wall / entrance sconce (no tall pole — site interiors + door gaps).
local function siteSconce(
	parent: Folder,
	name: string,
	position: Vector3,
	range: number,
	brightness: number,
	color: Color3
)
	local fixture = part(
		parent,
		name,
		Vector3.new(2, 1.4, 2),
		CFrame.new(position),
		COLOR.lampGlow,
		Enum.Material.Neon,
		false
	)
	fixture.Transparency = 0.18
	attachPointLight(fixture, range, brightness, color)
end

-- SpotLight on a fixture aimed along `look` (gate washes into a courtyard).
local function siteSpot(
	parent: Folder,
	name: string,
	position: Vector3,
	look: Vector3,
	range: number,
	brightness: number,
	angle: number
)
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end
	local fixture = part(
		parent,
		name,
		Vector3.new(1.6, 1.2, 1.6),
		CFrame.lookAt(position, position + dir),
		COLOR.lampGlow,
		Enum.Material.Neon,
		false
	)
	fixture.Transparency = 0.2
	local spot = Instance.new("SpotLight")
	spot.Name = "Glow"
	spot.Face = Enum.NormalId.Front
	spot.Angle = angle
	spot.Range = range
	spot.Brightness = brightness
	spot.Color = WARM_LIGHT
	spot.Shadows = false
	spot.Parent = fixture
end

local function lightConsulate(parent: Folder, center: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "ConsulateLights"
	folder.Parent = parent
	local floorY = MapMetrics.FloorY
	local interior = GameConfig.Map.HouseInteriorSize
	local halfX = interior.X / 2
	local halfZ = interior.Z / 2

	-- Dual entrances (south + west gaps)
	siteSconce(
		folder,
		"EntranceSouth",
		Vector3.new(center.X, floorY + 9, center.Z + halfZ - 1),
		38,
		1.6,
		COOL_SITE
	)
	siteSconce(
		folder,
		"EntranceWest",
		Vector3.new(center.X - halfX + 1, floorY + 9, center.Z),
		38,
		1.6,
		COOL_SITE
	)
	-- Pavilion canopy fill + sparse plaza rim (open hold readability)
	siteSconce(
		folder,
		"CanopyFill",
		Vector3.new(center.X, floorY + 12, center.Z - 4),
		42,
		1.4,
		WARM_LIGHT
	)
	siteSconce(
		folder,
		"PlazaApproachS",
		Vector3.new(center.X, floorY + 10, center.Z + 44),
		36,
		1.2,
		WARM_LIGHT
	)
	siteSconce(
		folder,
		"PlazaRimW",
		Vector3.new(center.X - 40, floorY + 8, center.Z),
		32,
		1.1,
		WARM_LIGHT
	)
	siteSconce(
		folder,
		"PlazaRimE",
		Vector3.new(center.X + 40, floorY + 8, center.Z),
		32,
		1.1,
		WARM_LIGHT
	)
end

local function lightPrecinct(parent: Folder, center: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "PrecinctLights"
	folder.Parent = parent
	local floorY = MapMetrics.FloorY
	local interior = GameConfig.Map.HouseInteriorSize
	local halfX = interior.X / 2
	local halfZ = interior.Z / 2

	-- South gate wash into the yard + gate-post sconces
	siteSpot(
		folder,
		"GateSpot",
		Vector3.new(center.X, floorY + 11, center.Z + 38),
		Vector3.new(0, 0, -1),
		48,
		2.0,
		75
	)
	siteSconce(
		folder,
		"GatePostL",
		Vector3.new(center.X - 8, floorY + 11, center.Z + 40),
		28,
		1.3,
		WARM_LIGHT
	)
	siteSconce(
		folder,
		"GatePostR",
		Vector3.new(center.X + 8, floorY + 11, center.Z + 40),
		28,
		1.3,
		WARM_LIGHT
	)
	siteSconce(
		folder,
		"EntranceWest",
		Vector3.new(center.X - halfX + 1, floorY + 9, center.Z),
		36,
		1.5,
		COOL_SITE
	)
	siteSconce(
		folder,
		"YardCenter",
		Vector3.new(center.X, floorY + 10, center.Z + 8),
		40,
		1.35,
		WARM_LIGHT
	)
	siteSconce(
		folder,
		"StationInterior",
		Vector3.new(center.X - 4, floorY + 10, center.Z - 4),
		34,
		1.45,
		COOL_SITE
	)
	siteSconce(
		folder,
		"SouthDoorGap",
		Vector3.new(center.X, floorY + 9, center.Z + halfZ - 1),
		32,
		1.4,
		COOL_SITE
	)
end

local function lightSpawns(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "SpawnLights"
	folder.Parent = parent
	local floorY = MapMetrics.FloorY
	local motorcade = MapMetrics.Anchors.Motorcade.position
	local market = MapMetrics.Anchors.Market.position

	-- Triad of poles around each spawn pad (road-centerline pools stay readable)
	local offsets = {
		{ 14, 10 },
		{ -14, 10 },
		{ 0, -14 },
	}
	for i, off in offsets do
		streetLamp(folder, "MotorcadeLamp" .. i, motorcade.X + off[1], motorcade.Z + off[2])
		streetLamp(folder, "MarketLamp" .. i, market.X + off[1], market.Z + off[2])
	end
	-- Soft overhead fills so jittered spawns (±14 X) stay lit
	siteSconce(
		folder,
		"MotorcadeFill",
		Vector3.new(motorcade.X, floorY + 14, motorcade.Z),
		36,
		1.5,
		SPAWN_LIGHT
	)
	siteSconce(
		folder,
		"MarketFill",
		Vector3.new(market.X, floorY + 14, market.Z),
		36,
		1.5,
		SPAWN_LIGHT
	)
end

--[[
	City lighting pass: street grid curbs + site entrances + spawn pools.
	Reasonable density (junction curbs, not every stud). Shadows off on lights.
]]
local function buildCityLighting(mapRoot: Folder)
	configureCityAtmosphere()

	local root = Instance.new("Folder")
	root.Name = "CityLighting"
	root.Parent = mapRoot

	local streets = Instance.new("Folder")
	streets.Name = "StreetLights"
	streets.Parent = root

	-- One curb lamp per ortho junction (NW curb). ~81 fixtures for the 9×9 grid —
	-- enough to read canyons without carpet-bombing every stud.
	local curb = ROAD_HALF - 2
	local lampIdx = 0
	for _, x in GRID_XS do
		for _, z in GRID_ZS do
			lampIdx += 1
			streetLamp(streets, "SL_" .. lampIdx, x - curb, z - curb)
		end
	end

	-- Sparse alley midpoints (secondary cuts — fewer lights than primary grid)
	local alleys = Instance.new("Folder")
	alleys.Name = "AlleyLights"
	alleys.Parent = root
	local alleyMids = {
		{ -250, -300 },
		{ -250, -100 },
		{ 250, -300 },
		{ 250, -100 },
		{ -150, -150 },
		{ 150, -150 },
	}
	for i, mid in alleyMids do
		streetLamp(alleys, "AlleyLamp" .. i, mid[1] + 5, mid[2])
	end

	lightConsulate(root, MapMetrics.Anchors.Consulate.position)
	lightPrecinct(root, MapMetrics.Anchors.Precinct.position)
	lightSpawns(root)

	local lightCount = 0
	for _, d in root:GetDescendants() do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			lightCount += 1
		end
	end
	print(string.format("[MapService] City lighting built (%d lights).", lightCount))
end

function MapService.build()
	local existing = Workspace:FindFirstChild("VIPMap")
	if existing then
		existing:Destroy()
	end

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		-- Cover arena + perimeter wall thickness
		baseplate.Size = Vector3.new(960, 2, 820)
		baseplate.Position = Vector3.new(0, -1, -170)
		baseplate.Color = COLOR.asphalt
		baseplate.Material = Enum.Material.Asphalt
	end

	-- Keep a live SpawnLocation on the Motorcade pad so solo Play / lobby
	-- drops the camera onto the greybox (round start still teleports via SpawnService).
	local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn and defaultSpawn:IsA("SpawnLocation") then
		local motorcade = MapMetrics.Anchors.Motorcade.position
		defaultSpawn.Enabled = true
		defaultSpawn.Transparency = 1
		defaultSpawn.CanCollide = false
		defaultSpawn.Neutral = true
		defaultSpawn.Duration = 0
		defaultSpawn.Position = Vector3.new(motorcade.X, MapMetrics.FloorY + 0.5, motorcade.Z)
	end

	local folder = Instance.new("Folder")
	folder.Name = "VIPMap"
	folder.Parent = Workspace
	mapFolder = folder

	local a = MapMetrics.Anchors.Consulate.position
	local b = MapMetrics.Anchors.Precinct.position
	local good = MapMetrics.Anchors.Motorcade.position
	local terror = MapMetrics.Anchors.Market.position

	safeHouse(folder, Enums.SafeHouseId.A, a, "CONSULATE")
	safeHouse(folder, Enums.SafeHouseId.B, b, "PRECINCT")

	spawnMarker(folder, "Motorcade", good, COLOR.good, "MOTORCADE (Good)", "GoodSpawn")
	spawnMarker(folder, "Market", terror, COLOR.terror, "MARKET (Terrorists)", "TerrorSpawn")

	local pathsFolder = Instance.new("Folder")
	pathsFolder.Name = "Paths"
	pathsFolder.Parent = folder
	for _, path in MapMetrics.Paths do
		pathRibbon(pathsFolder, path.name, path.points)
	end

	buildPerimeterWalls(folder)
	buildUrbanMassing(folder)
	buildVantages(folder)
	buildCityLighting(folder)

	-- Persist a StringValue summary for Studio inspection
	local report = Instance.new("StringValue")
	report.Name = "MapMetricsReport"
	report.Value = MapMetrics.formatReport()
	report.Parent = folder

	print("[MapService] Metric VIP greybox built.\n" .. report.Value)
	return folder
end

function MapService.getFolder(): Folder?
	return mapFolder or Workspace:FindFirstChild("VIPMap") :: Folder?
end

function MapService.getCaptureVolume(safeHouseId: string): BasePart?
	local folder = MapService.getFolder()
	if not folder then
		return nil
	end
	local house = folder:FindFirstChild("SafeHouse" .. safeHouseId)
	if not house then
		return nil
	end
	local volume = house:FindFirstChild("CaptureVolume")
	if volume and volume:IsA("BasePart") then
		return volume
	end
	return nil
end

function MapService.getSpawnCFrame(side: string): CFrame
	-- Spawns sit on road centerlines (Motorcade = X=0/Z=-500, Market = X=0/Z=-50).
	-- Keep the random jitter inside the primary asphalt width so players never
	-- land inside a building mass or on a rooftop.
	local anchor = if side == Enums.Side.Good
		then MapMetrics.Anchors.Motorcade.position
		else MapMetrics.Anchors.Market.position
	local halfLane = 14 -- inside ROAD_WIDTH 32
	return CFrame.new(
		anchor.X + (math.random() - 0.5) * halfLane * 2,
		MapMetrics.FloorY + 4,
		anchor.Z + (math.random() - 0.5) * 8
	)
end

function MapService.pointInPart(point: Vector3, volume: BasePart): boolean
	local localPoint = volume.CFrame:PointToObjectSpace(point)
	local half = volume.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

return MapService
