--!strict
-- Health + armor pool. Armor does not carry between rounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)

export type ArmorRuntime = {
	armorId: string,
	pool: number,
	maxPool: number,
	hasHelmet: boolean,
	paidPrice: number,
}

local PlayerStateService = {}

local armorByPlayer: { [Player]: ArmorRuntime } = {}

local function emptyArmor(): ArmorRuntime
	return {
		armorId = Enums.ArmorId.None,
		pool = 0,
		maxPool = 0,
		hasHelmet = false,
		paidPrice = 0,
	}
end

function PlayerStateService.resetArmor(player: Player)
	armorByPlayer[player] = emptyArmor()
end

function PlayerStateService.resetAllArmor()
	table.clear(armorByPlayer)
end

function PlayerStateService.getArmor(player: Player): ArmorRuntime
	local armor = armorByPlayer[player]
	if not armor then
		armor = emptyArmor()
		armorByPlayer[player] = armor
	end
	return armor
end

function PlayerStateService.setArmor(player: Player, armor: ArmorRuntime)
	armorByPlayer[player] = armor
	local character = player.Character
	if character then
		character:SetAttribute("ArmorPool", armor.pool)
		character:SetAttribute("ArmorMax", armor.maxPool)
		character:SetAttribute("HasHelmet", armor.hasHelmet)
	end
end

function PlayerStateService.applyArmorDamage(player: Player, amount: number): number
	local armor = PlayerStateService.getArmor(player)
	armor.pool = math.max(0, armor.pool - amount)
	local character = player.Character
	if character then
		character:SetAttribute("ArmorPool", armor.pool)
	end
	return armor.pool
end

Players.PlayerRemoving:Connect(function(player)
	armorByPlayer[player] = nil
end)

return PlayerStateService
