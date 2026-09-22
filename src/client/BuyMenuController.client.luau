--!strict
-- Buy menu during BUY phase. Server enforces purchases; this UI only requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local WeaponDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponDefs"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buyRequest = remotes:WaitForChild(Net.BuyRequest) :: RemoteEvent

local side = Enums.Side.Spectator
local role = Enums.Role.Unassigned
local cash = GameConfig.Economy.StartingCash
local buyOpen = false
local menuVisible = false

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
panel.Size = UDim2.fromOffset(520, 420)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.fromOffset(12, 10)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(240, 242, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "BUY"
title.Parent = panel

local cashLabel = Instance.new("TextLabel")
cashLabel.BackgroundTransparency = 1
cashLabel.Size = UDim2.fromOffset(160, 36)
cashLabel.Position = UDim2.new(1, -172, 0, 10)
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 20
cashLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
cashLabel.TextXAlignment = Enum.TextXAlignment.Right
cashLabel.Text = "$0"
cashLabel.Parent = panel

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, -24, 0, 22)
hint.Position = UDim2.fromOffset(12, 44)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(170, 175, 190)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "B to toggle · President is pistol-only · No pickups"
hint.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Items"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(12, 72)
scroll.Size = UDim2.new(1, -24, 1, -84)
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, -24, 0, 20)
statusLabel.Position = UDim2.new(0, 12, 1, -28)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 13
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = ""
statusLabel.Parent = panel

local function setMenuVisible(visible: boolean)
	menuVisible = visible and buyOpen
	gui.Enabled = menuVisible
end

local function clearRows()
	for _, child in scroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function addRow(label: string, price: number, layoutOrder: number, onClick: () -> ())
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -4, 0, 36)
	button.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(235, 238, 245)
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = string.format("  %s", label)
	button.LayoutOrder = layoutOrder
	button.Parent = scroll

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local priceLabel = Instance.new("TextLabel")
	priceLabel.BackgroundTransparency = 1
	priceLabel.Size = UDim2.fromOffset(90, 36)
	priceLabel.Position = UDim2.new(1, -96, 0, 0)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextSize = 15
	priceLabel.TextColor3 = if price == 0
		then Color3.fromRGB(140, 200, 255)
		else Color3.fromRGB(180, 220, 160)
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Text = if price == 0 then "FREE" else string.format("$%d", price)
	priceLabel.Parent = button

	local locked = price > cash
	if locked then
		button.TextColor3 = Color3.fromRGB(120, 122, 130)
		priceLabel.TextColor3 = Color3.fromRGB(150, 100, 100)
	end

	button.MouseButton1Click:Connect(function()
		onClick()
	end)
end

local function rebuild()
	clearRows()
	cashLabel.Text = string.format("$%d", cash)
	title.Text = if role == Enums.Role.President then "BUY — President (pistols)" else "BUY"

	local order = 1
	if side == Enums.Side.Good or side == Enums.Side.Terrorist then
		for _, weapon in WeaponDefs.forSide(side) do
			local presidentBlocked = role == Enums.Role.President
				and not WeaponDefs.isPistolTier(weapon.tier)
			if not presidentBlocked then
				local capturedId = weapon.id
				addRow(
					string.format("[%s] %s", weapon.tier, weapon.displayName),
					weapon.price,
					order,
					function()
						buyRequest:FireServer({ kind = "Weapon", id = capturedId })
					end
				)
				order += 1
			end
		end
	end

	addRow(GameConfig.Armor.Light.displayName, GameConfig.Armor.Light.price, order, function()
		buyRequest:FireServer({ kind = "Armor", id = Enums.ArmorId.Light })
	end)
	order += 1
	addRow(GameConfig.Armor.Heavy.displayName, GameConfig.Armor.Heavy.price, order, function()
		buyRequest:FireServer({ kind = "Armor", id = Enums.ArmorId.Heavy })
	end)

	scroll.CanvasSize = UDim2.fromOffset(0, order * 42)
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
	if input.KeyCode == Enum.KeyCode.B and buyOpen then
		setMenuVisible(not menuVisible)
		if menuVisible then
			rebuild()
		end
	end
end)

print("[BuyMenuController] Buy menu ready (B during BUY phase).")
