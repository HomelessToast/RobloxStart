--!strict
-- Fresh per-round loadouts. No pickups, no carry — only this service grants weapons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local TeamService = require(script.Parent.TeamService)

export type Loadout = {
	weaponId: string,
	weaponName: string,
	ammo: number,
	reserve: number,
	damage: number,
}

local LoadoutService = {}

local loadouts: { [Player]: Loadout } = {}

function LoadoutService.clear(player: Player?)
	if player then
		loadouts[player] = nil
		return
	end
	table.clear(loadouts)
end

function LoadoutService.grant(player: Player): Loadout
	local side = TeamService.getSide(player)
	local role = TeamService.getRole(player)
	local def = if side == Enums.Side.Good
		then GameConfig.Weapons.GoodPistol
		else GameConfig.Weapons.TerroristPistol

	-- President is pistol-only; slice 0 only has pistols anyway.
	local loadout: Loadout = {
		weaponId = def.id,
		weaponName = def.displayName,
		ammo = def.magazine,
		reserve = def.reserve,
		damage = def.damage,
	}

	if role == Enums.Role.President then
		-- Explicit primary lock marker for later buy/weapon gates.
		player:SetAttribute("PrimaryDisabled", true)
	else
		player:SetAttribute("PrimaryDisabled", false)
	end

	loadouts[player] = loadout
	return loadout
end

function LoadoutService.get(player: Player): Loadout?
	return loadouts[player]
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
		local mag = if TeamService.getSide(player) == Enums.Side.Good
			then GameConfig.Weapons.GoodPistol.magazine
			else GameConfig.Weapons.TerroristPistol.magazine
		local reload = math.min(mag, loadout.reserve)
		loadout.reserve -= reload
		loadout.ammo = reload
	end
	if loadout.ammo <= 0 then
		return false
	end
	loadout.ammo -= 1
	return true
end

return LoadoutService
