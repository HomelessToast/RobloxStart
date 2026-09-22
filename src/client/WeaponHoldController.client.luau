--!strict
-- Override R15 right-arm Motor6D.Transform every Stepped so welded guns sit in a
-- ready/aim pose (chest-high, character-forward) instead of hanging at the hip.
-- Applies to ALL characters that have a VipWeaponVisual folder (not just local).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponVisuals =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local function applyHoldPose(character: Model)
	local folder = character:FindFirstChild(WeaponVisuals.folderName())
	if not folder then
		return
	end
	local motors = WeaponVisuals.findArmMotors(character)
	local shoulderPose, elbowPose, wristPose = WeaponVisuals.readyArmTransforms()
	if motors.RightShoulder then
		motors.RightShoulder.Transform = shoulderPose
	end
	if motors.RightElbow then
		motors.RightElbow.Transform = elbowPose
	end
	if motors.RightWrist then
		motors.RightWrist.Transform = wristPose
	end
end

RunService.Stepped:Connect(function()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			applyHoldPose(character)
		end
	end
end)

print("[WeaponHoldController] Ready/aim arm pose for VipWeaponVisual characters.")
