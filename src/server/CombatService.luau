--!strict
-- Server-authoritative hits. Client reports intent; server raycasts and applies damage.
-- Friendly fire is off: same-side damage is discarded before it lands.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(script.Parent.Remotes)
local TeamService = require(script.Parent.TeamService)
local LoadoutService = require(script.Parent.LoadoutService)
local WeaponService = require(script.Parent.WeaponService)

local CombatService = {}

local roundLive = false
local onPlayerDied: ((Player, Player?) -> ())? = nil

function CombatService.setRoundLive(isLive: boolean)
	roundLive = isLive
end

function CombatService.setDeathCallback(callback: (Player, Player?) -> ())
	onPlayerDied = callback
end

local function characterFromPart(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return model
	end
	return nil
end

local function playerFromCharacter(character: Model): Player?
	return Players:GetPlayerFromCharacter(character)
end

function CombatService.applyDamage(attacker: Player, victim: Player, amount: number)
	if not roundLive then
		return
	end
	if not GameConfig.FriendlyFire then
		if TeamService.getSide(attacker) == TeamService.getSide(victim) then
			return
		end
	end
	if not TeamService.hasLivingBody(victim) then
		return
	end

	local character = victim.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	humanoid:TakeDamage(amount)

	if humanoid.Health <= 0 then
		character:SetAttribute("Alive", false)
		if onPlayerDied then
			onPlayerDied(victim, attacker)
		end
	end
end

function CombatService.handleFireShot(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.origin) ~= "Vector3" or typeof(payload.direction) ~= "Vector3" then
		return
	end
	if not roundLive then
		return
	end
	if not WeaponService.tryConsumeShot(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local origin = payload.origin :: Vector3
	local direction = payload.direction :: Vector3
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit

	-- Origin must be near the shooter's head/root (anti-teleport shot).
	if (origin - root.Position).Magnitude > GameConfig.HitValidationSlopStuds + 4 then
		origin = root.Position + Vector3.new(0, 1.5, 0)
	end

	local loadout = LoadoutService.get(player)
	if not loadout then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction * GameConfig.MaxShotDistance, params)
	if not result then
		return
	end

	local hitCharacter = characterFromPart(result.Instance)
	if not hitCharacter then
		return
	end
	local victim = playerFromCharacter(hitCharacter)
	if not victim or victim == player then
		return
	end

	CombatService.applyDamage(player, victim, loadout.damage)
end

function CombatService.init()
	Remotes.get(Net.FireShot).OnServerEvent:Connect(function(player, payload)
		CombatService.handleFireShot(player, payload)
	end)
end

return CombatService
