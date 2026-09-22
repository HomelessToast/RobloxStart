local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Welcome = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Welcome"))

local VISIBLE_SECONDS = 6
local FADE_SECONDS = 0.75

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WelcomeHud"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 24)
banner.Size = UDim2.new(1, -32, 0, 52)
banner.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
banner.BackgroundTransparency = 0.15
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = banner

local widthLimit = Instance.new("UISizeConstraint")
widthLimit.MaxSize = Vector2.new(560, math.huge)
widthLimit.Parent = banner

local label = Instance.new("TextLabel")
label.Name = "Message"
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, -24, 1, 0)
label.Position = UDim2.fromOffset(12, 0)
label.Font = Enum.Font.GothamMedium
label.TextColor3 = Color3.fromRGB(240, 242, 248)
label.TextSize = 16
label.TextWrapped = true
label.Text = ""
label.Parent = banner

local hideTween: Tween? = nil

local function show(message: string)
	if hideTween then
		hideTween:Cancel()
		hideTween = nil
	end

	label.Text = message
	banner.BackgroundTransparency = 0.15
	label.TextTransparency = 0
	banner.Visible = true

	task.delay(VISIBLE_SECONDS, function()
		if label.Text ~= message then
			return
		end

		local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fade = TweenService:Create(banner, info, { BackgroundTransparency = 1 })
		fade.Completed:Connect(function()
			banner.Visible = false
		end)
		hideTween = fade

		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		fade:Play()
	end)
end

local welcomeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Welcome.RemoteName)
welcomeRemote.OnClientEvent:Connect(show)

print(string.format("[WelcomeHud] %s client code is live.", Welcome.GameName))
