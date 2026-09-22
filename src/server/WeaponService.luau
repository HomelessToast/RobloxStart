--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local WeaponDefs = require(ReplicatedStorage.Shared.WeaponDefs)
local Remotes = require(script.Parent.Remotes)
local TeamService = require(script.Parent.TeamService)
local LoadoutService = require(script.Parent.LoadoutService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local AbilityService = require(script.Parent.AbilityService)

local WeaponService = {}

local lastShotAt: { [Player]: number } = {}
local onAmmoChanged: ((Player) -> ())? = nil
local buyOpenGetter: (() -> boolean)? = nil

function WeaponService.setBuyOpenGetter(getter: () -> boolean)
	buyOpenGetter = getter
end

function WeaponService.setAmmoChangedCallback(callback: (Player) -> ())
	onAmmoChanged = callback
end

function WeaponService.canFire(player: Player): boolean
	local assignment = TeamService.getAssignment(player)
	if assignment.side == Enums.Side.Spectator then
		return false
	end
	if not TeamService.hasLivingBody(player) then
		return false
	end
	local def = LoadoutService.getDef(player)
	if not def then
		return false
	end
	-- Gate 2: President cannot hold a primary even if somehow granted.
	if
		TeamService.getRole(player) == Enums.Role.President
		and not WeaponDefs.isPistolTier(def.tier)
	then
		return false
	end
	if LoadoutService.isReloading(player) then
		return false
	end
	-- Sprint and dodge/recovery block fire (design §5.3 / movement model).
	if not AbilityService.canFire(player) then
		return false
	end
	local now = os.clock()
	local last = lastShotAt[player] or 0
	if now - last < WeaponDefs.fireInterval(def) then
		return false
	end
	return true
end

function WeaponService.tryConsumeShot(player: Player): boolean
	if not WeaponService.canFire(player) then
		return false
	end
	if not LoadoutService.consumeAmmo(player) then
		return false
	end
	lastShotAt[player] = os.clock()
	if onAmmoChanged then
		onAmmoChanged(player)
	end
	return true
end

local function hotbarPayload(player: Player): { any }
	local inv = LoadoutService.getInventory(player)
	local list = {}
	if not inv then
		return list
	end
	for i, slot in inv.slots do
		table.insert(list, {
			slot = i,
			weaponId = slot.weaponId,
			weaponName = slot.weaponName,
			ammo = slot.ammo,
			reserve = slot.reserve,
		})
	end
	return list
end

function WeaponService.pushPlayerState(player: Player)
	local loadout = LoadoutService.get(player)
	local inv = LoadoutService.getInventory(player)
	local assignment = TeamService.getAssignment(player)
	local armor = PlayerStateService.getArmor(player)
	Remotes.get(Net.PlayerState):FireClient(player, {
		side = assignment.side,
		role = assignment.role,
		alive = TeamService.hasLivingBody(player),
		ammo = if loadout then loadout.ammo else 0,
		reserve = if loadout then loadout.reserve else 0,
		weaponName = if loadout then loadout.weaponName else "",
		weaponId = if loadout then loadout.weaponId else "",
		cash = EconomyService.getCash(player),
		armorPool = armor.pool,
		armorMax = armor.maxPool,
		hasHelmet = armor.hasHelmet,
		buyOpen = if buyOpenGetter then buyOpenGetter() else false,
		hotbar = hotbarPayload(player),
		activeSlot = if inv then inv.activeIndex else 1,
		reloading = LoadoutService.isReloading(player),
	})
end

function WeaponService.handleSelectWeapon(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local slot = payload.slot
	if typeof(slot) ~= "number" then
		return
	end
	local index = math.floor(slot)
	if LoadoutService.selectSlot(player, index) then
		WeaponService.pushPlayerState(player)
	end
end

function WeaponService.handleReload(player: Player)
	if not TeamService.hasLivingBody(player) then
		return
	end
	if LoadoutService.beginReload(player) then
		WeaponService.pushPlayerState(player)
		local def = LoadoutService.getDef(player)
		local duration = if def then math.max(0.35, def.reloadTime) else 1.5
		task.delay(duration + 0.05, function()
			if player.Parent then
				WeaponService.pushPlayerState(player)
			end
		end)
	else
		WeaponService.pushPlayerState(player)
	end
end

function WeaponService.init()
	Remotes.get(Net.SelectWeapon).OnServerEvent:Connect(function(player, payload)
		WeaponService.handleSelectWeapon(player, payload)
	end)
	Remotes.get(Net.ReloadRequest).OnServerEvent:Connect(function(player, _payload)
		WeaponService.handleReload(player)
	end)
end

function WeaponService.reset()
	table.clear(lastShotAt)
end

Players.PlayerRemoving:Connect(function(player)
	lastShotAt[player] = nil
end)

return WeaponService
