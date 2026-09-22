--!strict
--[[
	Builds the metric-correct urban greybox from MapMetrics.

	City-first hierarchy (Matthew):
	  1. Lay a readable orthogonal ROAD GRID first (asphalt faces between parcels)
	  2. Fill BLOCKS between roads with dense tall buildings
	  3. Cut a few secondary ALLEYS as costly bypasses
	  4. Place spawns on road centerlines / intersections
	  5. One intentional LOS blocker south of Market (terror) spawn
	Then perimeter walls + discrete ladder snipes. No new game mechanics.

	RoadNetwork visuals: per-block asphalt + curb lips + dashed center marks
	on open street only. Metric arterials stay as walkable reservations
	(contest timing) without stamping diagonal mark/curb ribbons through towers.

	Metric ribbons in MapMetrics stay the distance source of truth; primary
	path corridors remain reserved so contest timing holds on the grid.

	Gameplay wiring (unchanged contracts):
	- Workspace.VIPMap / SafeHouseA|B / CaptureVolume (+ SafeHouseId attribute)
	- MapService.getCaptureVolume / getSpawnCFrame / pointInPart

	Also: MapAnchor tags, CaptureBoundary markers, costly choke bypasses,
	tall city perimeter walls, discrete TrussPart ladder climbs onto selected
	roofs (no rooftop highway), overhead arcade, no lethal VIP falls.
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

-- Stable height hash so rebuilds match (studs). Tall canyons block roof peeks.
local function parcelHeight(x: number, z: number): number
	local h = math.abs(math.floor(x * 0.17) + math.floor(z * 0.31) * 7)
	-- 52–100 stud towers (≈4–7 floors at 14 studs)
	return 52 + (h % 7) * 8
end

local function stampTallParcel(
	parent: Folder,
	namePrefix: string,
	cx: number,
	cz: number,
	footX: number,
	footZ: number,
	floorY: number
)
	if footX < 10 or footZ < 10 then
		return
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
		local h2 = h - 8
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
			Vector3.new(footX * 0.55, h - 12, footZ * 0.45),
			CFrame.new(cx - footX * 0.225, floorY + (h - 12) / 2, cz + footZ * 0.275),
			COLOR.brick,
			Enum.Material.Brick
		)
		part(
			parent,
			namePrefix .. "_Fill",
			Vector3.new(footX * 0.45, h - 20, footZ * 0.45),
			CFrame.new(cx + footX * 0.275, floorY + (h - 20) / 2, cz + footZ * 0.275),
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

	-- Reserved sites: safe-house yards + discrete ladder-snipe footprints
	-- + the single Market LOS blocker island (see stamp below).
	-- Spawns (Motorcade / Market) are ON the grid roads — no clearPad plaza needed.
	local clearPads = {
		{ x = -385, z = 0, hw = 44, hd = 38 }, -- Consulate yard (feeds from X=-400 / Z=0 roads)
		{ x = 385, z = 0, hw = 44, hd = 38 }, -- Precinct yard
		{ x = -150, z = -260, hw = 18, hd = 16 }, -- approach vantages
		{ x = 150, z = -260, hw = 18, hd = 16 },
		{ x = -280, z = -120, hw = 16, hd = 18 },
		{ x = 280, z = -120, hw = 16, hd = 18 },
		{ x = -64, z = -320, hw = 14, hd = 14 }, -- discrete ladder snipes
		{ x = 64, z = -320, hw = 14, hd = 14 },
		{ x = -96, z = -20, hw = 14, hd = 14 },
		{ x = 96, z = -20, hw = 14, hd = 14 },
		{ x = -48, z = -220, hw = 14, hd = 14 },
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
	----------------------------------------------------------------
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

				-- Skip parcels eaten by house yards / sniper pads / arterials.
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
							stampTallParcel(
								blocksFolder,
								"Block_" .. idx,
								sx,
								sz,
								subW,
								subD,
								floorY
							)
						end
					end
				else
					idx += 1
					stampTallParcel(blocksFolder, "Block_" .. idx, cx, cz, footX, footZ, floorY)
				end
			end
		end
	end

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

	-- Two rooftop + two window angles onto main routes; no dual-house oversights.
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

	-- Extra discrete sniper towers on selected parcels only (not every roof).
	-- Isolated decks + one ladder each — no rooftop connections.
	local sniperSites = {
		{
			name = "SniperMidWest",
			pos = Vector3.new(-64, 0, -320),
			facing = Vector3.new(1, 0, 0),
			floors = 5,
		},
		{
			name = "SniperMidEast",
			pos = Vector3.new(64, 0, -320),
			facing = Vector3.new(-1, 0, 0),
			floors = 5,
		},
		{
			name = "SniperMarketNW",
			pos = Vector3.new(-96, 0, -20),
			facing = Vector3.new(0, 0, -1),
			floors = 4,
		},
		{
			name = "SniperMarketNE",
			pos = Vector3.new(96, 0, -20),
			facing = Vector3.new(0, 0, -1),
			floors = 4,
		},
		{
			name = "SniperSouthBlvd",
			pos = Vector3.new(-48, 0, -220),
			facing = Vector3.new(1, 0, 0),
			floors = 4,
		},
	}
	for _, site in sniperSites do
		vantageBuilding(
			folder,
			site.name,
			site.pos,
			Vector3.new(26, 0, 26),
			site.floors,
			site.facing,
			site.facing
		)
	end
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
