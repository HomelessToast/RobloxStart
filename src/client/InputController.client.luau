--!strict
-- Fire, sprint (Shift), and dodge (Q) intents. Server owns stamina / cooldown / WalkSpeed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function sendSprint(sprinting: boolean)
	sprintIntent:FireServer({ sprinting = sprinting })
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

	local camera = currentCamera()
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local direction = if camera then camera.CFrame.LookVector else root.CFrame.LookVector

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
	-- If server dropped our sprint (empty stamina), clear local hold intent mirror.
	if payload.sprinting == false and holdingSprint and typeof(payload.stamina) == "number" then
		if payload.stamina <= 0 then
			holdingSprint = false
			sendSprint(false)
		end
	end
end)

print("[InputController] LMB fire · Shift sprint · Q dodge (server-authoritative).")
