--!strict
-- Bottom-center hotbar from PlayerState.hotbar / activeSlot.
-- Keys 1-5 select · mouse wheel cycles · click slot · FireServer SelectWeapon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local selectWeapon = remotes:WaitForChild(Net.SelectWeapon) :: RemoteEvent

type HotbarSlot = {
	slot: number,
	weaponId: string,
	weaponName: string,
	ammo: number,
	reserve: number,
}

local hotbar: { HotbarSlot } = {}
local activeSlot = 1
local roundState = Enums.RoundState.Lobby
local nameFlashUntil = 0

local gui = Instance.new("ScreenGui")
gui.Name = "VipHotbar"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -28)
bar.Size = UDim2.fromOffset(420, 58)
bar.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
bar.BackgroundTransparency = 0.25
bar.BorderSizePixel = 0
bar.Parent = gui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 8)
barCorner.Parent = bar

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 6)
layout.Parent = bar

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = bar

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "WeaponFlash"
nameLabel.BackgroundTransparency = 1
nameLabel.AnchorPoint = Vector2.new(0.5, 1)
nameLabel.Position = UDim2.new(0.5, 0, 1, -92)
nameLabel.Size = UDim2.fromOffset(360, 28)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 18
nameLabel.TextColor3 = Color3.fromRGB(240, 242, 248)
nameLabel.TextStrokeTransparency = 0.45
nameLabel.Text = ""
nameLabel.Visible = false
nameLabel.Parent = gui

local slotButtons: { TextButton } = {}

local function isLobbyLike(): boolean
	return roundState == Enums.RoundState.Lobby
		or roundState == Enums.RoundState.RoundEnd
		or roundState == Enums.RoundState.Intermission
		or roundState == Enums.RoundState.MatchEnd
end

local function shouldShow(): boolean
	return #hotbar > 0 and not isLobbyLike()
end

local function flashWeaponName()
	local active: HotbarSlot? = nil
	for _, slot in hotbar do
		if slot.slot == activeSlot then
			active = slot
			break
		end
	end
	if not active then
		nameLabel.Visible = false
		return
	end
	nameLabel.Text = string.format("%s  %d / %d", active.weaponName, active.ammo, active.reserve)
	nameLabel.Visible = true
	nameFlashUntil = os.clock() + 1.6
end

local function requestSlot(slotIndex: number)
	if slotIndex < 1 or slotIndex > #hotbar then
		return
	end
	local entry = hotbar[slotIndex]
	if not entry then
		return
	end
	selectWeapon:FireServer({ slot = entry.slot })
end

local function rebuildSlots()
	for _, btn in slotButtons do
		btn:Destroy()
	end
	table.clear(slotButtons)

	for i, entry in hotbar do
		local btn = Instance.new("TextButton")
		btn.Name = "Slot" .. tostring(entry.slot)
		btn.Size = UDim2.fromOffset(72, 46)
		btn.AutoButtonColor = true
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.TextWrapped = true
		btn.Text = string.format("%d\n%s", entry.slot, entry.weaponName)
		btn.TextColor3 = Color3.fromRGB(230, 234, 245)
		btn.BorderSizePixel = 0
		local selected = entry.slot == activeSlot
		btn.BackgroundColor3 = if selected
			then Color3.fromRGB(55, 95, 140)
			else Color3.fromRGB(28, 32, 42)
		btn.Parent = bar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = if selected then 1.5 else 1
		stroke.Color = if selected
			then Color3.fromRGB(140, 200, 255)
			else Color3.fromRGB(60, 68, 85)
		stroke.Transparency = 0.25
		stroke.Parent = btn

		local captured = i
		btn.MouseButton1Click:Connect(function()
			requestSlot(captured)
		end)
		table.insert(slotButtons, btn)
	end

	gui.Enabled = shouldShow()
	if gui.Enabled then
		flashWeaponName()
	else
		nameLabel.Visible = false
	end
end

local function cycleSlot(delta: number)
	if #hotbar == 0 then
		return
	end
	local currentIndex = 1
	for i, entry in hotbar do
		if entry.slot == activeSlot then
			currentIndex = i
			break
		end
	end
	local nextIndex = ((currentIndex - 1 + delta) % #hotbar) + 1
	requestSlot(nextIndex)
end

remotes:WaitForChild(Net.PlayerState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	hotbar = {}
	if typeof(payload.hotbar) == "table" then
		for _, entry in payload.hotbar do
			if typeof(entry) == "table" and typeof(entry.slot) == "number" then
				table.insert(hotbar, {
					slot = math.floor(entry.slot),
					weaponId = tostring(entry.weaponId or ""),
					weaponName = tostring(entry.weaponName or entry.weaponId or "?"),
					ammo = if typeof(entry.ammo) == "number" then entry.ammo else 0,
					reserve = if typeof(entry.reserve) == "number" then entry.reserve else 0,
				})
			end
		end
	end
	if typeof(payload.activeSlot) == "number" then
		activeSlot = math.floor(payload.activeSlot)
	end
	rebuildSlots()
end)

remotes:WaitForChild(Net.RoundState).OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.state) == "string" then
		roundState = payload.state
	end
	gui.Enabled = shouldShow()
	if not gui.Enabled then
		nameLabel.Visible = false
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not shouldShow() then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.One then
		requestSlot(1)
	elseif key == Enum.KeyCode.Two then
		requestSlot(2)
	elseif key == Enum.KeyCode.Three then
		requestSlot(3)
	elseif key == Enum.KeyCode.Four then
		requestSlot(4)
	elseif key == Enum.KeyCode.Five then
		requestSlot(5)
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not shouldShow() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local z = input.Position.Z
		if z > 0 then
			cycleSlot(-1)
		elseif z < 0 then
			cycleSlot(1)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		if nameLabel.Visible and os.clock() > nameFlashUntil then
			nameLabel.Visible = false
		end
	end
end)

print("[HotbarController] Hotbar 1-5 · wheel cycle · click to select.")
