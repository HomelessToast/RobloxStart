--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local MapService = require(script.Parent.MapService)
local TeamService = require(script.Parent.TeamService)

local SpawnService = {}

local frozen: { [Player]: boolean } = {}

function SpawnService.teleportToSideSpawn(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local side = TeamService.getSide(player)
	if side == Enums.Side.Spectator then
		return
	end
	root.CFrame = MapService.getSpawnCFrame(side)
end

function SpawnService.prepareCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.MaxHealth = GameConfig.MaxHealth
	humanoid.Health = GameConfig.StartingHealth
	humanoid.WalkSpeed = GameConfig.WalkSpeed

	-- Tag for combat / HUD
	character:SetAttribute("Side", TeamService.getSide(player))
	character:SetAttribute("Role", TeamService.getRole(player))

	SpawnService.teleportToSideSpawn(player)
end

function SpawnService.setFrozen(player: Player, isFrozen: boolean)
	frozen[player] = isFrozen
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid then
		humanoid.WalkSpeed = if isFrozen then 0 else GameConfig.WalkSpeed
		humanoid.JumpPower = if isFrozen then 0 else 50
	end
	if root then
		root.Anchored = isFrozen
	end
end

function SpawnService.clearFrozen(player: Player)
	frozen[player] = nil
end

return SpawnService
