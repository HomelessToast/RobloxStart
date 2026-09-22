--!strict
-- Buy menu during BUY phase (30s). Picture cards + prices; click to purchase.
-- Server enforces side / cash / President pistol lock; this UI only requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local WeaponDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponDefs"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local WeaponVisuals =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buyRequest = remotes:WaitForChild(Net.BuyRequest) :: RemoteEvent

local side = Enums.Side.Spectator
local role = Enums.Role.Unassigned
local cash = GameConfig.Economy.StartingCash
local buyOpen = false
local menuVisible = false
local buySecondsLeft = GameConfig.BuyPhaseSeconds

local gui = Instance.new("ScreenGui")
gui.Name = "VipBuyMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromOffset(780, 520)
panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -220, 0, 36)
title.Position = UDim2.fromOffset(16, 12)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.TextColor3 = Color3.fromRGB(240, 242, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "BUY"
title.Parent = panel

local timerLabel = Instance.new("TextLabel")
timerLabel.BackgroundTransparency = 1
timerLabel.Size = UDim2.fromOffset(120, 36)
timerLabel.Position = UDim2.new(1, -340, 0, 12)
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextSize = 22
timerLabel.TextColor3 = Color3.fromRGB(255, 200, 90)
timerLabel.TextXAlignment = Enum.TextXAlignment.Right
timerLabel.Text = "30s"
timerLabel.Parent = panel

local cashLabel = Instance.new("TextLabel")
cashLabel.BackgroundTransparency = 1
cashLabel.Size = UDim2.fromOffset(140, 36)
cashLabel.Position = UDim2.new(1, -200, 0, 12)
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 22
cashLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
cashLabel.TextXAlignment = Enum.TextXAlignment.Right
cashLabel.Text = "$0"
cashLabel.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseX"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 10)
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.BackgroundColor3 = Color3.fromRGB(50, 28, 32)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 20
closeBtn.TextColor3 = Color3.fromRGB(255, 210, 210)
closeBtn.Text = "X"
closeBtn.AutoButtonColor = true
closeBtn.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, -32, 0, 20)
hint.Position = UDim2.fromOffset(16, 48)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 13
hint.TextColor3 = Color3.fromRGB(160, 168, 185)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text =
	"Click a card to buy · X toggles menu · multiple guns go to hotbar (1–5) · President pistol-only"
hint.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Items"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(16, 76)
scroll.Size = UDim2.new(1, -32, 1, -110)
scroll.ScrollBarThickness = 5
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(172, 168)
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, -32, 0, 22)
statusLabel.Position = UDim2.new(0, 16, 1, -30)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextColor3 = Color3.fromRGB(200, 205, 220)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = ""
statusLabel.Parent = panel

local function setMenuVisible(visible: boolean)
	menuVisible = visible and buyOpen
	gui.Enabled = menuVisible
end

closeBtn.MouseButton1Click:Connect(function()
	setMenuVisible(false)
end)

local function clearCards()
	for _, child in scroll:GetChildren() do
		if child:IsA("TextButton") or child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function mountPreview(viewport: ViewportFrame, model: Model?, camCf: CFrame)
	viewport:ClearAllChildren()
	if not model then
		return
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model.Parent = world
	local cam = Instance.new("Camera")
	cam.CFrame = camCf
	cam.Parent = viewport
	viewport.CurrentCamera = cam
end

local function addCard(
	layoutOrder: number,
	nameText: string,
	price: number,
	subtitle: string,
	locked: boolean,
	onClick: () -> (),
	previewBuilder: () -> (Model?, CFrame)
)
	local button = Instance.new("TextButton")
	button.Name = "Card_" .. nameText
	button.LayoutOrder = layoutOrder
	button.AutoButtonColor = not locked
	button.Text = ""
	button.BackgroundColor3 = if locked
		then Color3.fromRGB(28, 30, 36)
		else Color3.fromRGB(34, 38, 48)
	button.BorderSizePixel = 0
	button.Parent = scroll

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = if locked then Color3.fromRGB(60, 62, 70) else Color3.fromRGB(70, 90, 120)
	stroke.Transparency = 0.35
	stroke.Parent = button

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.new(1, -16, 0, 88)
	viewport.Position = UDim2.fromOffset(8, 8)
	viewport.Parent = button

	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 6)
	vpCorner.Parent = viewport

	local model, camCf = previewBuilder()
	mountPreview(viewport, model, camCf)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(8, 100)
	nameLabel.Size = UDim2.new(1, -16, 0, 22)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = if locked
		then Color3.fromRGB(120, 122, 130)
		else Color3.fromRGB(235, 238, 245)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = nameText
	nameLabel.Parent = button

	local subLabel = Instance.new("TextLabel")
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.fromOffset(8, 122)
	subLabel.Size = UDim2.new(0.55, 0, 0, 18)
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 12
	subLabel.TextColor3 = Color3.fromRGB(150, 158, 175)
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = subtitle
	subLabel.Parent = button

	local priceLabel = Instance.new("TextLabel")
	priceLabel.BackgroundTransparency = 1
	priceLabel.Position = UDim2.new(0.45, 0, 0, 120)
	priceLabel.Size = UDim2.new(0.55, -8, 0, 22)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextSize = 15
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Text = if price == 0 then "FREE" else string.format("$%d", price)
	priceLabel.TextColor3 = if locked
		then Color3.fromRGB(150, 100, 100)
		elseif price == 0 then Color3.fromRGB(140, 200, 255)
		else Color3.fromRGB(160, 220, 150)
	priceLabel.Parent = button

	if not locked then
		button.MouseButton1Click:Connect(onClick)
	end
end

local function rebuild()
	clearCards()
	cashLabel.Text = string.format("$%d", cash)
	timerLabel.Text = string.format("%ds", math.max(0, math.ceil(buySecondsLeft)))
	title.Text = if role == Enums.Role.President then "BUY — President (pistols)" else "BUY"

	local order = 1
	if side == Enums.Side.Good or side == Enums.Side.Terrorist then
		for _, weapon in WeaponDefs.forSide(side) do
			local presidentBlocked = role == Enums.Role.President
				and not WeaponDefs.isPistolTier(weapon.tier)
			if not presidentBlocked then
				local capturedId = weapon.id
				local locked = weapon.price > cash
				addCard(order, weapon.displayName, weapon.price, weapon.tier, locked, function()
					buyRequest:FireServer({ kind = "Weapon", id = capturedId })
				end, function()
					return WeaponVisuals.buildPreview(capturedId)
				end)
				order += 1
			end
		end
	end

	addCard(
		order,
		GameConfig.Armor.Light.displayName,
		GameConfig.Armor.Light.price,
		"Armor · 50 pool",
		GameConfig.Armor.Light.price > cash,
		function()
			buyRequest:FireServer({ kind = "Armor", id = Enums.ArmorId.Light })
		end,
		function()
			return WeaponVisuals.buildArmorPreview(Enums.ArmorId.Light)
		end
	)
	order += 1
	addCard(
		order,
		GameConfig.Armor.Heavy.displayName,
		GameConfig.Armor.Heavy.price,
		"Armor · 100 + helmet",
		GameConfig.Armor.Heavy.price > cash,
		function()
			buyRequest:FireServer({ kind = "Armor", id = Enums.ArmorId.Heavy })
		end,
		function()
			return WeaponVisuals.buildArmorPreview(Enums.ArmorId.Heavy)
		end
	)
end

remotes:WaitForChild(Net.PlayerState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	side = payload.side or side
	role = payload.role or role
	if typeof(payload.cash) == "number" then
		cash = payload.cash
	end
	local wasOpen = buyOpen
	buyOpen = payload.buyOpen == true
	if buyOpen and not wasOpen then
		setMenuVisible(true)
	elseif not buyOpen then
		setMenuVisible(false)
	end
	if menuVisible then
		rebuild()
	end
end)

remotes:WaitForChild(Net.EconomyState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.cash) == "number" then
		cash = payload.cash
		cashLabel.Text = string.format("$%d", cash)
		if menuVisible then
			rebuild()
		end
	end
end)

remotes:WaitForChild(Net.BuyResult).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.cash) == "number" then
		cash = payload.cash
	end
	statusLabel.Text = tostring(payload.message or payload.result or "")
	if menuVisible then
		rebuild()
	end
end)

remotes:WaitForChild(Net.RoundState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.timeRemaining) == "number" then
		buySecondsLeft = payload.timeRemaining
		timerLabel.Text = string.format("%ds", math.max(0, math.ceil(buySecondsLeft)))
	end
	if payload.state == Enums.RoundState.Buy then
		buyOpen = true
		setMenuVisible(true)
		rebuild()
	elseif payload.state ~= Enums.RoundState.Buy then
		buyOpen = false
		setMenuVisible(false)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.X and buyOpen then
		setMenuVisible(not menuVisible)
		if menuVisible then
			rebuild()
		end
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	if buyOpen then
		setMenuVisible(false)
	end
end)

print("[BuyMenuController] 30s buy menu with picture cards ready (X to toggle).")
