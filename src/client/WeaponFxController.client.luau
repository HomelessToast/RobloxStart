--!strict
-- Client gunfeel: punchy fire sounds, muzzle flash, tool kick, bold tracers.

local ContentProvider = game:GetService("ContentProvider")
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
	-- Tight rolloff so 3rd-person doesn't get a room-filling boom.
	sound.RollOffMaxDistance = 160
	sound.RollOffMinDistance = 6
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part

	-- Preload then play — cutting before Loaded made sniper (and cold assets) silent.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
		if not part.Parent then
			return
		end
		sound:Play()
		local cut = math.max(feel.maxDuration, 0.05)
		task.wait(cut)
		if sound.Parent then
			sound:Stop()
		end
		if part.Parent then
			part:Destroy()
		end
	end)
end

local function makeTracerBolt(
	origin: Vector3,
	endPos: Vector3,
	width: number,
	color: Color3,
	transparency: number,
	lifetime: number
)
	local delta = endPos - origin
	local dist = math.max(delta.Magnitude, 4)
	local dir = if delta.Magnitude > 0.01 then delta.Unit else Vector3.new(0, 0, -1)
	local far = origin + dir * dist

	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = color
	tracer.Transparency = transparency
	tracer.Size = Vector3.new(width, width, dist)
	tracer.CFrame = CFrame.lookAt(origin, far) * CFrame.new(0, 0, -dist * 0.5)
	tracer.Parent = tracerFolder

	local fade = TweenService:Create(
		tracer,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Transparency = 1,
			Size = Vector3.new(width * 0.7, width * 0.7, dist),
		}
	)
	fade:Play()
	fade.Completed:Connect(function()
		tracer:Destroy()
	end)
end

local function spawnTracer(origin: Vector3, endPos: Vector3, feel: WeaponAudio.FireFeel)
	local delta = endPos - origin
	if delta.Magnitude < 0.35 then
		return
	end

	-- Bright core + wider halo so shots read in 3rd person against sky/city.
	local w = feel.tracerWidth
	makeTracerBolt(origin, endPos, w, feel.tracerColor, 0, 0.2)
	makeTracerBolt(
		origin,
		endPos,
		w * 2.4,
		feel.tracerColor:Lerp(Color3.new(1, 1, 1), 0.45),
		0.4,
		0.24
	)
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
	light.Range = 12
	light.Color = Color3.fromRGB(255, 210, 130)
	light.Parent = muzzle.Parent

	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.55, 0.55, 0.55)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 240, 170)
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
	local yawJitter = (math.random() - 0.5) * math.min(feel.kickDegrees * 0.35, 1.2)
	local kick = base * CFrame.Angles(math.rad(-feel.kickDegrees), 0, math.rad(yawJitter))
	weld.C0 = kick
	task.delay(0.055, function()
		if weld and weld.Parent then
			weld.C0 = base
		end
	end)

	if character == localPlayer.Character then
		local cam = Workspace.CurrentCamera
		if cam then
			-- Camera punch scales with per-gun kick; keep mild vs tool kick.
			local punch = CFrame.Angles(math.rad(-feel.kickDegrees * 0.18), 0, 0)
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

print("[WeaponFxController] Per-gun kick · punchy SFX · bold tracers ready.")
