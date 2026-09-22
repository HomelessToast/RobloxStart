--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VipHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function makeLabel(
	name: string,
	position: UDim2,
	size: UDim2,
	textSize: number,
	anchor: Vector2?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.AnchorPoint = anchor or Vector2.new(0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(240, 242, 248)
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""
	label.Parent = screenGui
	return label
end

local timerLabel =
	makeLabel("Timer", UDim2.new(0.5, 0, 0, 16), UDim2.fromOffset(280, 36), 28, Vector2.new(0.5, 0))
timerLabel.TextXAlignment = Enum.TextXAlignment.Center

local objectiveLabel = makeLabel(
	"Objective",
	UDim2.new(0.5, 0, 0, 52),
	UDim2.new(0.8, 0, 0, 28),
	18,
	Vector2.new(0.5, 0)
)
objectiveLabel.TextXAlignment = Enum.TextXAlignment.Center
objectiveLabel.Font = Enum.Font.GothamMedium

local roleLabel = makeLabel("Role", UDim2.new(0, 20, 1, -120), UDim2.fromOffset(360, 28), 18)
local ammoLabel =
	makeLabel("Ammo", UDim2.new(1, -20, 1, -120), UDim2.fromOffset(220, 28), 20, Vector2.new(1, 0))
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 96)
banner.Size = UDim2.new(0.85, 0, 0, 44)
banner.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
banner.BackgroundTransparency = 0.2
banner.BorderSizePixel = 0
banner.Font = Enum.Font.GothamBold
banner.TextSize = 20
banner.TextColor3 = Color3.fromRGB(255, 230, 120)
banner.Text = ""
banner.Visible = false
banner.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 8)
bannerCorner.Parent = banner

local captureBarBg = Instance.new("Frame")
captureBarBg.Name = "CaptureBarBg"
captureBarBg.AnchorPoint = Vector2.new(0.5, 0)
captureBarBg.Position = UDim2.new(0.5, 0, 0, 148)
captureBarBg.Size = UDim2.new(0.5, 0, 0, 14)
captureBarBg.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
captureBarBg.BorderSizePixel = 0
captureBarBg.Visible = false
captureBarBg.Parent = screenGui

local captureBarCorner = Instance.new("UICorner")
captureBarCorner.CornerRadius = UDim.new(0, 6)
captureBarCorner.Parent = captureBarBg

local captureBar = Instance.new("Frame")
captureBar.Name = "Fill"
captureBar.Size = UDim2.fromScale(0, 1)
captureBar.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
captureBar.BorderSizePixel = 0
captureBar.Parent = captureBarBg

local captureBarFillCorner = Instance.new("UICorner")
captureBarFillCorner.CornerRadius = UDim.new(0, 6)
captureBarFillCorner.Parent = captureBar

local captureLabel = makeLabel(
	"CaptureLabel",
	UDim2.new(0.5, 0, 0, 168),
	UDim2.new(0.6, 0, 0, 24),
	16,
	Vector2.new(0.5, 0)
)
captureLabel.TextXAlignment = Enum.TextXAlignment.Center
captureLabel.Visible = false

local roundState = Enums.RoundState.Lobby
local playerAlive = true

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local m = math.floor(s / 60)
	local r = s % 60
	return string.format("%d:%02d", m, r)
end

local function playCue(kind: string)
	local sound = Instance.new("Sound")
	sound.Volume = 0.45
	if kind == "capture" then
		sound.SoundId = "rbxassetid://6026984224"
	elseif kind == "break" then
		sound.SoundId = "rbxassetid://6026984224"
		sound.PlaybackSpeed = 0.7
	else
		sound.SoundId = "rbxassetid://6026984224"
		sound.PlaybackSpeed = 1.3
	end
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function showBanner(text: string, kind: string?)
	banner.Text = text
	banner.Visible = true
	if kind == "capture" then
		banner.TextColor3 = Color3.fromRGB(255, 210, 90)
	elseif kind == "break" then
		banner.TextColor3 = Color3.fromRGB(255, 120, 100)
	elseif kind == "warning" then
		banner.TextColor3 = Color3.fromRGB(255, 170, 70)
	else
		banner.TextColor3 = Color3.fromRGB(240, 242, 248)
	end
	if kind then
		playCue(kind)
	end
	task.delay(4, function()
		if banner.Text == text then
			banner.Visible = false
		end
	end)
end

remotes:WaitForChild(Net.RoundState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	roundState = payload.state
	local remaining = payload.timeRemaining or 0
	timerLabel.Text = string.format(
		"R%d  %s  %s",
		payload.roundNumber or 0,
		tostring(roundState),
		formatTime(remaining)
	)
	objectiveLabel.Text = payload.objectiveBanner or ""

	if
		remaining <= 30
		and (roundState == Enums.RoundState.Live or roundState == Enums.RoundState.Capture)
	then
		timerLabel.TextColor3 = Color3.fromRGB(255, 120, 100)
	else
		timerLabel.TextColor3 = Color3.fromRGB(240, 242, 248)
	end
end)

remotes:WaitForChild(Net.CaptureState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local captureState = payload.state
	if captureState == Enums.CaptureState.Active then
		captureBarBg.Visible = true
		captureLabel.Visible = true
		captureBar.Size = UDim2.fromScale(payload.progress or 0, 1)
		captureLabel.Text = string.format(
			"SAFE HOUSE %s — %02d",
			tostring(payload.safeHouseId or "?"),
			math.ceil(payload.timeRemaining or 0)
		)
	elseif captureState == Enums.CaptureState.TooLate then
		captureBarBg.Visible = false
		captureLabel.Visible = true
		captureLabel.Text = "TOO LATE"
	else
		captureBarBg.Visible = false
		captureLabel.Visible = false
	end
end)

remotes:WaitForChild(Net.HudBanner).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	showBanner(tostring(payload.text or ""), payload.kind)
end)

remotes:WaitForChild(Net.RoundEnded).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	showBanner(tostring(payload.message or "Round over"), "warning")
end)

remotes:WaitForChild(Net.PlayerState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	playerAlive = payload.alive == true
	roleLabel.Text = string.format("%s · %s", tostring(payload.side), tostring(payload.role))
	ammoLabel.Text = string.format(
		"%s  %d / %d",
		tostring(payload.weaponName or ""),
		payload.ammo or 0,
		payload.reserve or 0
	)

	if not playerAlive then
		roleLabel.Text ..= "  (SPECTATING)"
		-- Simple spectator: follow a living teammate if possible.
		task.defer(function()
			for _, other in Players:GetPlayers() do
				if other ~= localPlayer and other.Character then
					local hum = other.Character:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						local cam = Workspace.CurrentCamera
						if cam then
							cam.CameraSubject = hum
						end
						break
					end
				end
			end
		end)
	end
end)

print("[HudController] VIP HUD live.")
