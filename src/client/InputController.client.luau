--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireShot = remotes:WaitForChild(Net.FireShot) :: RemoteEvent

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function fire()
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

	local camera = currentCamera()
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local direction = if camera then camera.CFrame.LookVector else root.CFrame.LookVector

	fireShot:FireServer({
		origin = origin,
		direction = direction,
	})
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local isFire = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
	if isFire then
		fire()
	end
end)

print("[InputController] LMB / R2 fires server-authoritative shots.")
