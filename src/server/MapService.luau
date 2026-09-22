--!strict
--[[
	Builds the metric-correct urban greybox from MapMetrics.

	Layout philosophy (Matthew feedback): dense city grid + CS2/Valorant lanes —
	few meaningful routes with chokepoints that matter; no large empty plazas.
	Metric ribbons in MapMetrics stay the distance source of truth.

	Gameplay wiring (unchanged contracts):
	- Workspace.VIPMap / SafeHouseA|B / CaptureVolume (+ SafeHouseId attribute)
	- MapService.getCaptureVolume / getSpawnCFrame / pointInPart

	Also: MapAnchor tags, CaptureBoundary markers, costly choke bypasses,
	elevated vantages (gapped roofs), overhead arcade, no lethal VIP falls.
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

--[[
	Dense city grid + CS2/Valorant lane philosophy:
	- Fill the footprint with building blocks; carve only named street/alley corridors.
	- Few meaningful routes Motorcade → mid → each house (not open-field plazas).
	- Every choke has a bypass that is longer/narrower (costly), never a free highway.
	- Rooftops stay gapped (vantage buildings elsewhere); no continuous roof rotate.
]]

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
	part(parent, name, Vector3.new(10, 5, 3.5), cf, COLOR.cover)
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

	-- Primary tactical lanes (half-widths). Path ribbons stay the measurement source;
	-- these corridors are the playable carve so free plaza crossing is gone.
	local laneHalf = {
		primary = 13, -- ~26 stud street (smokeable choke width)
		approach = 12,
		arterial = 14, -- southern A↔B boulevard
		alley = 7, -- costly bypass (~14 studs)
		crossover = 10,
	}

	local paths = MapMetrics.Paths
	local goodToA = paths.Good_to_A.points
	local goodToB = paths.Good_to_B.points
	local terrorToA = paths.Terror_to_A.points
	local terrorToB = paths.Terror_to_B.points
	local aToB = paths.A_to_B.points
	local midLane = paths.Good_to_Terror.points

	-- Extra orthogonal connectors / costly alleys (not primary measurement ribbons).
	local westBypass = {
		Vector3.new(-220, 0, -480),
		Vector3.new(-220, 0, -300),
		Vector3.new(-220, 0, -160),
		Vector3.new(-300, 0, -80),
		Vector3.new(-340, 0, -20),
	}
	local eastBypass = {
		Vector3.new(220, 0, -480),
		Vector3.new(220, 0, -300),
		Vector3.new(220, 0, -160),
		Vector3.new(300, 0, -80),
		Vector3.new(340, 0, -20),
	}
	local earlyCrossover = {
		Vector3.new(-120, 0, -380),
		Vector3.new(0, 0, -380),
		Vector3.new(120, 0, -380),
	}
	local lateCrossover = {
		Vector3.new(-160, 0, -160),
		Vector3.new(0, 0, -160),
		Vector3.new(160, 0, -160),
	}
	-- Northern pocket link (Market → house approaches without open field)
	local northLink = {
		Vector3.new(-200, 0, 100),
		Vector3.new(0, 0, 100),
		Vector3.new(200, 0, 100),
	}

	local clearPads = {
		{ x = 0, z = -500, hw = 28, hd = 28 }, -- Motorcade
		{ x = 0, z = -50, hw = 30, hd = 30 }, -- Market
		{ x = -385, z = 0, hw = 48, hd = 42 }, -- Consulate yard
		{ x = 385, z = 0, hw = 48, hd = 42 }, -- Precinct yard
		-- Vantage footprints (buildings placed after massing)
		{ x = -150, z = -260, hw = 28, hd = 26 },
		{ x = 150, z = -260, hw = 28, hd = 26 },
		{ x = -280, z = -120, hw = 26, hd = 28 },
		{ x = 280, z = -120, hw = 26, hd = 28 },
	}

	local function isPlayableCorridor(px: number, pz: number): boolean
		for _, pad in clearPads do
			if inRect(px, pz, pad.x, pad.z, pad.hw, pad.hd) then
				return true
			end
		end
		if nearPolyline(px, pz, midLane, laneHalf.primary) then
			return true
		end
		if nearPolyline(px, pz, goodToA, laneHalf.approach) then
			return true
		end
		if nearPolyline(px, pz, goodToB, laneHalf.approach) then
			return true
		end
		if nearPolyline(px, pz, aToB, laneHalf.arterial) then
			return true
		end
		if nearPolyline(px, pz, terrorToA, laneHalf.approach) then
			return true
		end
		if nearPolyline(px, pz, terrorToB, laneHalf.approach) then
			return true
		end
		if nearPolyline(px, pz, westBypass, laneHalf.alley) then
			return true
		end
		if nearPolyline(px, pz, eastBypass, laneHalf.alley) then
			return true
		end
		if nearPolyline(px, pz, earlyCrossover, laneHalf.crossover) then
			return true
		end
		if nearPolyline(px, pz, lateCrossover, laneHalf.crossover) then
			return true
		end
		if nearPolyline(px, pz, northLink, laneHalf.crossover) then
			return true
		end
		return false
	end

	-- Stamp dense blocks across the footprint; only carved corridors stay open.
	local pitch = 52
	local blockSize = 40
	local idx = 0
	for x = -400, 400, pitch do
		for z = -500, 160, pitch do
			if not isPlayableCorridor(x, z) then
				idx += 1
				-- Pseudo-random height from position (stable across rebuilds)
				local h = 16 + ((math.abs(x) + math.abs(z) * 3) % 5) * 4
				local brickish = ((x + z) % (pitch * 2)) == 0
				part(
					blocksFolder,
					"Block_" .. idx,
					Vector3.new(blockSize, h, blockSize),
					CFrame.new(x, floorY + h / 2, z),
					if brickish then COLOR.brick else COLOR.concrete,
					if brickish then Enum.Material.Brick else Enum.Material.Concrete
				)
				-- Corner interior / cover nook on street-facing edges (every other block)
				if idx % 2 == 0 then
					local nookX = x + (if x < 0 then blockSize / 2 + 4 else -(blockSize / 2 + 4))
					local nookZ = z
					if isPlayableCorridor(nookX, nookZ) then
						part(
							blocksFolder,
							"CornerCover_" .. idx,
							Vector3.new(8, 6, 8),
							CFrame.new(nookX, floorY + 3, nookZ),
							COLOR.cover
						)
					end
				end
			end
		end
	end

	-- Mid hub side masses: pinch Market into a lane (leave center avenue open).
	part(
		lanesFolder,
		"MarketHubN",
		Vector3.new(70, 22, 36),
		CFrame.new(0, floorY + 11, 40),
		COLOR.brick,
		Enum.Material.Brick
	)
	part(
		lanesFolder,
		"MarketHubSW",
		Vector3.new(36, 18, 40),
		CFrame.new(-42, floorY + 9, -110),
		COLOR.concrete
	)
	part(
		lanesFolder,
		"MarketHubSE",
		Vector3.new(36, 18, 40),
		CFrame.new(42, floorY + 9, -110),
		COLOR.concrete
	)

	-- Center canal choke (~24 stud opening) on Motorcade→Market lane
	part(
		lanesFolder,
		"CanalBridgeChokeL",
		Vector3.new(36, 16, 26),
		CFrame.new(-30, floorY + 8, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"CanalBridgeChokeR",
		Vector3.new(36, 16, 26),
		CFrame.new(30, floorY + 8, -300),
		COLOR.choke
	)
	part(
		lanesFolder,
		"CanalDeck",
		Vector3.new(24, 1, 32),
		CFrame.new(0, floorY + 0.5, -300),
		COLOR.asphalt,
		Enum.Material.Asphalt
	)

	-- West approach choke (~26 stud gap on Good→Consulate lane) + longer western alley bypass
	part(
		lanesFolder,
		"WestLaneChokeL",
		Vector3.new(28, 18, 22),
		CFrame.new(-212, floorY + 9, -265),
		COLOR.choke
	)
	part(
		lanesFolder,
		"WestLaneChokeR",
		Vector3.new(28, 18, 22),
		CFrame.new(-158, floorY + 9, -265),
		COLOR.choke
	)
	part(
		lanesFolder,
		"WestBypassGapMarker",
		Vector3.new(12, 0.3, 70),
		CFrame.new(-220, floorY + 0.2, -265),
		COLOR.path,
		Enum.Material.Neon,
		false
	)

	-- East approach choke + costly eastern alley bypass
	part(
		lanesFolder,
		"EastLaneChokeL",
		Vector3.new(28, 18, 22),
		CFrame.new(158, floorY + 9, -265),
		COLOR.choke
	)
	part(
		lanesFolder,
		"EastLaneChokeR",
		Vector3.new(28, 18, 22),
		CFrame.new(212, floorY + 9, -265),
		COLOR.choke
	)
	part(
		lanesFolder,
		"EastBypassGapMarker",
		Vector3.new(12, 0.3, 70),
		CFrame.new(220, floorY + 0.2, -265),
		COLOR.path,
		Enum.Material.Neon,
		false
	)

	-- Southern arterial pinch points on Consulate↔Precinct boulevard (away from canal mid)
	part(
		lanesFolder,
		"SouthBlvdChokeW",
		Vector3.new(36, 14, 24),
		CFrame.new(-200, floorY + 7, -250),
		COLOR.choke
	)
	part(
		lanesFolder,
		"SouthBlvdChokeE",
		Vector3.new(36, 14, 24),
		CFrame.new(200, floorY + 7, -250),
		COLOR.choke
	)

	-- Decision wedges (~200–250 from each house): commit past these costs a long rotate
	part(
		lanesFolder,
		"DecisionA",
		Vector3.new(32, 14, 32),
		CFrame.new(-210, floorY + 7, -50),
		COLOR.wood,
		Enum.Material.Wood
	)
	part(
		lanesFolder,
		"DecisionB",
		Vector3.new(32, 14, 32),
		CFrame.new(210, floorY + 7, -50),
		COLOR.wood,
		Enum.Material.Wood
	)

	-- Overhead arcade on primary center route (required §7.5 cover from above)
	for i = -3, 3 do
		part(
			lanesFolder,
			"ArcadePillar" .. i,
			Vector3.new(3, 14, 3),
			CFrame.new(i * 14, floorY + 7, -340),
			COLOR.concrete
		)
	end
	part(
		lanesFolder,
		"ArcadeRoof",
		Vector3.new(100, 2, 26),
		CFrame.new(0, floorY + 15, -340),
		COLOR.metal,
		Enum.Material.Metal
	)

	-- Street cover cadence along the three macro routes (≤60 stud open gaps)
	for i = 1, 8 do
		local z = -480 + i * 50
		streetCover(lanesFolder, -18, z, "MidCoverL" .. i)
		streetCover(lanesFolder, 18, z, "MidCoverR" .. i)
	end
	for i = 1, 5 do
		local t = i / 6
		local ax = goodToA[1].X + (goodToA[#goodToA].X - goodToA[1].X) * t
		local az = goodToA[1].Z + (goodToA[#goodToA].Z - goodToA[1].Z) * t
		local bx = goodToB[1].X + (goodToB[#goodToB].X - goodToB[1].X) * t
		local bz = goodToB[1].Z + (goodToB[#goodToB].Z - goodToB[1].Z) * t
		streetCover(lanesFolder, ax + 14, az, "WestLaneCover" .. i, 0.4)
		streetCover(lanesFolder, bx - 14, bz, "EastLaneCover" .. i, -0.4)
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
