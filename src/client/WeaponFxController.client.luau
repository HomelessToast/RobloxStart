--!strict
-- Client gunfeel: punchy fire sounds, muzzle flash, tool kick, physical bullets.
-- Bullets are client-only VFX (gravity drop + stick). Server damage stays hitscan.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local WeaponAudio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponAudio"))
local WeaponDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponDefs"))
local WeaponVisuals =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local weaponFired = remotes:WaitForChild(Net.WeaponFired) :: RemoteEvent

-- Stick lifetime / cap so Matthew can read miss distance without littering forever.
local STICK_LIFETIME = 4.5
local MAX_STUCK_BULLETS = 72
local MAX_FLIGHT_TIME = 2.8
local MAX_FLIGHT_DISTANCE = 900

local bulletFolder = Instance.new("Folder")
bulletFolder.Name = "VipBullets"
bulletFolder.Parent = Workspace

local stuckBullets: { BasePart } = {}

local function findMuzzleAttachment(character: Model): Attachment?
	local folder = character:FindFirstChild(WeaponVisuals.folderName())
	if not folder then
		return nil
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "Muzzle" then
			return d
		end
	end
	return nil
end

local function clearAllBullets()
	table.clear(stuckBullets)
	for _, child in bulletFolder:GetChildren() do
		child:Destroy()
	end
end

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

local function pruneStuck(part: BasePart)
	for i = #stuckBullets, 1, -1 do
		if stuckBullets[i] == part then
			table.remove(stuckBullets, i)
			break
		end
	end
end

local function registerStuck(part: BasePart)
	table.insert(stuckBullets, part)
	while #stuckBullets > MAX_STUCK_BULLETS do
		local oldest = table.remove(stuckBullets, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	task.delay(STICK_LIFETIME, function()
		pruneStuck(part)
		if part.Parent then
			part:Destroy()
		end
	end)
end

local function makeBulletPart(feel: WeaponAudio.FireFeel, at: Vector3, look: Vector3): BasePart
	local size = feel.bulletSize
	local bullet = Instance.new("Part")
	bullet.Name = "Bullet"
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CanTouch = false
	bullet.CastShadow = false
	bullet.Material = Enum.Material.Metal
	bullet.Color = feel.bulletColor
	bullet.Size = Vector3.new(size, size, size)
	local forward = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	bullet.CFrame = CFrame.lookAt(at, at + forward)
	bullet.Parent = bulletFolder
	return bullet
end

local function buildRayParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	return params
end

local function stickBullet(bullet: BasePart, hitPos: Vector3, normal: Vector3, velocity: Vector3)
	local offset = normal.Unit * (bullet.Size.X * 0.45)
	local look = if velocity.Magnitude > 0.01 then velocity.Unit else -normal
	bullet.CFrame = CFrame.lookAt(hitPos + offset, hitPos + offset + look)
	registerStuck(bullet)
end

local function simulateBullet(
	origin: Vector3,
	direction: Vector3,
	feel: WeaponAudio.FireFeel,
	exclude: { Instance }
)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local velocity = dir * feel.muzzleVelocity
	local gravity = Vector3.new(0, -feel.bulletGravity, 0)
	local position = origin
	local traveled = 0
	local elapsed = 0
	local bullet = makeBulletPart(feel, origin, dir)
	local params = buildRayParams(exclude)

	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function(dt)
		if not bullet.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end

		dt = math.clamp(dt, 0, 1 / 20)
		elapsed += dt
		local nextVelocity = velocity + gravity * dt
		local delta = velocity * dt + gravity * (dt * dt * 0.5)
		local step = delta.Magnitude
		if step < 1e-4 then
			return
		end

		local result = Workspace:Raycast(position, delta, params)
		if result then
			if conn then
				conn:Disconnect()
			end
			stickBullet(bullet, result.Position, result.Normal, velocity)
			return
		end

		position = position + delta
		velocity = nextVelocity
		traveled += step
		local look = if velocity.Magnitude > 0.01 then velocity.Unit else dir
		bullet.CFrame = CFrame.lookAt(position, position + look)

		if elapsed >= MAX_FLIGHT_TIME or traveled >= MAX_FLIGHT_DISTANCE then
			if conn then
				conn:Disconnect()
			end
			bullet:Destroy()
		end
	end)
end

local function randomSpread(direction: Vector3, maxRadians: number): Vector3
	local dir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local yaw = (math.random() - 0.5) * 2 * maxRadians
	local pitch = (math.random() - 0.5) * 2 * maxRadians
	local cf = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(pitch, yaw, 0)
	return cf.LookVector
end

local function spawnShotBullets(
	origin: Vector3,
	aimDir: Vector3,
	weaponId: string,
	feel: WeaponAudio.FireFeel,
	shooterCharacter: Model?
)
	local def = WeaponDefs.get(weaponId)
	local pellets = if def then math.max(1, def.pellets) else 1
	local spread = if def then def.baseSpread else 0.02
	-- Visual shotgun fan slightly wider than hip spread so pellets read as a cluster.
	if pellets > 1 then
		spread = math.max(spread, 0.04)
	end

	local exclude: { Instance } = { bulletFolder }
	if shooterCharacter then
		table.insert(exclude, shooterCharacter)
	end
	if localPlayer.Character then
		table.insert(exclude, localPlayer.Character)
	end

	for i = 1, pellets do
		local dir = if i == 1 and pellets == 1 then aimDir else randomSpread(aimDir, spread)
		simulateBullet(origin, dir, feel, exclude)
	end
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
	-- Aim stays hitscan (endPos - origin); spawn position prefers the visual muzzle.
	local delta = endPos - origin
	local aimDir = if delta.Magnitude > 0.01 then delta.Unit else Vector3.new(0, 0, -1)

	local shooterUserId = payload.shooterUserId
	local shooter: Player? = nil
	if typeof(shooterUserId) == "number" then
		shooter = Players:GetPlayerByUserId(shooterUserId)
	end
	local character = if shooter then shooter.Character else nil

	local spawnOrigin = origin
	if character then
		local muzzle = findMuzzleAttachment(character)
		if muzzle then
			spawnOrigin = muzzle.WorldPosition
		end
	end

	spawnShotBullets(spawnOrigin, aimDir, weaponId, feel, character)
	playFireSound(feel, spawnOrigin)

	if character then
		muzzleFlash(character, feel)
		toolKick(character, feel)
	end
end)

remotes:WaitForChild(Net.RoundState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local state = payload.state
	if
		state == Enums.RoundState.RoundEnd
		or state == Enums.RoundState.Intermission
		or state == Enums.RoundState.MatchEnd
		or state == Enums.RoundState.Lobby
	then
		clearAllBullets()
	end
end)

print("[WeaponFxController] Per-gun kick · punchy SFX · sticky bullets · muzzle spawn.")
