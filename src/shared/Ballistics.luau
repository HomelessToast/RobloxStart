--!strict
-- Pure damage math shared by client prediction and server authority.
-- Armor is a CS-style absorbing pool (§5.2), not flat % reduction.

local WeaponDefs = require(script.Parent.WeaponDefs)

export type ArmorState = {
	pool: number,
	hasHelmet: boolean,
}

export type DamageBreakdown = {
	healthDamage: number,
	armorDamage: number,
	wasHeadshot: boolean,
	remainingArmor: number,
}

local Ballistics = {}

-- Default body split: 60% absorbed by armor, 40% to health (§5.2 [A]).
-- armorPenetration shifts absorbed fraction toward health.
function Ballistics.armorAbsorbFraction(armorPenetration: number): number
	local pen = math.clamp(armorPenetration, 0, 1)
	local baseAbsorb = 0.6
	return math.clamp(baseAbsorb * (1 - pen), 0, 0.95)
end

function Ballistics.rangeMultiplier(
	distance: number,
	falloffStart: number,
	falloffEnd: number,
	falloffMin: number
): number
	if distance <= falloffStart then
		return 1
	end
	if distance >= falloffEnd then
		return falloffMin
	end
	local t = (distance - falloffStart) / math.max(falloffEnd - falloffStart, 0.001)
	return 1 - t * (1 - falloffMin)
end

function Ballistics.spreadDirection(
	forward: Vector3,
	baseSpread: number,
	rng: () -> number
): Vector3
	if baseSpread <= 0 then
		return forward.Unit
	end
	-- Simple cone: pick a random offset in the plane perpendicular to forward.
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude < 0.001 then
		right = forward:Cross(Vector3.xAxis)
	end
	right = right.Unit
	local up = right:Cross(forward).Unit
	local angle = rng() * math.pi * 2
	local radius = rng() * baseSpread
	local offset = right * math.cos(angle) * radius + up * math.sin(angle) * radius
	return (forward.Unit + offset).Unit
end

function Ballistics.applyHit(
	baseDamage: number,
	isHeadshot: boolean,
	headshotMultiplier: number,
	armorPenetration: number,
	armor: ArmorState,
	distance: number,
	weapon: WeaponDefs.WeaponDef
): DamageBreakdown
	local mult = Ballistics.rangeMultiplier(
		distance,
		weapon.falloffStart,
		weapon.falloffEnd,
		weapon.falloffMin
	)
	local raw = baseDamage * mult
	if isHeadshot then
		raw *= headshotMultiplier
	end

	local pool = armor.pool
	local hasHelmet = armor.hasHelmet

	-- Headshots bypass armor unless helmet is equipped.
	if isHeadshot and not hasHelmet then
		return {
			healthDamage = raw,
			armorDamage = 0,
			wasHeadshot = true,
			remainingArmor = pool,
		}
	end

	if pool <= 0 then
		return {
			healthDamage = raw,
			armorDamage = 0,
			wasHeadshot = isHeadshot,
			remainingArmor = 0,
		}
	end

	local absorbFrac = Ballistics.armorAbsorbFraction(armorPenetration)
	local intendedAbsorb = raw * absorbFrac
	local armorTaken = math.min(pool, intendedAbsorb)
	local healthFromSplit = raw * (1 - absorbFrac)
	-- Any absorb that armor couldn't cover spills to health.
	local spill = intendedAbsorb - armorTaken
	local healthDamage = healthFromSplit + spill

	return {
		healthDamage = healthDamage,
		armorDamage = armorTaken,
		wasHeadshot = isHeadshot,
		remainingArmor = pool - armorTaken,
	}
end

return Ballistics
