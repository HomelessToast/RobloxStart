--!strict
-- Fresh per-round loadouts. No pickups, no carry — only this service grants weapons.
-- Visuals: procedural multi-part guns from WeaponVisuals (not Billboard-labeled sticks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local WeaponVisuals = require(ReplicatedStorage.Shared.WeaponVisuals)
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

function LoadoutService.clear(player: Player?)
	if player then
		loadouts[player] = nil
		if player.Character then
			WeaponVisuals.clearFromCharacter(player.Character)
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

	local character = player.Character
	if character then
		WeaponVisuals.attachToCharacter(character, def.id)
	end

	local role = TeamService.getRole(player)
	player:SetAttribute("PrimaryDisabled", role == Enums.Role.President)
	player:SetAttribute("WeaponId", def.id)

	return loadout
end

function LoadoutService.grant(player: Player): Loadout
	local side = TeamService.getSide(player)
	local role = TeamService.getRole(player)
	local def = WeaponDefs.defaultPistol(side)

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

function LoadoutService.denyPickup(_player: Player)
	return false
end

-- Re-attach visual after respawn if loadout still held.
Players.PlayerRemoving:Connect(function(player)
	loadouts[player] = nil
end)

return LoadoutService
