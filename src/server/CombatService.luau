--!strict
-- Server-authoritative hits. Client reports intent; server raycasts and applies damage.
-- Friendly fire is off: same-side damage is discarded before it reaches the armor pool.
-- No weapon pickups from corpses — LoadoutService is the only grant path.
-- Broadcasts WeaponFired for client bullet VFX / muzzle / sounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Remotes = require(script.Parent.Remotes)
local TeamService = require(script.Parent.TeamService)
local LoadoutService = require(script.Parent.LoadoutService)
local WeaponService = require(script.Parent.WeaponService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local EconomyService = require(script.Parent.EconomyService)
local CaptureService = require(script.Parent.CaptureService)

local CombatService = {}

local roundLive = false
local onPlayerDied: ((Player, Player?) -> ())? = nil

local function rngFromShot(player: Player, origin: Vector3, direction: Vector3): () -> number
	local seed = player.UserId
		+ math.floor(origin.X * 10)
		+ math.floor(origin.Z * 10)
		+ math.floor(direction.X * 1000)
		+ math.floor(os.clock() * 1000)
	local state = seed % 2147483647
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

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

local function isHeadPart(part: BasePart): boolean
	local name = string.lower(part.Name)
	return name == "head" or string.find(name, "head", 1, true) ~= nil
end

function CombatService.applyDamage(
	attacker: Player,
	victim: Player,
	healthDamage: number,
	armorDamage: number
)
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

	if armorDamage > 0 then
		PlayerStateService.applyArmorDamage(victim, armorDamage)
	end

	if healthDamage > 0 then
		humanoid:TakeDamage(healthDamage)
	end

	if humanoid.Health <= 0 then
		character:SetAttribute("Alive", false)
		local wasPresident = TeamService.getRole(victim) == Enums.Role.President
		local captureActive = CaptureService.isActive()
		EconomyService.onKill(attacker, victim, {
			victimWasPresident = wasPresident,
			captureActive = captureActive and wasPresident,
		})
		if onPlayerDied then
			onPlayerDied(victim, attacker)
		end
	end
end

local function resolvePellet(
	attacker: Player,
	origin: Vector3,
	direction: Vector3,
	def: any,
	params: RaycastParams
): (Vector3, boolean)
	local result = Workspace:Raycast(origin, direction * GameConfig.MaxShotDistance, params)
	if not result then
		return origin + direction * GameConfig.MaxShotDistance, false
	end

	local endPos = result.Position
	local hitCharacter = characterFromPart(result.Instance)
	if not hitCharacter then
		return endPos, false
	end
	local victim = playerFromCharacter(hitCharacter)
	if not victim or victim == attacker then
		return endPos, false
	end

	local headshot = isHeadPart(result.Instance)
	local armor = PlayerStateService.getArmor(victim)
	local distance = (endPos - origin).Magnitude
	local breakdown = Ballistics.applyHit(
		def.damage,
		headshot,
		def.headshotMultiplier,
		def.armorPenetration,
		{ pool = armor.pool, hasHelmet = armor.hasHelmet },
		distance,
		def
	)

	CombatService.applyDamage(attacker, victim, breakdown.healthDamage, breakdown.armorDamage)
	return endPos, headshot
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

	if (origin - root.Position).Magnitude > GameConfig.HitValidationSlopStuds + 4 then
		origin = root.Position + Vector3.new(0, 1.5, 0)
	end

	local def = LoadoutService.getDef(player)
	if not def then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local rng = rngFromShot(player, origin, direction)
	local pellets = math.max(1, def.pellets)
	local primaryEnd = origin + direction * GameConfig.MaxShotDistance
	local anyHeadshot = false
	for i = 1, pellets do
		local dir = Ballistics.spreadDirection(direction, def.baseSpread, rng)
		local endPos, headshot = resolvePellet(player, origin, dir, def, params)
		if i == 1 then
			primaryEnd = endPos
		end
		if headshot then
			anyHeadshot = true
		end
	end

	Remotes.get(Net.WeaponFired):FireAllClients({
		shooterUserId = player.UserId,
		weaponId = def.id,
		origin = origin,
		endPos = primaryEnd,
		headshot = anyHeadshot,
	})
end

function CombatService.init()
	Remotes.get(Net.FireShot).OnServerEvent:Connect(function(player, payload)
		CombatService.handleFireShot(player, payload)
	end)
end

return CombatService
