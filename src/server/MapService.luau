--!strict
-- Builds the urban greybox at runtime so distances stay in GameConfig.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)

local MapService = {}

local mapFolder: Folder? = nil

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	anchored: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = if anchored == nil then true else anchored
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.Concrete
	p.Color = color
	p.Parent = parent
	return p
end

local function marker(parent: Instance, name: string, cframe: CFrame, color: Color3, text: string)
	local p = part(parent, name, Vector3.new(14, 1, 14), cframe, color, Enum.Material.Neon)
	p.CanCollide = false
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui
	return p
end

local function safeHouse(parent: Folder, id: string, center: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "SafeHouse" .. id
	folder.Parent = parent

	local cfg = GameConfig.Map
	local interior = cfg.HouseInteriorSize
	local floorY = cfg.FloorY

	-- Floor plate (visible capture boundary)
	local floor = part(
		folder,
		"Floor",
		Vector3.new(interior.X, 1, interior.Z),
		CFrame.new(center.X, floorY, center.Z),
		if id == "A" then Color3.fromRGB(40, 90, 140) else Color3.fromRGB(140, 70, 40),
		Enum.Material.Slate
	)

	-- Boundary stripe on top of floor
	local stripe = part(
		folder,
		"CaptureBoundary",
		Vector3.new(interior.X - 4, 0.2, interior.Z - 4),
		CFrame.new(center.X, floorY + 0.6, center.Z),
		Color3.fromRGB(255, 220, 60),
		Enum.Material.Neon
	)
	stripe.CanCollide = false

	-- Walls with two entrances (gaps on +Z and -X)
	local wallH = interior.Y
	local wallT = 2
	local halfX = interior.X / 2
	local halfZ = interior.Z / 2

	part(
		folder,
		"WallNorth",
		Vector3.new(interior.X, wallH, wallT),
		CFrame.new(center.X, floorY + wallH / 2, center.Z - halfZ),
		Color3.fromRGB(70, 70, 75)
	)
	-- South wall split for doorway
	part(
		folder,
		"WallSouthL",
		Vector3.new(interior.X * 0.35, wallH, wallT),
		CFrame.new(center.X - halfX * 0.55, floorY + wallH / 2, center.Z + halfZ),
		Color3.fromRGB(70, 70, 75)
	)
	part(
		folder,
		"WallSouthR",
		Vector3.new(interior.X * 0.35, wallH, wallT),
		CFrame.new(center.X + halfX * 0.55, floorY + wallH / 2, center.Z + halfZ),
		Color3.fromRGB(70, 70, 75)
	)
	part(
		folder,
		"WallEast",
		Vector3.new(wallT, wallH, interior.Z),
		CFrame.new(center.X + halfX, floorY + wallH / 2, center.Z),
		Color3.fromRGB(70, 70, 75)
	)
	-- West wall split for second entrance
	part(
		folder,
		"WallWestN",
		Vector3.new(wallT, wallH, interior.Z * 0.35),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z - halfZ * 0.55),
		Color3.fromRGB(70, 70, 75)
	)
	part(
		folder,
		"WallWestS",
		Vector3.new(wallT, wallH, interior.Z * 0.35),
		CFrame.new(center.X - halfX, floorY + wallH / 2, center.Z + halfZ * 0.55),
		Color3.fromRGB(70, 70, 75)
	)

	-- Interior cover
	part(
		folder,
		"CoverA",
		Vector3.new(10, 8, 3),
		CFrame.new(center.X - 12, floorY + 4, center.Z - 8),
		Color3.fromRGB(90, 90, 95)
	)
	part(
		folder,
		"CoverB",
		Vector3.new(3, 8, 12),
		CFrame.new(center.X + 14, floorY + 4, center.Z + 6),
		Color3.fromRGB(90, 90, 95)
	)

	-- Capture volume (generous, non-colliding)
	local volume = part(
		folder,
		"CaptureVolume",
		cfg.CaptureSize,
		CFrame.new(center.X, floorY + cfg.CaptureSize.Y / 2, center.Z),
		Color3.fromRGB(80, 200, 120),
		Enum.Material.ForceField
	)
	volume.Transparency = 0.85
	volume.CanCollide = false
	volume:SetAttribute("SafeHouseId", id)

	floor:SetAttribute("SafeHouseId", id)
	return folder
end

local function building(
	parent: Folder,
	name: string,
	base: Vector3,
	footprint: Vector3,
	floors: number,
	windowFacing: Vector3?
)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	local floorH = 14
	local totalH = floors * floorH
	part(
		folder,
		"Shell",
		Vector3.new(footprint.X, totalH, footprint.Z),
		CFrame.new(base.X, GameConfig.Map.FloorY + totalH / 2, base.Z),
		Color3.fromRGB(95, 95, 100),
		Enum.Material.Brick
	)

	-- Rooftop deck (slightly inset, walkable)
	local roof = part(
		folder,
		"Rooftop",
		Vector3.new(footprint.X - 2, 1, footprint.Z - 2),
		CFrame.new(base.X, GameConfig.Map.FloorY + totalH + 0.5, base.Z),
		Color3.fromRGB(60, 60, 65),
		Enum.Material.Metal
	)

	-- Simple stair stack on one side
	for i = 1, floors do
		part(
			folder,
			"Stair" .. i,
			Vector3.new(6, 1, 10),
			CFrame.new(
				base.X + footprint.X / 2 + 4,
				GameConfig.Map.FloorY + (i - 0.5) * floorH,
				base.Z
			),
			Color3.fromRGB(110, 110, 115)
		)
	end

	if windowFacing then
		local win = part(
			folder,
			"WindowAngle",
			Vector3.new(8, 6, 1),
			CFrame.new(
				base.X + windowFacing.X * (footprint.X / 2 + 0.6),
				GameConfig.Map.FloorY + floorH * 1.2,
				base.Z + windowFacing.Z * (footprint.Z / 2 + 0.6)
			),
			Color3.fromRGB(140, 190, 220),
			Enum.Material.Glass
		)
		win.CanCollide = false
		win.Transparency = 0.4
	end

	return roof
end

function MapService.build()
	local existing = Workspace:FindFirstChild("VIPMap")
	if existing then
		existing:Destroy()
	end

	-- Hide default baseplate spawn if present; we use VIP markers.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Size = Vector3.new(1200, 2, 900)
		baseplate.Position = Vector3.new(0, -1, -100)
		baseplate.Color = Color3.fromRGB(55, 58, 62)
		baseplate.Material = Enum.Material.Asphalt
	end

	local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn and defaultSpawn:IsA("SpawnLocation") then
		defaultSpawn.Enabled = false
		defaultSpawn.Transparency = 1
	end

	local folder = Instance.new("Folder")
	folder.Name = "VIPMap"
	folder.Parent = Workspace
	mapFolder = folder

	local half = GameConfig.Map.HouseHalfSeparation
	local floorY = GameConfig.Map.FloorY

	local aCenter = Vector3.new(-half, floorY, 0)
	local bCenter = Vector3.new(half, floorY, 0)

	safeHouse(folder, Enums.SafeHouseId.A, aCenter)
	safeHouse(folder, Enums.SafeHouseId.B, bCenter)

	marker(
		folder,
		"SpawnGood",
		CFrame.new(0, floorY + 0.5, GameConfig.Map.GoodSpawnZ),
		Color3.fromRGB(50, 120, 220),
		"MOTORCADE (Good)"
	)
	marker(
		folder,
		"SpawnTerrorist",
		CFrame.new(0, floorY + 0.5, GameConfig.Map.TerroristSpawnZ),
		Color3.fromRGB(200, 70, 60),
		"MARKET (Terrorists)"
	)

	-- Midfield blocks / chokes
	part(
		folder,
		"MarketStallA",
		Vector3.new(30, 10, 12),
		CFrame.new(-80, floorY + 5, -120),
		Color3.fromRGB(150, 120, 80),
		Enum.Material.Wood
	)
	part(
		folder,
		"MarketStallB",
		Vector3.new(30, 10, 12),
		CFrame.new(90, floorY + 5, -90),
		Color3.fromRGB(150, 120, 80),
		Enum.Material.Wood
	)
	part(
		folder,
		"AlleyChoke",
		Vector3.new(18, 16, 40),
		CFrame.new(0, floorY + 8, -220),
		Color3.fromRGB(80, 80, 85)
	)

	-- Overhead covered stretch (arcade)
	for i = -3, 3 do
		part(
			folder,
			"ArcadePillar" .. i,
			Vector3.new(3, 14, 3),
			CFrame.new(i * 18, floorY + 7, -300),
			Color3.fromRGB(100, 100, 105)
		)
	end
	part(
		folder,
		"ArcadeRoof",
		Vector3.new(130, 2, 24),
		CFrame.new(0, floorY + 15, -300),
		Color3.fromRGB(90, 85, 80),
		Enum.Material.Metal
	)

	-- Verticality: rooftops + window angles onto main routes
	building(
		folder,
		"BuildingWest",
		Vector3.new(-160, 0, -180),
		Vector3.new(40, 0, 36),
		2,
		Vector3.new(1, 0, 0)
	)
	building(
		folder,
		"BuildingEast",
		Vector3.new(170, 0, -160),
		Vector3.new(40, 0, 36),
		2,
		Vector3.new(-1, 0, 0)
	)
	building(
		folder,
		"BuildingNearA",
		Vector3.new(-280, 0, -80),
		Vector3.new(36, 0, 40),
		3,
		Vector3.new(0, 0, 1)
	)
	building(
		folder,
		"BuildingNearB",
		Vector3.new(290, 0, -70),
		Vector3.new(36, 0, 40),
		3,
		Vector3.new(0, 0, 1)
	)

	-- Low cover along escort routes
	for i = 1, 6 do
		local z = GameConfig.Map.GoodSpawnZ + i * 70
		part(
			folder,
			"RouteCoverL" .. i,
			Vector3.new(12, 5, 4),
			CFrame.new(-40, floorY + 2.5, z),
			Color3.fromRGB(85, 85, 90)
		)
		part(
			folder,
			"RouteCoverR" .. i,
			Vector3.new(12, 5, 4),
			CFrame.new(40, floorY + 2.5, z),
			Color3.fromRGB(85, 85, 90)
		)
	end

	print("[MapService] VIP greybox built (SafeHouse A/B, Motorcade, Market, rooftops).")
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
	local z = if side == Enums.Side.Good
		then GameConfig.Map.GoodSpawnZ
		else GameConfig.Map.TerroristSpawnZ
	local xSpread = if side == Enums.Side.Good then 20 else 24
	return CFrame.new((math.random() - 0.5) * xSpread, GameConfig.Map.FloorY + 4, z)
end

function MapService.pointInPart(point: Vector3, volume: BasePart): boolean
	local localPoint = volume.CFrame:PointToObjectSpace(point)
	local half = volume.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

return MapService
