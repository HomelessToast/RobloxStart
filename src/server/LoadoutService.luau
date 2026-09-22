--!strict
-- Fresh per-round loadouts. No pickups, no carry — only this service grants weapons.
-- Hotbar: up to MAX_SLOTS owned guns; active slot fires / reloads independently.
-- Visuals: procedural multi-part guns from WeaponVisuals (not Billboard-labeled sticks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local WeaponVisuals = require(ReplicatedStorage.Shared.WeaponVisuals)
local TeamService = require(script.Parent.TeamService)

export type LoadoutSlot = {
	weaponId: string,
	weaponName: string,
	ammo: number,
	reserve: number,
	magazineSize: number,
}

export type Loadout = {
	slots: { LoadoutSlot },
	activeIndex: number,
}

local MAX_SLOTS = 5

local LoadoutService = {}

local loadouts: { [Player]: Loadout } = {}
local reloadEndsAt: { [Player]: number } = {}

function LoadoutService.maxSlots(): number
	return MAX_SLOTS
end

local function syncAttributes(player: Player, slot: LoadoutSlot?)
	local role = TeamService.getRole(player)
	player:SetAttribute("PrimaryDisabled", role == Enums.Role.President)
	if slot then
		player:SetAttribute("WeaponId", slot.weaponId)
	else
		player:SetAttribute("WeaponId", "")
	end
end

local function attachActive(player: Player)
	local loadout = loadouts[player]
	local character = player.Character
	if not loadout or not character then
		return
	end
	local slot = loadout.slots[loadout.activeIndex]
	if not slot then
		WeaponVisuals.clearFromCharacter(character)
		return
	end
	WeaponVisuals.attachToCharacter(character, slot.weaponId)
	syncAttributes(player, slot)
end

function LoadoutService.clear(player: Player?)
	if player then
		loadouts[player] = nil
		reloadEndsAt[player] = nil
		if player.Character then
			WeaponVisuals.clearFromCharacter(player.Character)
		end
		return
	end
	table.clear(loadouts)
	table.clear(reloadEndsAt)
end

function LoadoutService.get(player: Player): LoadoutSlot?
	local loadout = loadouts[player]
	if not loadout then
		return nil
	end
	return loadout.slots[loadout.activeIndex]
end

function LoadoutService.getInventory(player: Player): Loadout?
	return loadouts[player]
end

function LoadoutService.getDef(player: Player): WeaponDefs.WeaponDef?
	local slot = LoadoutService.get(player)
	if not slot then
		return nil
	end
	return WeaponDefs.get(slot.weaponId)
end

function LoadoutService.owns(player: Player, weaponId: string): boolean
	local loadout = loadouts[player]
	if not loadout then
		return false
	end
	for _, slot in loadout.slots do
		if slot.weaponId == weaponId then
			return true
		end
	end
	return false
end

function LoadoutService.slotCount(player: Player): number
	local loadout = loadouts[player]
	return if loadout then #loadout.slots else 0
end

local function makeSlot(def: WeaponDefs.WeaponDef): LoadoutSlot
	return {
		weaponId = def.id,
		weaponName = def.displayName,
		ammo = def.magazine,
		reserve = def.reserve,
		magazineSize = def.magazine,
	}
end

function LoadoutService.equipWeapon(player: Player, def: WeaponDefs.WeaponDef): LoadoutSlot
	-- Replace-all path used by round grant: single default pistol.
	local slot = makeSlot(def)
	loadouts[player] = {
		slots = { slot },
		activeIndex = 1,
	}
	reloadEndsAt[player] = nil
	attachActive(player)
	return slot
end

function LoadoutService.addWeapon(
	player: Player,
	def: WeaponDefs.WeaponDef
): (LoadoutSlot?, string?)
	if LoadoutService.owns(player, def.id) then
		return nil, "owned"
	end
	local loadout = loadouts[player]
	if not loadout then
		local slot = LoadoutService.equipWeapon(player, def)
		return slot, nil
	end
	if #loadout.slots >= MAX_SLOTS then
		return nil, "full"
	end
	local slot = makeSlot(def)
	table.insert(loadout.slots, slot)
	loadout.activeIndex = #loadout.slots
	reloadEndsAt[player] = nil
	attachActive(player)
	return slot, nil
end

function LoadoutService.selectSlot(player: Player, index: number): boolean
	local loadout = loadouts[player]
	if not loadout then
		return false
	end
	if index < 1 or index > #loadout.slots then
		return false
	end
	if loadout.activeIndex == index then
		return true
	end
	loadout.activeIndex = index
	reloadEndsAt[player] = nil
	attachActive(player)
	return true
end

function LoadoutService.isReloading(player: Player): boolean
	local ends = reloadEndsAt[player]
	return ends ~= nil and os.clock() < ends
end

function LoadoutService.beginReload(player: Player): boolean
	if LoadoutService.isReloading(player) then
		return false
	end
	local slot = LoadoutService.get(player)
	local def = LoadoutService.getDef(player)
	if not slot or not def then
		return false
	end
	if slot.ammo >= slot.magazineSize then
		return false
	end
	if slot.reserve <= 0 then
		return false
	end
	local duration = math.max(0.35, def.reloadTime)
	reloadEndsAt[player] = os.clock() + duration
	local weaponId = slot.weaponId
	local expectedEnd = reloadEndsAt[player]
	task.delay(duration, function()
		if reloadEndsAt[player] ~= expectedEnd then
			return
		end
		reloadEndsAt[player] = nil
		local current = LoadoutService.get(player)
		if not current or current.weaponId ~= weaponId then
			return
		end
		local need = current.magazineSize - current.ammo
		if need <= 0 or current.reserve <= 0 then
			return
		end
		local take = math.min(need, current.reserve)
		current.reserve -= take
		current.ammo += take
	end)
	return true
end

function LoadoutService.grant(player: Player): LoadoutSlot
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

function LoadoutService.consumeAmmo(player: Player): boolean
	if LoadoutService.isReloading(player) then
		return false
	end
	local slot = LoadoutService.get(player)
	if not slot then
		return false
	end
	-- Empty mag blocks fire until explicit reload (R).
	if slot.ammo <= 0 then
		return false
	end
	slot.ammo -= 1
	return true
end

function LoadoutService.denyPickup(_player: Player)
	return false
end

-- Re-attach visual after respawn if loadout still held.
Players.PlayerRemoving:Connect(function(player)
	loadouts[player] = nil
	reloadEndsAt[player] = nil
end)

return LoadoutService
