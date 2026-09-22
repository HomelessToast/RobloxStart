--!strict
-- Client gunfeel: fire sounds, muzzle flash, tool kick, bullet tracers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local WeaponAudio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponAudio"))
local WeaponVisuals =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local weaponFired = remotes:WaitForChild(Net.WeaponFired) :: RemoteEvent

local tracerFolder = Instance.new("Folder")
tracerFolder.Name = "VipTracers"
tracerFolder.Parent = Workspace

local function playFireSound(feel: WeaponAudio.FireFeel, position: Vector3)
	local part = Instance.new("Part")
	part.Name = "GunSoundEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position
	part.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = feel.soundId
	sound.Volume = feel.volume
	sound.PlaybackSpeed = feel.playbackSpeed
	sound.RollOffMaxDistance = 220
	sound.RollOffMinDistance = 12
	sound.Parent = part
	sound:Play()
	sound.Ended:Connect(function()
		part:Destroy()
	end)
	task.delay(3, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

local function spawnTracer(origin: Vector3, endPos: Vector3, feel: WeaponAudio.FireFeel)
	local delta = endPos - origin
	local dist = delta.Magnitude
	if dist < 0.5 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = feel.tracerColor
	tracer.Size = Vector3.new(feel.tracerWidth, feel.tracerWidth, dist)
	tracer.CFrame = CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -dist * 0.5)
	tracer.Parent = tracerFolder

	local fade = TweenService:Create(
		tracer,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Transparency = 1,
			Size = Vector3.new(feel.tracerWidth * 0.4, feel.tracerWidth * 0.4, dist),
		}
	)
	fade:Play()
	fade.Completed:Connect(function()
		tracer:Destroy()
	end)
end

local function muzzleFlash(character: Model, feel: WeaponAudio.FireFeel)
	local folder = character:FindFirstChild(WeaponVisuals.folderName())
	if not folder then
		return
	end
	local muzzle: Attachment? = nil
	for _, d in folder:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "Muzzle" then
			muzzle = d
			break
		end
	end
	if not muzzle then
		return
	end

	local light = Instance.new("PointLight")
	light.Brightness = feel.muzzleBrightness
	light.Range = 10
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Parent = muzzle.Parent

	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.45, 0.45, 0.45)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 230, 140)
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Massless = true
	flash.CastShadow = false
	flash.Anchored = false
	flash.CFrame = muzzle.WorldCFrame
	flash.Parent = folder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = muzzle.Parent :: BasePart
	weld.Part1 = flash
	weld.Parent = flash

	task.delay(0.05, function()
		light:Destroy()
		flash:Destroy()
	end)
end

local function toolKick(character: Model, feel: WeaponAudio.FireFeel)
	local folder = character:FindFirstChild(WeaponVisuals.folderName())
	if not folder then
		return
	end
	local weld: Weld? = nil
	for _, d in folder:GetDescendants() do
		if d:IsA("Weld") and d.Name == "WeaponHandWeld" then
			weld = d
			break
		end
	end
	if not weld then
		return
	end

	local base = weld.C0
	local kick = base
		* CFrame.Angles(math.rad(-feel.kickDegrees), 0, math.rad((math.random() - 0.5) * 2))
	weld.C0 = kick
	task.delay(0.05, function()
		if weld and weld.Parent then
			weld.C0 = base
		end
	end)

	if character == localPlayer.Character then
		local cam = Workspace.CurrentCamera
		if cam then
			-- Mild camera punch; kickDegrees already tuned down for playtest.
			local punch = CFrame.Angles(math.rad(-feel.kickDegrees * 0.2), 0, 0)
			cam.CFrame = cam.CFrame * punch
		end
	end
end

weaponFired.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local weaponId = payload.weaponId
	local origin = payload.origin
	local endPos = payload.endPos
	if
		typeof(weaponId) ~= "string"
		or typeof(origin) ~= "Vector3"
		or typeof(endPos) ~= "Vector3"
	then
		return
	end

	local feel = WeaponAudio.feelFor(weaponId)
	spawnTracer(origin, endPos, feel)
	playFireSound(feel, origin)

	local shooterUserId = payload.shooterUserId
	local shooter: Player? = nil
	if typeof(shooterUserId) == "number" then
		shooter = Players:GetPlayerByUserId(shooterUserId)
	end
	local character = if shooter then shooter.Character else nil
	if character then
		muzzleFlash(character, feel)
		toolKick(character, feel)
	end
end)

print("[WeaponFxController] Tracers · muzzle · kick · class fire sounds ready.")
