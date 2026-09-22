--!strict
--[[
	Metric-correct greybox layout for VIP §7.

	All primary distances are PATH lengths along named waypoint ribbons
	(sum of consecutive segment magnitudes). Straight-line world placement
	is chosen so those ribbons land in the legal bands:

	  A↔B:           950–1100 path studs (target ~1000)
	  Contest radius R = SprintSpeed × CaptureDuration = 660
	  Furthest → nearest house ≤ 650 path
	  Good spawn → each house ~650 (±10%)
	  Terror spawn → each house ~500
	  Dual-contest midfield around Market

	Layout philosophy: Matthew’s dense city references — small flush parcels with
	tall towers (street canyons), only carved tactical corridors walkable. Ribbons
	mark Motorcade → mid → each house plus A↔B arterial; MapService fills every
	other plot with ≥52-stud massing so you cannot peek across low roofs.

	Rebuild the map when CaptureDuration or SprintSpeed change — those
	define R and invalidate this blockout (see GameConfig / design §7.2).
]]

local MapMetrics = {}

MapMetrics.FloorY = 0
MapMetrics.ContestRadius = 660 -- R = 22 × 30; keep in sync with GameConfig
MapMetrics.SeparationMin = 950
MapMetrics.SeparationMax = 1100
MapMetrics.SeparationTarget = 1000
MapMetrics.PathTolerance = 0.05 -- ±5% on primary ribbons

-- Anchor world positions (studs). Naming: Motorcade / Market / Consulate / Precinct.
MapMetrics.Anchors = {
	Consulate = {
		id = "Consulate",
		role = "SafeHouseA",
		safeHouseId = "A",
		position = Vector3.new(-385, 0, 0),
	},
	Precinct = {
		id = "Precinct",
		role = "SafeHouseB",
		safeHouseId = "B",
		position = Vector3.new(385, 0, 0),
	},
	Motorcade = {
		id = "Motorcade",
		role = "GoodSpawn",
		position = Vector3.new(0, 0, -500),
	},
	Market = {
		id = "Market",
		role = "TerrorSpawn",
		-- Midfield on the A–B midline (dual-contest band); ~450 from Motorcade.
		position = Vector3.new(0, 0, -50),
	},
}

-- Ordered path ribbons (horizontal; Y ignored in length). Targets from §7.4.
MapMetrics.Paths = {
	A_to_B = {
		name = "A_to_B",
		target = 1000,
		min = 950,
		max = 1100,
		-- Southern arterial around central plaza massing (forces ~1000 vs 770 straight).
		points = {
			Vector3.new(-385, 0, 0),
			Vector3.new(-250, 0, -200),
			Vector3.new(-80, 0, -280),
			Vector3.new(80, 0, -280),
			Vector3.new(250, 0, -200),
			Vector3.new(385, 0, 0),
		},
	},
	Good_to_A = {
		name = "Good_to_A",
		target = 650,
		min = 585, -- ±10%
		max = 715,
		points = {
			Vector3.new(0, 0, -500),
			Vector3.new(-120, 0, -350),
			Vector3.new(-250, 0, -180),
			Vector3.new(-385, 0, 0),
		},
	},
	Good_to_B = {
		name = "Good_to_B",
		target = 650,
		min = 585,
		max = 715,
		points = {
			Vector3.new(0, 0, -500),
			Vector3.new(120, 0, -350),
			Vector3.new(250, 0, -180),
			Vector3.new(385, 0, 0),
		},
	},
	Terror_to_A = {
		name = "Terror_to_A",
		target = 500,
		min = 450,
		max = 550,
		-- Northern pocket approach (around plaza massing).
		points = {
			Vector3.new(0, 0, -50),
			Vector3.new(-100, 0, 100),
			Vector3.new(-250, 0, 120),
			Vector3.new(-340, 0, 40),
			Vector3.new(-385, 0, 0),
		},
	},
	Terror_to_B = {
		name = "Terror_to_B",
		target = 500,
		min = 450,
		max = 550,
		points = {
			Vector3.new(0, 0, -50),
			Vector3.new(100, 0, 100),
			Vector3.new(250, 0, 120),
			Vector3.new(340, 0, 40),
			Vector3.new(385, 0, 0),
		},
	},
	Good_to_Terror = {
		name = "Good_to_Terror",
		target = 450,
		min = 400,
		max = 520,
		points = {
			Vector3.new(0, 0, -500),
			Vector3.new(0, 0, -280),
			Vector3.new(0, 0, -50),
		},
	},
}

function MapMetrics.pathLength(points: { Vector3 }): number
	local total = 0
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local dx = b.X - a.X
		local dz = b.Z - a.Z
		total += math.sqrt(dx * dx + dz * dz)
	end
	return total
end

function MapMetrics.straightLine(a: Vector3, b: Vector3): number
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	return math.sqrt(dx * dx + dz * dz)
end

export type PathReport = {
	name: string,
	length: number,
	target: number,
	min: number,
	max: number,
	ok: boolean,
}

function MapMetrics.measureAll(): { PathReport }
	local reports = {}
	for _, path in MapMetrics.Paths do
		local length = MapMetrics.pathLength(path.points)
		table.insert(reports, {
			name = path.name,
			length = length,
			target = path.target,
			min = path.min,
			max = path.max,
			ok = length >= path.min and length <= path.max,
		})
	end
	return reports
end

function MapMetrics.formatReport(reports: { PathReport }?): string
	local list = reports or MapMetrics.measureAll()
	local lines = {
		"VIP MapMetrics path report (horizontal path studs)",
		string.format(
			"Anchors: Consulate %s | Precinct %s | Motorcade %s | Market %s",
			tostring(MapMetrics.Anchors.Consulate.position),
			tostring(MapMetrics.Anchors.Precinct.position),
			tostring(MapMetrics.Anchors.Motorcade.position),
			tostring(MapMetrics.Anchors.Market.position)
		),
		string.format(
			"Straight A↔B: %.1f  |  Contest R: %d",
			MapMetrics.straightLine(
				MapMetrics.Anchors.Consulate.position,
				MapMetrics.Anchors.Precinct.position
			),
			MapMetrics.ContestRadius
		),
		"---",
	}
	local allOk = true
	for _, r in list do
		local mark = if r.ok then "OK" else "FAIL"
		if not r.ok then
			allOk = false
		end
		table.insert(
			lines,
			string.format(
				"[%s] %s = %.1f  (target %d, band %d–%d)",
				mark,
				r.name,
				r.length,
				r.target,
				r.min,
				r.max
			)
		)
	end
	table.insert(
		lines,
		if allOk then "RESULT: all primary paths in band" else "RESULT: FAIL — fix layout"
	)
	return table.concat(lines, "\n")
end

return MapMetrics
