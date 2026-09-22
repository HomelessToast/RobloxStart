--!strict
-- Fire, sprint (Shift), and dodge (Q) intents. Server owns stamina / cooldown / WalkSpeed.
-- Client mirrors sprint with a real run AnimationTrack (not WalkSpeed alone).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local WeaponDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponDefs"))

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireShot = remotes:WaitForChild(Net.FireShot) :: RemoteEvent
local sprintIntent = remotes:WaitForChild(Net.SprintIntent) :: RemoteEvent
local dodgeRequest = remotes:WaitForChild(Net.DodgeRequest) :: RemoteEvent

local holdingFire = false
local holdingSprint = false
local lastClientShot = 0
local currentWeaponId = "M9"
local serverAllowsFire = true
local serverSprinting = false
local serverDodging = false

local sprintTrack: AnimationTrack? = nil
local sprintTrackRig: Enum.HumanoidRigType? = nil
local sprintAnimCharacter: Model? = nil

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

--[[
	Aim through the screen center (crosshair), not camera.LookVector from the chest.
	Root cause of 3rd-person miss: in 3rd person the camera sits behind/above the
	character, so LookVector-from-chest is parallel to the camera but does not pass
	through the aim point under the crosshair. 1st person hid the bug (camera ≈ head).
]]
local function aimDirectionFromScreen(origin: Vector3, character: Model, fallback: Vector3): Vector3
	local camera = currentCamera()
	if not camera then
		return fallback
	end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local hit = Workspace:Raycast(ray.Origin, ray.Direction * GameConfig.MaxShotDistance, params)
	local aimPoint = if hit
		then hit.Position
		else ray.Origin + ray.Direction * GameConfig.MaxShotDistance

	local delta = aimPoint - origin
	if delta.Magnitude < 0.25 then
		return ray.Direction.Unit
	end
	return delta.Unit
end

local function sendSprint(sprinting: boolean)
	sprintIntent:FireServer({ sprinting = sprinting })
end

local function stopSprintAnim(fade: number?)
	local track = sprintTrack
	if track and track.IsPlaying then
		track:Stop(fade or 0.12)
	end
end

local function ensureSprintTrack(humanoid: Humanoid): AnimationTrack?
	local character = humanoid.Parent
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local rig = humanoid.RigType
	if sprintTrack and sprintAnimCharacter == character and sprintTrackRig == rig then
		return sprintTrack
	end

	stopSprintAnim(0)
	sprintTrack = nil
	sprintTrackRig = rig
	sprintAnimCharacter = character

	local anim = Instance.new("Animation")
	local sprintCfg = GameConfig.Sprint
	anim.AnimationId = if rig == Enum.HumanoidRigType.R6
		then sprintCfg.RunAnimationR6
		else sprintCfg.RunAnimationR15

	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or typeof(trackOrErr) ~= "Instance" then
		warn("[InputController] Failed to load sprint run animation:", trackOrErr)
		return nil
	end

	local track = trackOrErr :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	sprintTrack = track
	return track
end

local function updateSprintAnim()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		stopSprintAnim(0.08)
		return
	end

	-- Visual only when server says sprinting, we're actually moving, and not mid-roll.
	local moving = humanoid.MoveDirection.Magnitude > 0.08
	local shouldPlay = serverSprinting and moving and not serverDodging
	if not shouldPlay then
		stopSprintAnim(0.12)
		return
	end

	local track = ensureSprintTrack(humanoid)
	if not track then
		return
	end
	if not track.IsPlaying then
		track:Play(0.12)
		track:AdjustSpeed(GameConfig.Sprint.RunAnimSpeed)
	end
end

local function fire()
	if not serverAllowsFire then
		return
	end
	-- Design: cannot fire while sprinting (client mirror; server enforces).
	if holdingSprint then
		return
	end
	local character = localPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local def = WeaponDefs.get(currentWeaponId)
	local interval = if def then WeaponDefs.fireInterval(def) else 0.18
	local now = os.clock()
	if now - lastClientShot < interval * 0.9 then
		return
	end
	lastClientShot = now

	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local direction = aimDirectionFromScreen(origin, character, root.CFrame.LookVector)

	fireShot:FireServer({
		origin = origin,
		direction = direction,
	})
end

local function isSprintKey(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.LeftShift
		or input.KeyCode == Enum.KeyCode.RightShift
		or input.KeyCode == Enum.KeyCode.ButtonL3
end

local function isDodgeKey(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local isFire = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
	if isFire then
		holdingFire = true
		fire()
		return
	end
	if isSprintKey(input) then
		holdingSprint = true
		sendSprint(true)
		return
	end
	if isDodgeKey(input) then
		dodgeRequest:FireServer({})
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local isFire = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
	if isFire then
		holdingFire = false
		return
	end
	if isSprintKey(input) then
		holdingSprint = false
		sendSprint(false)
	end
end)

RunService.RenderStepped:Connect(function()
	if holdingFire then
		fire()
	end
	updateSprintAnim()
end)

localPlayer.CharacterAdded:Connect(function()
	stopSprintAnim(0)
	sprintTrack = nil
	sprintTrackRig = nil
	sprintAnimCharacter = nil
	serverSprinting = false
	serverDodging = false
end)

remotes:WaitForChild(Net.PlayerState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.weaponId) == "string" and payload.weaponId ~= "" then
		currentWeaponId = payload.weaponId
	end
end)

remotes:WaitForChild(Net.MovementState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.canFire) == "boolean" then
		serverAllowsFire = payload.canFire
	end
	if typeof(payload.sprinting) == "boolean" then
		serverSprinting = payload.sprinting
	end
	if typeof(payload.dodging) == "boolean" then
		serverDodging = payload.dodging
	end
	-- If server dropped our sprint (empty stamina), clear local hold intent mirror.
	if payload.sprinting == false and holdingSprint and typeof(payload.stamina) == "number" then
		if payload.stamina <= 0 then
			holdingSprint = false
			sendSprint(false)
		end
	end
	updateSprintAnim()
end)

print("[InputController] LMB fire · Shift sprint (run anim) · Q dodge (server-authoritative).")
