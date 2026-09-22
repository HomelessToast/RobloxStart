--!strict
--[[
	Validates MapMetrics path ribbons against §7.4 bands.
	Runs at server start after MapService.build(); prints a report and
	stores pass/fail on Workspace.VIPMap.MapMetricsReport.

	This is a layout harness, not a gameplay authority check.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapMetrics = require(ReplicatedStorage.Shared.MapMetrics)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapValidator = {}

function MapValidator.validate(): (boolean, string)
	local reports = MapMetrics.measureAll()
	local text = MapMetrics.formatReport(reports)

	-- Cross-check R against live GameConfig (catch drift).
	local expectedR = GameConfig.SprintSpeed * GameConfig.CaptureDurationSeconds
	if expectedR ~= MapMetrics.ContestRadius then
		text ..= string.format(
			"\n[FAIL] ContestRadius drift: MapMetrics=%d GameConfig R=%d (sprint×capture)",
			MapMetrics.ContestRadius,
			expectedR
		)
		return false, text
	end

	local allOk = true
	for _, r in reports do
		if not r.ok then
			allOk = false
			break
		end
	end

	-- Straight-line A↔B should be shorter than path (urban friction).
	local straight = MapMetrics.straightLine(
		MapMetrics.Anchors.Consulate.position,
		MapMetrics.Anchors.Precinct.position
	)
	local aToB = MapMetrics.pathLength(MapMetrics.Paths.A_to_B.points)
	if straight >= aToB then
		text ..= "\n[FAIL] A↔B straight-line >= path length — massing should force a longer ribbon"
		allOk = false
	else
		text ..= string.format(
			"\n[OK] Urban friction A↔B: straight %.1f → path %.1f (×%.2f)",
			straight,
			aToB,
			aToB / straight
		)
	end

	return allOk, text
end

function MapValidator.runAndPrint()
	local ok, text = MapValidator.validate()
	if ok then
		print("[MapValidator] PASS\n" .. text)
	else
		warn("[MapValidator] FAIL\n" .. text)
	end
	return ok
end

return MapValidator
