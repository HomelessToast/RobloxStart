--!strict
-- Fresh per-round loadouts. No pickups, no carry — only this service grants weapons.
-- Greybox tools: a simple Part welded to the right hand as a visual stand-in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local TeamService = require(script.Parent.TeamService)

export type Loadout = {
	weaponId: string,
	weaponName: string,
	ammo: number,
	reserve: number,
	magazineSize: number,
}

local LoadoutService = {}

local loadouts: { [Player]: Loadout } = {}
local toolFolderName = "VipWeaponVisual"

local function clearVisual(character: Model)
	local existing = character:FindFirstChild(toolFolderName)
	if existing then
		existing:Destroy()
	end
end

local function attachVisual(player: Player, def: WeaponDefs.WeaponDef)
	local character = player.Character
	if not character then
		return
	end
	clearVisual(character)

	local rightHand = character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")
	if not rightHand or not rightHand:IsA("BasePart") then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = toolFolderName
	folder.Parent = character

	local length = if def.slot == "Primary" then 3.2 else 1.6
	local thickness = if def.pellets > 1 then 0.55 else 0.35

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(thickness, thickness, length)
	barrel.Color = def.color
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Massless = true
	barrel.CastShadow = false
	barrel.Parent = folder

	local weld = Instance.new("Weld")
	weld.Part0 = rightHand
	weld.Part1 = barrel
	weld.C0 = CFrame.new(0, -0.2, -length * 0.35)
	weld.Parent = barrel
end

function LoadoutService.clear(player: Player?)
	if player then
		loadouts[player] = nil
		if player.Character then
			clearVisual(player.Character)
		end
		return
	end
	table.clear(loadouts)
end

function LoadoutService.equipWeapon(player: Player, def: WeaponDefs.WeaponDef): Loadout
	local loadout: Loadout = {
		weaponId = def.id,
		weaponName = def.displayName,
		ammo = def.magazine,
		reserve = def.reserve,
		magazineSize = def.magazine,
	}
	loadouts[player] = loadout
	attachVisual(player, def)

	local role = TeamService.getRole(player)
	player:SetAttribute("PrimaryDisabled", role == Enums.Role.President)
	player:SetAttribute("WeaponId", def.id)

	return loadout
end

function LoadoutService.grant(player: Player): Loadout
	local side = TeamService.getSide(player)
	local role = TeamService.getRole(player)
	local def = WeaponDefs.defaultPistol(side)

	-- President pistol lock marker (gate 2 enforcement lives in Buy/Weapon services).
	if role == Enums.Role.President then
		player:SetAttribute("PrimaryDisabled", true)
	else
		player:SetAttribute("PrimaryDisabled", false)
	end

	return LoadoutService.equipWeapon(player, def)
end

function LoadoutService.get(player: Player): Loadout?
	return loadouts[player]
end

function LoadoutService.getDef(player: Player): WeaponDefs.WeaponDef?
	local loadout = loadouts[player]
	if not loadout then
		return nil
	end
	return WeaponDefs.get(loadout.weaponId)
end

function LoadoutService.consumeAmmo(player: Player): boolean
	local loadout = loadouts[player]
	if not loadout then
		return false
	end
	if loadout.ammo <= 0 then
		if loadout.reserve <= 0 then
			return false
		end
		local reload = math.min(loadout.magazineSize, loadout.reserve)
		loadout.reserve -= reload
		loadout.ammo = reload
	end
	if loadout.ammo <= 0 then
		return false
	end
	loadout.ammo -= 1
	return true
end

-- Explicitly no corpse weapon pickups — there is no API to loot another player.
function LoadoutService.denyPickup(_player: Player)
	return false
end

Players.PlayerRemoving:Connect(function(player)
	loadouts[player] = nil
end)

return LoadoutService
