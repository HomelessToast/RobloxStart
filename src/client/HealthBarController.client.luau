--!strict
-- Billboard health bars above every player character.

local Players = game:GetService("Players")

local BAR_NAME = "VipHealthBar"

local function clearBar(character: Model)
	local head = character:FindFirstChild("Head")
	if head then
		local existing = head:FindFirstChild(BAR_NAME)
		if existing then
			existing:Destroy()
		end
	end
end

local function attachBar(character: Model)
	clearBar(character)
	local head = character:WaitForChild("Head", 8)
	if not head or not head:IsA("BasePart") then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 8)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = BAR_NAME
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(90, 10)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 220
	billboard.Parent = head

	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	local function refresh()
		local maxHp = math.max(humanoid.MaxHealth, 1)
		local ratio = math.clamp(humanoid.Health / maxHp, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		if ratio > 0.55 then
			fill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
		elseif ratio > 0.3 then
			fill.BackgroundColor3 = Color3.fromRGB(230, 180, 70)
		else
			fill.BackgroundColor3 = Color3.fromRGB(220, 80, 70)
		end
		billboard.Enabled = humanoid.Health > 0
	end

	refresh()
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.defer(attachBar, character)
	end)
	if player.Character then
		task.defer(attachBar, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

print("[HealthBarController] Health bars above players.")
