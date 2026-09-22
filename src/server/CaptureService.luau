--!strict
--[[
	Capture rules (confirmed):
	- Progress only while President is inside a volume
	- Resets to 0 the instant he leaves alive
	- Entry viability checked once: need remaining round time > CaptureDuration (t=270)
	- Late entry: no progress, no alert (TOO_LATE)
	- Round timer is owned elsewhere and never pauses
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(script.Parent.Remotes)
local MapService = require(script.Parent.MapService)
local TeamService = require(script.Parent.TeamService)

local CaptureService = {}

local active = false
local state = Enums.CaptureState.Idle
local safeHouseId: string? = nil
local captureRemaining = 0
local completed = false
local lastEntryWarned = false
local getRoundRemaining: (() -> number)? = nil
local onCaptureCompleted: (() -> ())? = nil
local heartbeatConn: RBXScriptConnection? = nil
local replicateAccum = 0

local function snapshot()
	local progress = 0
	if state == Enums.CaptureState.Active and GameConfig.CaptureDurationSeconds > 0 then
		progress = 1 - (captureRemaining / GameConfig.CaptureDurationSeconds)
	end
	return {
		state = state,
		safeHouseId = safeHouseId,
		timeRemaining = math.max(captureRemaining, 0),
		progress = math.clamp(progress, 0, 1),
	}
end

local function broadcast()
	Remotes.get(Net.CaptureState):FireAllClients(snapshot())
end

local function setState(newState: string, house: string?)
	state = newState
	if house ~= nil then
		safeHouseId = house
	end
	broadcast()
end

local function presidentRootPosition(): Vector3?
	local prez = TeamService.getPresident()
	if not prez then
		return nil
	end
	local character = prez.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root.Position
end

local function houseContaining(point: Vector3): string?
	for _, id in { Enums.SafeHouseId.A, Enums.SafeHouseId.B } do
		local volume = MapService.getCaptureVolume(id)
		if volume and MapService.pointInPart(point, volume) then
			return id
		end
	end
	return nil
end

function CaptureService.setRoundRemainingGetter(getter: () -> number)
	getRoundRemaining = getter
end

function CaptureService.setCompletedCallback(callback: () -> ())
	onCaptureCompleted = callback
end

function CaptureService.reset()
	active = false
	state = Enums.CaptureState.Idle
	safeHouseId = nil
	captureRemaining = 0
	completed = false
	lastEntryWarned = false
	replicateAccum = 0
	broadcast()
end

function CaptureService.isComplete(): boolean
	return completed
end

function CaptureService.getState(): string
	return state
end

function CaptureService.isActive(): boolean
	return state == Enums.CaptureState.Active
end

function CaptureService.startMonitoring()
	CaptureService.reset()
	active = true
end

function CaptureService.stopMonitoring()
	active = false
end

local function breakCapture(reasonState: string)
	captureRemaining = 0
	safeHouseId = nil
	setState(reasonState, nil)
	-- Return to idle shortly so HUD clears the broken banner.
	task.delay(1.2, function()
		if not active then
			return
		end
		if state == reasonState then
			setState(Enums.CaptureState.Idle, nil)
		end
	end)
end

function CaptureService.step(dt: number)
	if not active then
		return
	end
	if completed then
		return
	end

	local remaining = if getRoundRemaining then getRoundRemaining() else 0

	-- Deadline UI cue (shared): 5s before last viable entry
	if
		remaining <= GameConfig.LastEntryWarningRemaining
		and remaining > GameConfig.CaptureEntryDeadlineRemaining
	then
		if not lastEntryWarned then
			lastEntryWarned = true
			Remotes.get(Net.HudBanner):FireAllClients({
				text = "LAST ENTRY — 5s  |  CAPTURE WINDOW CLOSING",
				kind = "warning",
			})
		end
	end

	local pos = presidentRootPosition()
	local insideId = if pos then houseContaining(pos) else nil

	if state == Enums.CaptureState.Active then
		if insideId == nil or insideId ~= safeHouseId then
			-- President left: reset to zero (confirmed).
			breakCapture(Enums.CaptureState.Broken)
			Remotes.get(Net.HudBanner):FireAllClients({
				text = "CAPTURE BROKEN — progress reset",
				kind = "break",
			})
			return
		end

		captureRemaining -= dt
		if captureRemaining <= 0 then
			captureRemaining = 0
			completed = true
			setState(Enums.CaptureState.Complete, safeHouseId)
			if onCaptureCompleted then
				onCaptureCompleted()
			end
			return
		end

		replicateAccum += dt
		if replicateAccum >= 0.2 then
			replicateAccum = 0
			broadcast()
		end
		return
	end

	-- Not active: maybe start
	if insideId then
		-- Viability checked once on entry: need STRICTLY more than 30s remaining.
		if remaining > GameConfig.CaptureEntryDeadlineRemaining then
			safeHouseId = insideId
			captureRemaining = GameConfig.CaptureDurationSeconds
			setState(Enums.CaptureState.Active, insideId)
			Remotes.get(Net.HudBanner):FireAllClients({
				text = string.format(
					"PRESIDENT IN SAFE HOUSE %s — %02d",
					insideId,
					GameConfig.CaptureDurationSeconds
				),
				kind = "capture",
			})
		else
			-- Too late: no progress, no terrorist alert.
			if state ~= Enums.CaptureState.TooLate then
				setState(Enums.CaptureState.TooLate, insideId)
				Remotes.get(Net.HudBanner):FireAllClients({
					text = "TOO LATE — capture no longer possible",
					kind = "warning",
				})
			end
		end
	elseif state == Enums.CaptureState.TooLate then
		setState(Enums.CaptureState.Idle, nil)
	end
end

function CaptureService.init()
	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		CaptureService.step(dt)
	end)
	broadcast()
end

return CaptureService
