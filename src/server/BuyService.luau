--!strict
-- Purchase gate 1 of 2. Validates cash, side, BUY phase, and President pistol lock.
-- Multiple guns allowed during BUY — each purchase adds a hotbar slot (no auto-replace).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local Remotes = require(script.Parent.Remotes)
local TeamService = require(script.Parent.TeamService)
local EconomyService = require(script.Parent.EconomyService)
local LoadoutService = require(script.Parent.LoadoutService)
local PlayerStateService = require(script.Parent.PlayerStateService)

local BuyService = {}

local buyOpen = false
local onPurchaseApplied: ((Player) -> ())? = nil

function BuyService.setOpen(isOpen: boolean)
	buyOpen = isOpen
end

function BuyService.isOpen(): boolean
	return buyOpen
end

function BuyService.setPurchaseCallback(callback: (Player) -> ())
	onPurchaseApplied = callback
end

local function reply(player: Player, result: string, id: string?, message: string?)
	Remotes.get(Net.BuyResult):FireClient(player, {
		result = result,
		id = id,
		cash = EconomyService.getCash(player),
		message = message or result,
	})
	if result == Enums.PurchaseResult.Ok and onPurchaseApplied then
		onPurchaseApplied(player)
	end
end

function BuyService.purchaseWeapon(player: Player, weaponId: string): string
	if not buyOpen then
		reply(player, Enums.PurchaseResult.NotBuyPhase, weaponId, "Buy phase closed")
		return Enums.PurchaseResult.NotBuyPhase
	end
	if not TeamService.hasLivingBody(player) then
		reply(player, Enums.PurchaseResult.Dead, weaponId, "Dead players cannot buy")
		return Enums.PurchaseResult.Dead
	end

	local def = WeaponDefs.get(weaponId)
	if not def then
		reply(player, Enums.PurchaseResult.UnknownItem, weaponId, "Unknown weapon")
		return Enums.PurchaseResult.UnknownItem
	end

	local side = TeamService.getSide(player)
	if def.side ~= side then
		reply(player, Enums.PurchaseResult.WrongSide, weaponId, "Wrong arsenal")
		return Enums.PurchaseResult.WrongSide
	end

	local role = TeamService.getRole(player)
	if role == Enums.Role.President and not WeaponDefs.isPistolTier(def.tier) then
		reply(
			player,
			Enums.PurchaseResult.PresidentPrimaryLocked,
			weaponId,
			"President is pistol-only"
		)
		return Enums.PurchaseResult.PresidentPrimaryLocked
	end

	if LoadoutService.owns(player, weaponId) then
		reply(player, Enums.PurchaseResult.AlreadyOwned, weaponId, "Already in hotbar")
		return Enums.PurchaseResult.AlreadyOwned
	end

	if LoadoutService.slotCount(player) >= LoadoutService.maxSlots() then
		reply(
			player,
			Enums.PurchaseResult.HotbarFull,
			weaponId,
			string.format("Hotbar full (%d)", LoadoutService.maxSlots())
		)
		return Enums.PurchaseResult.HotbarFull
	end

	local price = def.price
	if price > 0 and not EconomyService.trySpend(player, price) then
		reply(player, Enums.PurchaseResult.CannotAfford, weaponId, "Not enough cash")
		return Enums.PurchaseResult.CannotAfford
	end

	local _, err = LoadoutService.addWeapon(player, def)
	if err == "full" then
		if price > 0 then
			EconomyService.refund(player, price)
		end
		reply(player, Enums.PurchaseResult.HotbarFull, weaponId, "Hotbar full")
		return Enums.PurchaseResult.HotbarFull
	end
	if err == "owned" then
		if price > 0 then
			EconomyService.refund(player, price)
		end
		reply(player, Enums.PurchaseResult.AlreadyOwned, weaponId, "Already in hotbar")
		return Enums.PurchaseResult.AlreadyOwned
	end

	reply(player, Enums.PurchaseResult.Ok, weaponId, "Purchased " .. def.displayName)
	return Enums.PurchaseResult.Ok
end

function BuyService.purchaseArmor(player: Player, armorId: string): string
	if not buyOpen then
		reply(player, Enums.PurchaseResult.NotBuyPhase, armorId, "Buy phase closed")
		return Enums.PurchaseResult.NotBuyPhase
	end
	if not TeamService.hasLivingBody(player) then
		reply(player, Enums.PurchaseResult.Dead, armorId, "Dead players cannot buy")
		return Enums.PurchaseResult.Dead
	end

	local armorDef = if armorId == Enums.ArmorId.Light
		then GameConfig.Armor.Light
		elseif armorId == Enums.ArmorId.Heavy then GameConfig.Armor.Heavy
		else nil

	if not armorDef then
		reply(player, Enums.PurchaseResult.UnknownItem, armorId, "Unknown armor")
		return Enums.PurchaseResult.UnknownItem
	end

	local current = PlayerStateService.getArmor(player)
	if current.armorId == armorId and current.pool >= armorDef.pool then
		reply(player, Enums.PurchaseResult.AlreadyOwned, armorId, "Armor already equipped")
		return Enums.PurchaseResult.AlreadyOwned
	end

	-- Upgrade path: charge full price, refund previous armor purchase this BUY.
	if current.paidPrice > 0 then
		EconomyService.refund(player, current.paidPrice)
	end

	if not EconomyService.trySpend(player, armorDef.price) then
		-- Re-apply previous charge if we refunded
		if current.paidPrice > 0 then
			EconomyService.trySpend(player, current.paidPrice)
		end
		reply(player, Enums.PurchaseResult.CannotAfford, armorId, "Not enough cash")
		return Enums.PurchaseResult.CannotAfford
	end

	PlayerStateService.setArmor(player, {
		armorId = armorId,
		pool = armorDef.pool,
		maxPool = armorDef.pool,
		hasHelmet = armorDef.hasHelmet,
		paidPrice = armorDef.price,
	})
	reply(player, Enums.PurchaseResult.Ok, armorId, "Purchased " .. armorDef.displayName)
	return Enums.PurchaseResult.Ok
end

function BuyService.handleRequest(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local id = payload.id
	if typeof(id) ~= "string" then
		return
	end
	if kind == "Weapon" then
		BuyService.purchaseWeapon(player, id)
	elseif kind == "Armor" then
		BuyService.purchaseArmor(player, id)
	end
end

function BuyService.init()
	Remotes.get(Net.BuyRequest).OnServerEvent:Connect(function(player, payload)
		BuyService.handleRequest(player, payload)
	end)
end

return BuyService
