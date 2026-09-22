--!strict
-- Sniper ADS: hold RMB (or L2) for scoped zoom + overlay. Release restores view.
-- LMB fire stays on InputController. Only M24 / SVD (Sniper visual class).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local WeaponVisuals =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local adsCfg = GameConfig.SniperAds

local currentWeaponId = ""
local holdingAds = false
local scoped = false
local savedFov: number? = nil
local savedCameraMode: Enum.CameraMode? = nil
local savedMinZoom: number? = nil
local savedMaxZoom: number? = nil
local fovTween: Tween? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "VipSniperScope"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local function makeBar(name: string, size: UDim2, pos: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = pos
	f.Parent = gui
	return f
end

-- Letterbox + dark vignette; center stays clear for the zoomed FOV.
makeBar("TopBar", UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0))
makeBar("BottomBar", UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0.84))
makeBar("LeftBar", UDim2.fromScale(0.22, 0.68), UDim2.fromScale(0, 0.16))
makeBar("RightBar", UDim2.fromScale(0.22, 0.68), UDim2.fromScale(0.78, 0.16))

local ring = Instance.new("Frame")
ring.Name = "ScopeRing"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromScale(0.52, 0.52)
ring.BackgroundTransparency = 1
ring.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.Parent = ring
local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Color = Color3.fromRGB(20, 24, 18)
stroke.Transparency = 0.15
stroke.Parent = ring
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = ring

local function hairline(name: string, size: UDim2, pos: UDim2)
	local line = Instance.new("Frame")
	line.Name = name
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = Color3.fromRGB(30, 40, 28)
	line.BorderSizePixel = 0
	line.Size = size
	line.Position = pos
	line.Parent = gui
end

hairline("CrossH", UDim2.new(0.14, 0, 0, 2), UDim2.fromScale(0.5, 0.5))
hairline("CrossV", UDim2.new(0, 2, 0.14, 0), UDim2.fromScale(0.5, 0.5))

local dot = Instance.new("Frame")
dot.Name = "ReticleDot"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
dot.BorderSizePixel = 0
dot.Size = UDim2.fromOffset(4, 4)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Parent = gui
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot

local function canAds(): boolean
	return WeaponVisuals.isSniperWeapon(currentWeaponId)
end

local function cancelFovTween()
	if fovTween then
		fovTween:Cancel()
		fovTween = nil
	end
end

local function tweenFov(target: number, duration: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	cancelFovTween()
	local tw = TweenService:Create(
		cam,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = target }
	)
	fovTween = tw
	tw:Play()
end

local function exitScope()
	if not scoped then
		gui.Enabled = false
		return
	end
	scoped = false
	gui.Enabled = false

	local cam = Workspace.CurrentCamera
	local restoreFov = savedFov or adsCfg.DefaultFovFallback
	savedFov = nil
	if cam then
		tweenFov(restoreFov, adsCfg.TweenOut)
	end

	if savedCameraMode ~= nil then
		localPlayer.CameraMode = savedCameraMode
		savedCameraMode = nil
	end
	if savedMinZoom ~= nil then
		localPlayer.CameraMinZoomDistance = savedMinZoom
		savedMinZoom = nil
	end
	if savedMaxZoom ~= nil then
		localPlayer.CameraMaxZoomDistance = savedMaxZoom
		savedMaxZoom = nil
	end
end

local function enterScope()
	if scoped or not canAds() then
		return
	end
	scoped = true

	local cam = Workspace.CurrentCamera
	if cam then
		savedFov = cam.FieldOfView
		tweenFov(adsCfg.Fov, adsCfg.TweenIn)
	else
		savedFov = adsCfg.DefaultFovFallback
	end

	savedCameraMode = localPlayer.CameraMode
	savedMinZoom = localPlayer.CameraMinZoomDistance
	savedMaxZoom = localPlayer.CameraMaxZoomDistance
	-- Pull into first-person so the scope overlay frames a real zoom.
	localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

	gui.Enabled = true
end

local function syncAds()
	if holdingAds and canAds() then
		enterScope()
	else
		exitScope()
	end
end

local function isAdsInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.ButtonL2
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if isAdsInput(input) then
		holdingAds = true
		syncAds()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if isAdsInput(input) then
		holdingAds = false
		syncAds()
	end
end)

remotes:WaitForChild(Net.PlayerState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.weaponId) == "string" then
		currentWeaponId = payload.weaponId
		syncAds()
	end
end)

localPlayer.CharacterAdded:Connect(function()
	holdingAds = false
	exitScope()
end)

print("[SniperAdsController] Hold RMB to scope (snipers only).")
