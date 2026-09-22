--!strict
--[[
	Role uniforms on spawn / role assign. Owns character clothing only —
	does not touch weapons, buy, dodge, or combat.

	Hook: SpawnService.prepareCharacter → applyRole
	Lobby return: teleportToLobby / teleportToReadyPad → restoreAvatar
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local RoleAppearances = require(ReplicatedStorage.Shared.RoleAppearances)

local AppearanceService = {}

local ATTR_APPLIED = "VipRoleAppearance"

local function clearLayeredClothing(description: HumanoidDescription)
	-- Keep hair / face / neck / hats so players stay recognizable; strip torso
	-- layered pieces that would cover the classic shirt/pants kit.
	description.GraphicTShirt = 0
	description.ShirtAccessory = 0
	description.TShirtAccessory = 0
	description.SweaterAccessory = 0
	description.JacketAccessory = 0
	description.PantsAccessory = 0
	description.ShortsAccessory = 0
	description.DressSkirtAccessory = 0
	description.LeftShoeAccessory = 0
	description.RightShoeAccessory = 0
end

local function stripCoveringAccessories(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") then
			local accessoryType = child.AccessoryType
			if
				accessoryType == Enum.AccessoryType.Jacket
				or accessoryType == Enum.AccessoryType.Shirt
				or accessoryType == Enum.AccessoryType.TShirt
				or accessoryType == Enum.AccessoryType.Sweater
				or accessoryType == Enum.AccessoryType.Pants
				or accessoryType == Enum.AccessoryType.Shorts
				or accessoryType == Enum.AccessoryType.DressSkirt
				or accessoryType == Enum.AccessoryType.LeftShoe
				or accessoryType == Enum.AccessoryType.RightShoe
				or accessoryType == Enum.AccessoryType.Waist
				or accessoryType == Enum.AccessoryType.Back
				or accessoryType == Enum.AccessoryType.Front
				or accessoryType == Enum.AccessoryType.Shoulder
			then
				child:Destroy()
			end
		elseif child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
end

local function baseDescription(player: Player, humanoid: Humanoid): HumanoidDescription
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if ok and desc then
		return desc
	end
	return humanoid:GetAppliedDescription()
end

--- Apply the kit for the player's current TeamService role (no-op if Unassigned).
function AppearanceService.applyRole(player: Player, role: string?)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local resolved = role or (character:GetAttribute("Role") :: string?) or Enums.Role.Unassigned
	local kit = RoleAppearances.getKit(resolved)
	if not kit then
		character:SetAttribute(ATTR_APPLIED, Enums.Role.Unassigned)
		return
	end

	local description = baseDescription(player, humanoid)
	clearLayeredClothing(description)
	description.Shirt = kit.shirtAssetId
	description.Pants = kit.pantsAssetId

	stripCoveringAccessories(character)

	local ok, err = pcall(function()
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not ok then
		warn(
			string.format(
				"[AppearanceService] ApplyDescription failed for %s role=%s: %s",
				player.Name,
				resolved,
				tostring(err)
			)
		)
		-- Fallback: classic Shirt/Pants siblings (HumanoidDescription is preferred).
		local shirt = character:FindFirstChildOfClass("Shirt") :: Shirt?
		if not shirt then
			shirt = Instance.new("Shirt")
			shirt.Parent = character
		end
		local pants = character:FindFirstChildOfClass("Pants") :: Pants?
		if not pants then
			pants = Instance.new("Pants")
			pants.Parent = character
		end
		shirt.ShirtTemplate = "rbxassetid://" .. tostring(kit.shirtAssetId)
		pants.PantsTemplate = "rbxassetid://" .. tostring(kit.pantsAssetId)
	end

	character:SetAttribute(ATTR_APPLIED, resolved)
end

--- Restore the player's own avatar (lobby / ready pad).
function AppearanceService.restoreAvatar(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local ok, err = pcall(function()
		local description = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not ok then
		warn(
			string.format(
				"[AppearanceService] restoreAvatar failed for %s: %s",
				player.Name,
				tostring(err)
			)
		)
	end
	character:SetAttribute(ATTR_APPLIED, Enums.Role.Unassigned)
end

return AppearanceService
