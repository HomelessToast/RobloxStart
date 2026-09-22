--!strict
--[[
	Sprint stamina + Q dodge/roll for every character.

	Client sends SprintIntent / DodgeRequest; server owns stamina, cooldown,
	WalkSpeed, and the roll travel. Dodge keeps HumanoidRootPart upright
	(AlignOrientation) and drives XZ from a locked startPos each Heartbeat
	under server network ownership — exit CFrame uses the final slide sample
	(never a stale pre-dodge Position). Client plays the somersault AnimationTrack
	from MovementState.dodging. Design §5.3 originally reserved the roll for the
	President — this slice unifies Q dodge for all roles (see docs/vip-movement.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local Remotes = require(script.Parent.Remotes)
local SpawnService = require(script.Parent.SpawnService)
local TeamService = require(script.Parent.TeamService)

type Runtime = {
	stamina: number,
	wantSprint: boolean,
	sprinting: boolean,
	regenDelay: number,
	dodgeCooldown: number,
	dodgeUntil: number,
	recoveryUntil: number,
	dodgeConn: RBXScriptConnection?,
	dodgeAttachment: Attachment?,
	dodgeVelocity: LinearVelocity?,
	dodgeAlign: AlignOrientation?,
	savedJumpPower: number?,
	savedJumpHeight: number?,
	lastPush: number,
	lastStaminaSent: number,
	lastCooldownSent: number,
}

local AbilityService = {}

local byPlayer: { [Player]: Runtime } = {}
local heartbeatConn: RBXScriptConnection? = nil

local function cfgSprint()
	return GameConfig.Sprint
end

local function cfgDodge()
	return GameConfig.Dodge
end

local function nowClock(): number
	return os.clock()
end

local function getRuntime(player: Player): Runtime
	local rt = byPlayer[player]
	if not rt then
		rt = {
			stamina = cfgSprint().MaxStamina,
			wantSprint = false,
			sprinting = false,
			regenDelay = 0,
			dodgeCooldown = 0,
			dodgeUntil = 0,
			recoveryUntil = 0,
			dodgeConn = nil,
			dodgeAttachment = nil,
			dodgeVelocity = nil,
			dodgeAlign = nil,
			savedJumpPower = nil,
			savedJumpHeight = nil,
			lastPush = 0,
			lastStaminaSent = -1,
			lastCooldownSent = -1,
		}
		byPlayer[player] = rt
	end
	return rt
end

local function isDodging(rt: Runtime): boolean
	return nowClock() < rt.dodgeUntil
end

local function inRecovery(rt: Runtime): boolean
	return nowClock() < rt.recoveryUntil
end

function AbilityService.isSprinting(player: Player): boolean
	local rt = byPlayer[player]
	return rt ~= nil and rt.sprinting
end

function AbilityService.isDodging(player: Player): boolean
	local rt = byPlayer[player]
	return rt ~= nil and isDodging(rt)
end

function AbilityService.canFire(player: Player): boolean
	local rt = byPlayer[player]
	if not rt then
		return true
	end
	if rt.sprinting then
		return false
	end
	if isDodging(rt) or inRecovery(rt) then
		return false
	end
	return true
end

function AbilityService.push(player: Player, force: boolean?)
	local rt = getRuntime(player)
	local t = nowClock()
	local cooldownLeft = math.max(0, rt.dodgeCooldown - t)
	local staminaRounded = math.floor(rt.stamina * 10 + 0.5) / 10
	local cooldownRounded = math.floor(cooldownLeft * 10 + 0.5) / 10
	if
		not force
		and t - rt.lastPush < 0.08
		and math.abs(staminaRounded - rt.lastStaminaSent) < 0.5
		and math.abs(cooldownRounded - rt.lastCooldownSent) < 0.15
		and not isDodging(rt)
	then
		return
	end
	rt.lastPush = t
	rt.lastStaminaSent = staminaRounded
	rt.lastCooldownSent = cooldownRounded
	Remotes.get(Net.MovementState):FireClient(player, {
		stamina = rt.stamina,
		maxStamina = cfgSprint().MaxStamina,
		sprinting = rt.sprinting,
		dodgeCooldownRemaining = cooldownLeft,
		dodging = isDodging(rt),
		canFire = AbilityService.canFire(player),
	})
end

local function clearDodgeConn(rt: Runtime)
	if rt.dodgeConn then
		rt.dodgeConn:Disconnect()
		rt.dodgeConn = nil
	end
end

local function destroyDodgeConstraints(rt: Runtime)
	if rt.dodgeVelocity then
		rt.dodgeVelocity:Destroy()
		rt.dodgeVelocity = nil
	end
	if rt.dodgeAlign then
		rt.dodgeAlign:Destroy()
		rt.dodgeAlign = nil
	end
	if rt.dodgeAttachment then
		rt.dodgeAttachment:Destroy()
		rt.dodgeAttachment = nil
	end
end

local function trySetNetworkOwner(root: BasePart, owner: Player?)
	pcall(function()
		root:SetNetworkOwner(owner)
	end)
end

--- XZ slide target from locked origin; preserves Y from the live root (gravity/steps).
local function slidePosition(
	startPos: Vector3,
	flat: Vector3,
	traveled: number,
	liveY: number
): Vector3
	local planar = startPos + flat * traveled
	return Vector3.new(planar.X, liveY, planar.Z)
end

local function setDodgeRagdollGuards(humanoid: Humanoid, enabled: boolean)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, enabled)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, enabled)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, enabled)
end

local function restoreHumanoidAfterDodge(
	_player: Player,
	humanoid: Humanoid,
	savedJumpPower: number,
	savedJumpHeight: number
)
	humanoid.AutoRotate = true
	humanoid.PlatformStand = false
	humanoid.JumpPower = savedJumpPower
	humanoid.JumpHeight = savedJumpHeight
	setDodgeRagdollGuards(humanoid, true)
	if humanoid.Health > 0 then
		-- Stay in locomotion — do not GettingUp (that was for Physics tumbles).
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function stopDodge(player: Player, rt: Runtime)
	clearDodgeConn(rt)
	destroyDodgeConstraints(rt)
	rt.dodgeUntil = 0
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyAngularVelocity = Vector3.zero
			trySetNetworkOwner(root, player)
		end
		if humanoid then
			humanoid.AutoRotate = true
			humanoid.PlatformStand = false
			setDodgeRagdollGuards(humanoid, true)
			if rt.savedJumpPower ~= nil then
				humanoid.JumpPower = rt.savedJumpPower
			end
			if rt.savedJumpHeight ~= nil then
				humanoid.JumpHeight = rt.savedJumpHeight
			end
		end
	end
	rt.savedJumpPower = nil
	rt.savedJumpHeight = nil
end

--- Flat forward unit from move intent, else facing. Nil if neither is usable.
local function resolveDodgeFlat(humanoid: Humanoid, root: BasePart): Vector3?
	local move = humanoid.MoveDirection
	local flat = Vector3.new(move.X, 0, move.Z)
	if flat.Magnitude < 0.12 then
		local look = root.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude < 0.05 then
		return nil
	end
	return flat.Unit
end

local function uprightCFrame(position: Vector3, flat: Vector3): CFrame
	return CFrame.lookAt(position, position + flat)
end

local function facingCFrame(flat: Vector3): CFrame
	return CFrame.lookAt(Vector3.zero, flat)
end

function AbilityService.cancelSprint(player: Player)
	local rt = getRuntime(player)
	rt.wantSprint = false
	rt.sprinting = false
	if not SpawnService.isFrozen(player) then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and not isDodging(rt) then
			humanoid.WalkSpeed = GameConfig.WalkSpeed
		end
	end
end

function AbilityService.resetForRound(player: Player)
	local rt = getRuntime(player)
	stopDodge(player, rt)
	rt.stamina = cfgSprint().MaxStamina
	rt.wantSprint = false
	rt.sprinting = false
	rt.regenDelay = 0
	rt.dodgeCooldown = 0
	rt.recoveryUntil = 0
	AbilityService.push(player, true)
end

function AbilityService.resetAllForRound()
	for _, player in Players:GetPlayers() do
		AbilityService.resetForRound(player)
	end
end

--- Cancel active sprint/dodge (e.g. entering BUY freeze or round end resolution).
function AbilityService.interruptAll()
	for player, rt in byPlayer do
		rt.wantSprint = false
		rt.sprinting = false
		stopDodge(player, rt)
		if not SpawnService.isFrozen(player) then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = GameConfig.WalkSpeed
			end
		end
		AbilityService.push(player, true)
	end
end

local function canUseAbilities(player: Player): boolean
	if SpawnService.isFrozen(player) then
		return false
	end
	return TeamService.hasLivingBody(player)
end

local function isGrounded(character: Model, root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local hit =
		Workspace:Raycast(root.Position, Vector3.new(0, -cfgDodge().GroundRayLength, 0), params)
	return hit ~= nil
end

local function applyWalkSpeed(player: Player, rt: Runtime)
	if SpawnService.isFrozen(player) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if isDodging(rt) then
		humanoid.WalkSpeed = 0
		return
	end
	if rt.sprinting then
		humanoid.WalkSpeed = GameConfig.SprintSpeed
	else
		humanoid.WalkSpeed = GameConfig.WalkSpeed
	end
end

function AbilityService.handleSprintIntent(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local want = payload.sprinting == true
	local rt = getRuntime(player)
	if not want then
		rt.wantSprint = false
		if rt.sprinting then
			rt.sprinting = false
			rt.regenDelay = cfgSprint().RegenDelaySeconds
			applyWalkSpeed(player, rt)
			AbilityService.push(player, true)
		end
		return
	end
	if not canUseAbilities(player) then
		rt.wantSprint = false
		return
	end
	if isDodging(rt) or inRecovery(rt) then
		return
	end
	if rt.stamina < cfgSprint().MinStaminaToStart then
		rt.wantSprint = false
		return
	end
	rt.wantSprint = true
end

function AbilityService.handleDodgeRequest(player: Player, _payload: any)
	local rt = getRuntime(player)
	local t = nowClock()
	if not canUseAbilities(player) then
		return
	end
	if t < rt.dodgeCooldown then
		AbilityService.push(player, true)
		return
	end
	if isDodging(rt) then
		return
	end

	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if not isGrounded(character, root) then
		return
	end

	local flat = resolveDodgeFlat(humanoid, root)
	if not flat then
		return
	end

	-- Cancel sprint for the roll.
	rt.wantSprint = false
	rt.sprinting = false
	rt.regenDelay = cfgSprint().RegenDelaySeconds

	local dodge = cfgDodge()
	local speed = dodge.Distance / dodge.Duration
	-- Drop any prior roll without clearing the new dodgeUntil window.
	clearDodgeConn(rt)
	destroyDodgeConstraints(rt)
	rt.dodgeCooldown = t + dodge.CooldownSeconds
	rt.dodgeUntil = t + dodge.Duration
	rt.recoveryUntil = t + dodge.Duration + dodge.RecoverySeconds

	local savedJumpPower = humanoid.JumpPower
	local savedJumpHeight = humanoid.JumpHeight
	rt.savedJumpPower = savedJumpPower
	rt.savedJumpHeight = savedJumpHeight

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.PlatformStand = false
	setDodgeRagdollGuards(humanoid, false)

	-- Keep locomotion state — do NOT enter Physics (that was the fling/desync path).
	if
		humanoid:GetState() == Enum.HumanoidStateType.Physics
		or humanoid:GetState() == Enum.HumanoidStateType.Ragdoll
		or humanoid:GetState() == Enum.HumanoidStateType.FallingDown
	then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end

	-- Server-sim during the slide so Position stays authoritative. Client ownership
	-- left stillRoot.Position stale; exit CFrame then teleported back to pre-dodge.
	trySetNetworkOwner(root, nil)

	local startPos = root.Position
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = uprightCFrame(startPos, flat)
	local startVelY = math.clamp(root.AssemblyLinearVelocity.Y, -6, 2)
	root.AssemblyLinearVelocity = Vector3.new(flat.X * speed, startVelY, flat.Z * speed)

	local attachment = Instance.new("Attachment")
	attachment.Name = "VIPDodgeAttachment"
	attachment.Parent = root
	rt.dodgeAttachment = attachment

	-- Orientation lock only — XZ is Heartbeat-driven from startPos (no exit snap).
	local align = Instance.new("AlignOrientation")
	align.Name = "VIPDodgeAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.CFrame = facingCFrame(flat)
	align.Parent = root
	rt.dodgeAlign = align

	local elapsed = 0
	local finished = false
	local lastPos = startPos
	rt.dodgeConn = RunService.Heartbeat:Connect(function(dt)
		if finished then
			return
		end
		elapsed += dt
		local still = player.Character
		local stillRoot = still and still:FindFirstChild("HumanoidRootPart") :: BasePart?
		local stillHum = still and still:FindFirstChildOfClass("Humanoid")
		local done = elapsed >= dodge.Duration
			or not stillRoot
			or not stillHum
			or stillHum.Health <= 0

		if done then
			finished = true
			clearDodgeConn(rt)
			destroyDodgeConstraints(rt)
			rt.dodgeUntil = 0
			if stillRoot and stillHum and stillHum.Health > 0 then
				-- Land at the final slide sample — never re-read a pre-slide Position.
				local traveled = math.clamp(elapsed, 0, dodge.Duration) * speed
				traveled = math.min(traveled, dodge.Distance)
				local endPos = slidePosition(startPos, flat, traveled, stillRoot.Position.Y)
				local alongLast = (Vector3.new(lastPos.X, 0, lastPos.Z) - Vector3.new(
					startPos.X,
					0,
					startPos.Z
				)):Dot(flat)
				if alongLast > traveled then
					endPos = slidePosition(startPos, flat, alongLast, stillRoot.Position.Y)
				end
				stillRoot.AssemblyAngularVelocity = Vector3.zero
				stillRoot.CFrame = uprightCFrame(endPos, flat)
				local landSpeed = GameConfig.WalkSpeed
				local vy = math.clamp(stillRoot.AssemblyLinearVelocity.Y, -10, 4)
				stillRoot.AssemblyLinearVelocity =
					Vector3.new(flat.X * landSpeed, vy, flat.Z * landSpeed)
				trySetNetworkOwner(stillRoot, player)
				restoreHumanoidAfterDodge(player, stillHum, savedJumpPower, savedJumpHeight)
				rt.savedJumpPower = nil
				rt.savedJumpHeight = nil
				applyWalkSpeed(player, rt)
			elseif stillRoot then
				trySetNetworkOwner(stillRoot, player)
				if stillHum then
					restoreHumanoidAfterDodge(player, stillHum, savedJumpPower, savedJumpHeight)
				end
				rt.savedJumpPower = nil
				rt.savedJumpHeight = nil
			elseif stillHum then
				restoreHumanoidAfterDodge(player, stillHum, savedJumpPower, savedJumpHeight)
				rt.savedJumpPower = nil
				rt.savedJumpHeight = nil
			end
			AbilityService.push(player, true)
			return
		end

		local alpha = math.clamp(elapsed / dodge.Duration, 0, 1)
		local traveled = dodge.Distance * alpha
		local pos = slidePosition(startPos, flat, traveled, stillRoot.Position.Y)
		lastPos = pos
		stillRoot.AssemblyAngularVelocity = Vector3.zero
		local vy = math.clamp(stillRoot.AssemblyLinearVelocity.Y, -16, 6)
		stillRoot.AssemblyLinearVelocity = Vector3.new(flat.X * speed, vy, flat.Z * speed)
		stillRoot.CFrame = uprightCFrame(pos, flat)

		if
			stillHum:GetState() == Enum.HumanoidStateType.Physics
			or stillHum:GetState() == Enum.HumanoidStateType.Ragdoll
		then
			stillHum:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)

	AbilityService.push(player, true)
end

local function stepPlayer(player: Player, dt: number)
	local rt = getRuntime(player)
	local sprint = cfgSprint()

	if SpawnService.isFrozen(player) then
		rt.wantSprint = false
		rt.sprinting = false
		return
	end

	if isDodging(rt) then
		rt.sprinting = false
		return
	end

	local canSprint = canUseAbilities(player)
		and rt.wantSprint
		and rt.stamina > 0
		and not inRecovery(rt)

	if canSprint then
		if not rt.sprinting and rt.stamina < sprint.MinStaminaToStart then
			canSprint = false
			rt.wantSprint = false
		end
	end

	if canSprint then
		rt.sprinting = true
		rt.stamina = math.max(0, rt.stamina - sprint.DrainPerSecond * dt)
		rt.regenDelay = sprint.RegenDelaySeconds
		if rt.stamina <= 0 then
			rt.stamina = 0
			rt.sprinting = false
			rt.wantSprint = false
		end
	else
		if rt.sprinting then
			rt.sprinting = false
			rt.regenDelay = sprint.RegenDelaySeconds
		end
		if rt.regenDelay > 0 then
			rt.regenDelay = math.max(0, rt.regenDelay - dt)
		elseif rt.stamina < sprint.MaxStamina then
			rt.stamina = math.min(sprint.MaxStamina, rt.stamina + sprint.RegenPerSecond * dt)
		end
	end

	applyWalkSpeed(player, rt)
	AbilityService.push(player, false)
end

function AbilityService.init()
	Remotes.get(Net.SprintIntent).OnServerEvent:Connect(function(player, payload)
		AbilityService.handleSprintIntent(player, payload)
	end)
	Remotes.get(Net.DodgeRequest).OnServerEvent:Connect(function(player, payload)
		AbilityService.handleDodgeRequest(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local rt = byPlayer[player]
		if rt then
			stopDodge(player, rt)
		end
		byPlayer[player] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				local rt = getRuntime(player)
				rt.wantSprint = false
				rt.sprinting = false
				stopDodge(player, rt)
				if not SpawnService.isFrozen(player) then
					applyWalkSpeed(player, rt)
				end
				AbilityService.push(player, true)
			end)
		end)
		AbilityService.push(player, true)
	end)

	for _, player in Players:GetPlayers() do
		AbilityService.push(player, true)
	end

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for _, player in Players:GetPlayers() do
			stepPlayer(player, dt)
		end
	end)

	print(
		string.format(
			"[AbilityService] Sprint %d→%d studs/s, stamina drain %.0f/s; dodge %.0f studs / %.0fs CD.",
			GameConfig.WalkSpeed,
			GameConfig.SprintSpeed,
			cfgSprint().DrainPerSecond,
			cfgDodge().Distance,
			cfgDodge().CooldownSeconds
		)
	)
end

return AbilityService
