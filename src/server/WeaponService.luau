--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(script.Parent.Remotes)
local TeamService = require(script.Parent.TeamService)
local LoadoutService = require(script.Parent.LoadoutService)

local WeaponService = {}

local lastShotAt: { [Player]: number } = {}
local onAmmoChanged: ((Player) -> ())? = nil

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
	local now = os.clock()
	local last = lastShotAt[player] or 0
	if now - last < GameConfig.FireRateSeconds then
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

function WeaponService.pushPlayerState(player: Player)
	local loadout = LoadoutService.get(player)
	local assignment = TeamService.getAssignment(player)
	Remotes.get(Net.PlayerState):FireClient(player, {
		side = assignment.side,
		role = assignment.role,
		alive = TeamService.hasLivingBody(player),
		ammo = if loadout then loadout.ammo else 0,
		reserve = if loadout then loadout.reserve else 0,
		weaponName = if loadout then loadout.weaponName else "",
	})
end

function WeaponService.reset()
	table.clear(lastShotAt)
end

Players.PlayerRemoving:Connect(function(player)
	lastShotAt[player] = nil
end)

return WeaponService
