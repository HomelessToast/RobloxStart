--!strict
--[[
	Builds the metric-correct urban greybox from MapMetrics.

	Gameplay wiring (unchanged contracts):
	- Workspace.VIPMap / SafeHouseA|B / CaptureVolume (+ SafeHouseId attribute)
	- MapService.getCaptureVolume / getSpawnCFrame / pointInPart

	New for §7 / world-gen:
	- CollectionService tag MapAnchor + Role / Id / SafeHouseId attributes
	- Visible CaptureBoundary markers
	- Chokes with bypass corridors, elevated vantages, overhead arcade
	- No lethal falls on President routes (stairs / low decks only)
]]

local CollectionService = game:GetService("CollectionService")
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
	houseA = Color3.fromRGB(40, 90, 140),
	houseB = Color3.fromRGB(140, 70, 40),
	boundary = Color3.fromRGB(255, 220, 60),
	capture = Color3.fromRGB(80, 200, 120),
	good = Color3.fromRGB(50, 120, 220),
	terror = Color3.fromRGB(200, 70, 60),
	glass = Color3.fromRGB(140, 190, 220),
	path = Color3.fromRGB(180, 160, 60),
	choke = Color3.fromRGB(80, 80, 85),
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

local function safeHouse(parent: Folder, id: string, center: Vector3, displayName: string)
	local folder = Instance.new("Folder")
	folder.Name = "SafeHouse" .. id
	folder.Parent = parent

	local cfg = GameConfig.Map
	local interior = cfg.HouseInteriorSize
	local floorY = MapMetrics.FloorY
	local houseColor = if id == "A" then COLOR.houseA else COLOR.houseB

	local floor = part(
		folder,
		"Floor",
		Vector3.new(interior.X, 1, interior.Z),
		CFrame.new(center.X, floorY, center.Z),
		houseColor,
		Enum.Material.Slate
	)
	floor:SetAttribute("SafeHouseId", id)

	-- Visible capture boundary (yellow neon stripe)
	local stripe = part(
		folder,
		"CaptureBoundary",
		Vector3.new(interior.X - 4, 0.25, interior.Z - 4),
		CFrame.new(center.X, floorY + 0.65, center.Z),
		COLOR.boundary,
		Enum.Material.Neon,
		false
	)
	stripe:SetAttribute("SafeHouseId", id)
	billboard(stripe, displayName .. " CAPTURE", 10)

	local wallH = interior.Y
	local wallT = 2
	local halfX = interior.X / 2
	local halfZ = interior.Z / 2

	-- North solid; south + west doorways (dual entrances, not mutually visible)
	part(
		folder,
		"WallNorth",
		Vector3.new(interior.X, wallH, wallT),
		CFrame.new(center.X, floorY + wallH / 2, center.Z - halfZ),
		COLOR.wall
	)
	part(
		folder,
		"WallSouthL",
		Vector3.new(interior.X * 0.32, wallH, wallT),
		CFrame.new(center.X - halfX * 0.58, floorY + wallH / 2, center.Z + halfZ),
		COLOR.wall
	)
	part(
		folder,
		"WallSouthR",
		Vector3.new(interior.X * 0.32, wallH, wallT),
		CFrame.new(center.X + halfX * 0.58, floorY + wallH / 2, center.Z + halfZ),
		COLOR.wall
	)
	part(
		folder,
		"WallEast",
		Vector3.new(wallT, wallH, interior.Z),
		CFrame.new(center.X + halfX, floorY + wallH / 2, center.Z),
		COLOR.wall
	)
	part(
		folder,
		"WallWestN",
		Vector3.new(wallT, wallH, interior.Z * 0.32),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z - halfZ * 0.58),
		COLOR.wall
	)
	part(
		folder,
		"WallWestS",
		Vector3.new(wallT, wallH, interior.Z * 0.32),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z + halfZ * 0.58),
		COLOR.wall
	)

	-- Interior cover for 2–3 defenders + a pistol angle
	part(
		folder,
		"CoverA",
		Vector3.new(10, 8, 3),
		CFrame.new(center.X - 12, floorY + 4, center.Z - 8),
		COLOR.cover
	)
	part(
		folder,
		"CoverB",
		Vector3.new(3, 8, 12),
		CFrame.new(center.X + 14, floorY + 4, center.Z + 6),
		COLOR.cover
	)
	part(
		folder,
		"CoverC",
		Vector3.new(8, 6, 8),
		CFrame.new(center.X + 4, floorY + 3, center.Z - 14),
		COLOR.cover
	)

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

	-- Named house anchor (center marker)
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

	return folder
end

local function stairStack(
	parent: Folder,
	name: string,
	base: Vector3,
	toward: Vector3,
	floors: number,
	floorH: number
)
	-- Low, collidable steps — no lethal drops on VIP routes.
	local dir = (toward - Vector3.new(base.X, 0, base.Z))
	if dir.Magnitude < 1 then
		dir = Vector3.new(1, 0, 0)
	else
		dir = Vector3.new(dir.X, 0, dir.Z).Unit
	end
	local right = Vector3.new(-dir.Z, 0, dir.X)
	for i = 1, floors * 3 do
		local pos = base
			+ dir * (i * 3.2)
			+ Vector3.new(0, MapMetrics.FloorY + i * (floorH / 3) * 0.95, 0)
		part(
			parent,
			name .. "_Step" .. i,
			Vector3.new(8, 1, 4),
			CFrame.lookAt(pos, pos + dir),
			COLOR.concrete
		)
		-- Side rail (visual + soft guard)
		if i % 2 == 0 then
			part(
				parent,
				name .. "_Rail" .. i,
				Vector3.new(1, 4, 3),
				CFrame.new(pos + right * 5 + Vector3.new(0, 2, 0)),
				COLOR.metal,
				Enum.Material.Metal
			)
		end
	end
end

local function vantageBuilding(
	parent: Folder,
	name: string,
	base: Vector3,
	footprint: Vector3,
	floors: number,
	windowFacing: Vector3,
	stairToward: Vector3
)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	local floorH = 14
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

	-- Gapped rooftop deck (not a continuous roof highway)
	part(
		folder,
		"Rooftop",
		Vector3.new(footprint.X - 6, 1, footprint.Z - 6),
		CFrame.new(base.X, floorY + totalH + 0.5, base.Z),
		COLOR.metal,
		Enum.Material.Metal
	)

	stairStack(
		folder,
		"Stairs",
		base + Vector3.new(footprint.X / 2 + 2, 0, 0),
		stairToward,
		floors,
		floorH
	)

	-- Window angle marker (non-colliding, readable)
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

	-- Second-floor balcony ledge (elevated vantage Part)
	part(
		folder,
		"Balcony",
		Vector3.new(footprint.X * 0.6, 1, 6),
		CFrame.new(
			base.X + windowFacing.X * (footprint.X / 2 + 3),
			floorY + floorH + 0.5,
			base.Z + windowFacing.Z * 4
		),
		COLOR.concrete
	)
end

local function streetCover(parent: Folder, x: number, z: number, name: string)
	part(
		parent,
		name,
		Vector3.new(12, 5, 4),
		CFrame.new(x, MapMetrics.FloorY + 2.5, z),
		COLOR.cover
	)
end

local function buildUrbanMassing(parent: Folder)
	local floorY = MapMetrics.FloorY
	local massing = Instance.new("Folder")
	massing.Name = "UrbanMassing"
	massing.Parent = parent

	-- Central plaza mass: forces A↔B to take the southern arterial (path ribbon).
	part(
		massing,
		"CentralPlaza",
		Vector3.new(220, 28, 140),
		CFrame.new(0, floorY + 14, -40),
		COLOR.concrete
	)
	-- Northern market block (terror approaches go around)
	part(
		massing,
		"NorthMarketBlock",
		Vector3.new(160, 18, 80),
		CFrame.new(0, floorY + 9, 140),
		COLOR.brick,
		Enum.Material.Brick
	)

	-- Three macro routes from Motorcade with bypasses:
	-- 1) Center avenue (through arcade) — choke at CanalBridge
	-- 2) West lane — alley choke with east bypass
	-- 3) East lane — plaza gate with west bypass

	-- Center choke (≤30 studs wide) + bypass lanes ±40
	part(
		massing,
		"CanalBridgeChokeL",
		Vector3.new(40, 16, 28),
		CFrame.new(-40, floorY + 8, -300),
		COLOR.choke
	)
	part(
		massing,
		"CanalBridgeChokeR",
		Vector3.new(40, 16, 28),
		CFrame.new(40, floorY + 8, -300),
		COLOR.choke
	)
	-- Opening ~24 studs in the middle (smokeable choke)
	part(
		massing,
		"CanalDeck",
		Vector3.new(28, 1, 36),
		CFrame.new(0, floorY + 0.5, -300),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)

	-- West alley choke + longer bypass further west
	part(
		massing,
		"WestAlleyChoke",
		Vector3.new(24, 18, 50),
		CFrame.new(-160, floorY + 9, -220),
		COLOR.choke
	)
	part(
		massing,
		"WestBypassGapMarker",
		Vector3.new(18, 0.3, 60),
		CFrame.new(-220, floorY + 0.2, -220),
		COLOR.path,
		Enum.Material.Neon,
		false
	)

	-- East plaza gate + bypass
	part(
		massing,
		"EastPlazaGateL",
		Vector3.new(30, 16, 20),
		CFrame.new(130, floorY + 8, -200),
		COLOR.choke
	)
	part(
		massing,
		"EastPlazaGateR",
		Vector3.new(30, 16, 20),
		CFrame.new(190, floorY + 8, -200),
		COLOR.choke
	)
	part(
		massing,
		"EastBypassGapMarker",
		Vector3.new(18, 0.3, 60),
		CFrame.new(240, floorY + 0.2, -200),
		COLOR.path,
		Enum.Material.Neon,
		false
	)

	-- Crossover connectors (~40% and ~70% of escort)
	part(
		massing,
		"CrossoverEarly",
		Vector3.new(120, 1, 16),
		CFrame.new(0, floorY + 0.5, -380),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)
	part(
		massing,
		"CrossoverLate",
		Vector3.new(160, 1, 16),
		CFrame.new(0, floorY + 0.5, -160),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)

	-- Overhead covered stretch (arcade) on primary center route
	for i = -4, 4 do
		part(
			massing,
			"ArcadePillar" .. i,
			Vector3.new(3, 14, 3),
			CFrame.new(i * 16, floorY + 7, -340),
			COLOR.concrete
		)
	end
	part(
		massing,
		"ArcadeRoof",
		Vector3.new(140, 2, 28),
		CFrame.new(0, floorY + 15, -340),
		COLOR.metal,
		Enum.Material.Metal
	)

	-- Decision-point wedges near each house (~200–250 out)
	part(
		massing,
		"DecisionA",
		Vector3.new(36, 12, 36),
		CFrame.new(-200, floorY + 6, -40),
		COLOR.wood,
		Enum.Material.Wood
	)
	part(
		massing,
		"DecisionB",
		Vector3.new(36, 12, 36),
		CFrame.new(200, floorY + 6, -40),
		COLOR.wood,
		Enum.Material.Wood
	)

	-- Route cover cadence (≤60 stud open gaps)
	for i = 1, 7 do
		local z = -500 + i * 55
		streetCover(massing, -36, z, "RouteCoverL" .. i)
		streetCover(massing, 36, z, "RouteCoverR" .. i)
	end
end

local function buildVantages(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Vantages"
	folder.Parent = parent

	-- Two rooftop + two window angles onto main routes; no dual-house oversights.
	vantageBuilding(
		folder,
		"VantageWestApproach",
		Vector3.new(-150, 0, -260),
		Vector3.new(36, 0, 32),
		2,
		Vector3.new(1, 0, 0),
		Vector3.new(-100, 0, -260)
	)
	vantageBuilding(
		folder,
		"VantageEastApproach",
		Vector3.new(150, 0, -260),
		Vector3.new(36, 0, 32),
		2,
		Vector3.new(-1, 0, 0),
		Vector3.new(100, 0, -260)
	)
	vantageBuilding(
		folder,
		"VantageNearConsulate",
		Vector3.new(-280, 0, -120),
		Vector3.new(34, 0, 36),
		3,
		Vector3.new(0, 0, 1),
		Vector3.new(-240, 0, -120)
	)
	vantageBuilding(
		folder,
		"VantageNearPrecinct",
		Vector3.new(280, 0, -120),
		Vector3.new(34, 0, 36),
		3,
		Vector3.new(0, 0, 1),
		Vector3.new(240, 0, -120)
	)
end

function MapService.build()
	local existing = Workspace:FindFirstChild("VIPMap")
	if existing then
		existing:Destroy()
	end

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		-- ~800×600 footprint with margin
		baseplate.Size = Vector3.new(1000, 2, 800)
		baseplate.Position = Vector3.new(0, -1, -180)
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

	buildUrbanMassing(folder)
	buildVantages(folder)

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
	local anchor = if side == Enums.Side.Good
		then MapMetrics.Anchors.Motorcade.position
		else MapMetrics.Anchors.Market.position
	local xSpread = if side == Enums.Side.Good then 20 else 24
	return CFrame.new(
		anchor.X + (math.random() - 0.5) * xSpread,
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
