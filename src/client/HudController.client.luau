--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
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
	makeLabel("Timer", UDim2.new(0.5, 0, 0, 16), UDim2.fromOffset(320, 36), 28, Vector2.new(0.5, 0))
timerLabel.TextXAlignment = Enum.TextXAlignment.Center

local scoreLabel =
	makeLabel("Score", UDim2.new(0.5, 0, 0, 48), UDim2.fromOffset(420, 22), 16, Vector2.new(0.5, 0))
scoreLabel.TextXAlignment = Enum.TextXAlignment.Center
scoreLabel.Font = Enum.Font.GothamMedium
scoreLabel.TextColor3 = Color3.fromRGB(180, 200, 230)

local objectiveLabel = makeLabel(
	"Objective",
	UDim2.new(0.5, 0, 0, 70),
	UDim2.new(0.85, 0, 0, 28),
	18,
	Vector2.new(0.5, 0)
)
objectiveLabel.TextXAlignment = Enum.TextXAlignment.Center
objectiveLabel.Font = Enum.Font.GothamMedium

local roleLabel = makeLabel("Role", UDim2.new(0, 20, 1, -188), UDim2.fromOffset(360, 28), 18)
local cashLabel = makeLabel("Cash", UDim2.new(0, 20, 1, -160), UDim2.fromOffset(220, 24), 16)
cashLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
local armorLabel = makeLabel("Armor", UDim2.new(0, 20, 1, -136), UDim2.fromOffset(280, 24), 16)
armorLabel.TextColor3 = Color3.fromRGB(140, 180, 255)
local ammoLabel =
	makeLabel("Ammo", UDim2.new(1, -20, 1, -120), UDim2.fromOffset(220, 28), 20, Vector2.new(1, 0))
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Dodge cooldown — bottom-left (bar + numeric remaining). Server owns CD via MovementState.
local dodgePanel = Instance.new("Frame")
dodgePanel.Name = "DodgeCooldown"
dodgePanel.AnchorPoint = Vector2.new(0, 1)
dodgePanel.Position = UDim2.new(0, 20, 1, -72)
dodgePanel.Size = UDim2.fromOffset(200, 40)
dodgePanel.BackgroundTransparency = 1
dodgePanel.Parent = screenGui

local dodgeLabel = Instance.new("TextLabel")
dodgeLabel.Name = "Label"
dodgeLabel.BackgroundTransparency = 1
dodgeLabel.Position = UDim2.fromOffset(0, 0)
dodgeLabel.Size = UDim2.new(1, 0, 0, 18)
dodgeLabel.Font = Enum.Font.GothamBold
dodgeLabel.TextSize = 14
dodgeLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
dodgeLabel.TextStrokeTransparency = 0.4
dodgeLabel.TextXAlignment = Enum.TextXAlignment.Left
dodgeLabel.TextYAlignment = Enum.TextYAlignment.Center
dodgeLabel.Text = "DODGE  Q  ready"
dodgeLabel.Parent = dodgePanel

local dodgeBarBg = Instance.new("Frame")
dodgeBarBg.Name = "BarBg"
dodgeBarBg.Position = UDim2.fromOffset(0, 22)
dodgeBarBg.Size = UDim2.new(1, 0, 0, 10)
dodgeBarBg.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
dodgeBarBg.BorderSizePixel = 0
dodgeBarBg.Parent = dodgePanel

local dodgeBarBgCorner = Instance.new("UICorner")
dodgeBarBgCorner.CornerRadius = UDim.new(0, 4)
dodgeBarBgCorner.Parent = dodgeBarBg

local dodgeBarFill = Instance.new("Frame")
dodgeBarFill.Name = "Fill"
dodgeBarFill.Size = UDim2.fromScale(1, 1)
dodgeBarFill.BackgroundColor3 = Color3.fromRGB(100, 190, 255)
dodgeBarFill.BorderSizePixel = 0
dodgeBarFill.Parent = dodgeBarBg

local dodgeBarFillCorner = Instance.new("UICorner")
dodgeBarFillCorner.CornerRadius = UDim.new(0, 4)
dodgeBarFillCorner.Parent = dodgeBarFill

-- Cooldown duration from GameConfig for bar ratio (server sends remaining seconds).
local DODGE_COOLDOWN_SECONDS = GameConfig.Dodge.CooldownSeconds

-- Sprint stamina bar (bottom-center)
local staminaBg = Instance.new("Frame")
staminaBg.Name = "StaminaBarBg"
staminaBg.AnchorPoint = Vector2.new(0.5, 1)
staminaBg.Position = UDim2.new(0.5, 0, 1, -36)
staminaBg.Size = UDim2.fromOffset(220, 10)
staminaBg.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
staminaBg.BorderSizePixel = 0
staminaBg.Parent = screenGui

local staminaBgCorner = Instance.new("UICorner")
staminaBgCorner.CornerRadius = UDim.new(0, 4)
staminaBgCorner.Parent = staminaBg

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.Size = UDim2.fromScale(1, 1)
staminaFill.BackgroundColor3 = Color3.fromRGB(90, 200, 140)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaBg

local staminaFillCorner = Instance.new("UICorner")
staminaFillCorner.CornerRadius = UDim.new(0, 4)
staminaFillCorner.Parent = staminaFill

local staminaCaption = makeLabel(
	"StaminaCaption",
	UDim2.new(0.5, 0, 1, -52),
	UDim2.fromOffset(160, 16),
	12,
	Vector2.new(0.5, 1)
)
staminaCaption.TextXAlignment = Enum.TextXAlignment.Center
staminaCaption.Font = Enum.Font.GothamMedium
staminaCaption.TextColor3 = Color3.fromRGB(160, 175, 190)
staminaCaption.Text = "SPRINT  Shift"

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 108)
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
captureBarBg.Position = UDim2.new(0.5, 0, 0, 160)
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
	UDim2.new(0.5, 0, 0, 180),
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
	local roundNumber = payload.roundNumber or 0
	timerLabel.Text =
		string.format("R%d  %s  %s", roundNumber, tostring(roundState), formatTime(remaining))
	objectiveLabel.Text = payload.objectiveBanner or ""

	local scoreLine = payload.scoreLine
	local winsNeeded = payload.winsNeeded or 4
	if scoreLine and roundNumber > 0 then
		local sideA = payload.sideA or "?"
		local sideB = payload.sideB or "?"
		scoreLabel.Text = string.format(
			"Score %s  (first to %d)  ·  A:%s  B:%s",
			tostring(scoreLine),
			winsNeeded,
			tostring(sideA),
			tostring(sideB)
		)
		scoreLabel.Visible = true
	elseif scoreLine and tostring(scoreLine) ~= "0–0" then
		scoreLabel.Text = string.format("Score %s  (first to %d)", tostring(scoreLine), winsNeeded)
		scoreLabel.Visible = true
	else
		scoreLabel.Text = string.format("Best of 7 · first to %d", winsNeeded)
		scoreLabel.Visible = roundState ~= Enums.RoundState.Lobby or (payload.lobbyMode ~= nil)
	end

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
	local score = payload.scoreLine
	local msg = tostring(payload.message or "Round over")
	if score then
		msg = string.format("%s · %s", msg, tostring(score))
	end
	if typeof(payload.economySummary) == "string" and payload.economySummary ~= "" then
		msg ..= " · " .. payload.economySummary
	end
	showBanner(msg, "warning")
end)

remotes:WaitForChild(Net.MatchEnded).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local winner = payload.winnerTeam
	local score = payload.scoreLine or ""
	local text = if winner
		then string.format("MATCH OVER — Team %s wins (%s)", tostring(winner), tostring(score))
		else string.format("MATCH OVER (%s)", tostring(score))
	showBanner(text, "warning")
end)

remotes:WaitForChild(Net.EconomyState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.cash) == "number" then
		cashLabel.Text = string.format("$%d", payload.cash)
	end
end)

remotes:WaitForChild(Net.PlayerState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	playerAlive = payload.alive == true
	roleLabel.Text = string.format("%s · %s", tostring(payload.side), tostring(payload.role))
	if typeof(payload.cash) == "number" then
		cashLabel.Text = string.format("$%d", payload.cash)
	end
	local armorPool = payload.armorPool or 0
	local armorMax = payload.armorMax or 0
	if armorMax > 0 then
		armorLabel.Text = string.format(
			"Armor %d/%d%s",
			armorPool,
			armorMax,
			if payload.hasHelmet then " · HELMET" else ""
		)
	else
		armorLabel.Text = "Armor —"
	end
	ammoLabel.Text = string.format(
		"%s  %d / %d%s",
		tostring(payload.weaponName or ""),
		payload.ammo or 0,
		payload.reserve or 0,
		if payload.reloading == true then "  RELOAD" else ""
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

remotes:WaitForChild(Net.MovementState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local maxStamina = payload.maxStamina or 100
	local stamina = payload.stamina or maxStamina
	local ratio = if maxStamina > 0 then math.clamp(stamina / maxStamina, 0, 1) else 0
	staminaFill.Size = UDim2.fromScale(ratio, 1)
	if payload.sprinting then
		staminaFill.BackgroundColor3 = Color3.fromRGB(255, 190, 80)
		staminaCaption.Text = "SPRINTING"
	elseif ratio < 0.25 then
		staminaFill.BackgroundColor3 = Color3.fromRGB(220, 90, 80)
		staminaCaption.Text = "SPRINT  Shift"
	else
		staminaFill.BackgroundColor3 = Color3.fromRGB(90, 200, 140)
		staminaCaption.Text = "SPRINT  Shift"
	end

	local cd = payload.dodgeCooldownRemaining or 0
	if payload.dodging then
		dodgeLabel.Text = "DODGE  rolling…"
		dodgeLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
		dodgeBarFill.Size = UDim2.fromScale(1, 1)
		dodgeBarFill.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
	elseif cd > 0.05 then
		-- Show one-decimal remaining so the bottom-left CD is readable mid-count.
		dodgeLabel.Text = string.format("DODGE  Q  %.1fs", cd)
		dodgeLabel.TextColor3 = Color3.fromRGB(150, 160, 175)
		local cdRatio = math.clamp(1 - (cd / DODGE_COOLDOWN_SECONDS), 0, 1)
		dodgeBarFill.Size = UDim2.fromScale(cdRatio, 1)
		dodgeBarFill.BackgroundColor3 = Color3.fromRGB(120, 150, 190)
	else
		dodgeLabel.Text = "DODGE  Q  ready"
		dodgeLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
		dodgeBarFill.Size = UDim2.fromScale(1, 1)
		dodgeBarFill.BackgroundColor3 = Color3.fromRGB(100, 190, 255)
	end
end)

print("[HudController] VIP HUD live.")
