--!strict
--[[
	Procedural weapon meshes for VIP.

	Why this approach (vs Toolbox free models / curated MeshPart asset IDs):
	- Fully git-tracked under Rojo — no place-owned uploads, no Toolbox moderation risk,
	  no unpaid private assets that break when the creator locks them.
	- Each gun gets a recognizable silhouette (pistol / SMG / shotgun / AR / LMG / sniper)
	  built from welded Metal Parts, tinted per WeaponDefs.color.
	- Same builder feeds world attach + buy-menu ViewportFrame previews ("pictures").

	Tradeoff: greybox geometry, not catalog meshes. Smooth enough for slice-0 gunfeel;
	PrimaryPart + Muzzle attachment stay stable if MeshParts are swapped in later.
]]

local WeaponDefs = require(script.Parent.WeaponDefs)

export type VisualClass = "Pistol" | "SMG" | "Shotgun" | "Assault" | "LMG" | "Sniper"

local WeaponVisuals = {}

local FOLDER_NAME = "VipWeaponVisual"

function WeaponVisuals.folderName(): string
	return FOLDER_NAME
end

function WeaponVisuals.visualClass(def: WeaponDefs.WeaponDef): VisualClass
	if def.pellets > 1 then
		return "Shotgun"
	end
	if def.tier == "T4" and def.damage >= 80 then
		return "Sniper"
	end
	if def.tier == "T4" then
		return "LMG"
	end
	if def.slot == "Secondary" then
		return "Pistol"
	end
	if def.tier == "T2" then
		return "SMG"
	end
	return "Assault"
end

function WeaponVisuals.isSniperWeapon(weaponId: string): boolean
	local def = WeaponDefs.get(weaponId)
	return def ~= nil and WeaponVisuals.visualClass(def) == "Sniper"
end

local function makePart(
	name: string,
	size: Vector3,
	localCf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	p.CFrame = localCf
	return p
end

local function assemble(handle: Part, pieces: { Part }): Model
	local model = Instance.new("Model")
	model.Name = "WeaponModel"
	handle.Name = "Handle"
	handle.Parent = model
	model.PrimaryPart = handle

	for _, piece in pieces do
		local localCf = piece.CFrame
		piece.CFrame = handle.CFrame * localCf
		piece.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.Parent = piece
	end

	return model
end

--[[
	Author parts in handle-local space: +Z forward (muzzle), +Y up, +X right.
	Handle sits near the grip so RightHand weld looks natural.
]]
local function buildPistol(color: Color3, longSlide: boolean, fat: boolean): Model
	local gripW = if fat then 0.42 else 0.34
	local gripL = if longSlide then 0.55 else 0.48
	local slideL = if longSlide then 1.55 else 1.15
	local barrelL = if longSlide then 0.55 else 0.35
	local dark = color:Lerp(Color3.new(0.15, 0.15, 0.15), 0.4)

	local handle = makePart(
		"Handle",
		Vector3.new(gripW, 0.85, gripL),
		CFrame.new(),
		color:Lerp(Color3.fromRGB(40, 40, 40), 0.35),
		Enum.Material.SmoothPlastic
	)
	return assemble(handle, {
		makePart(
			"Slide",
			Vector3.new(gripW + 0.06, 0.32, slideL),
			CFrame.new(0, 0.35, -slideL * 0.25),
			color
		),
		makePart(
			"Barrel",
			Vector3.new(0.16, 0.16, barrelL),
			CFrame.new(0, 0.38, -slideL * 0.55 - barrelL * 0.35),
			dark
		),
		makePart(
			"TriggerGuard",
			Vector3.new(gripW * 0.7, 0.22, 0.28),
			CFrame.new(0, -0.05, -0.15),
			color:Lerp(Color3.new(0.2, 0.2, 0.2), 0.3)
		),
	})
end

local function buildSMG(color: Color3, helicalMag: boolean): Model
	local dark = color:Lerp(Color3.new(0.12, 0.12, 0.12), 0.5)
	local handle = makePart(
		"Handle",
		Vector3.new(0.32, 0.7, 0.4),
		CFrame.new(),
		color:Lerp(Color3.fromRGB(30, 30, 35), 0.4),
		Enum.Material.SmoothPlastic
	)
	local mag = if helicalMag
		then makePart(
			"Mag",
			Vector3.new(0.55, 0.35, 0.9),
			CFrame.new(0, -0.35, 0.05),
			color:Lerp(Color3.fromRGB(50, 45, 30), 0.2)
		)
		else makePart(
			"Mag",
			Vector3.new(0.28, 0.7, 0.35),
			CFrame.new(0, -0.55, -0.05),
			color:Lerp(Color3.fromRGB(40, 40, 45), 0.2)
		)
	return assemble(handle, {
		makePart("Receiver", Vector3.new(0.38, 0.4, 1.4), CFrame.new(0, 0.25, -0.55), color),
		makePart("Barrel", Vector3.new(0.18, 0.18, 0.9), CFrame.new(0, 0.28, -1.45), dark),
		makePart(
			"Stock",
			Vector3.new(0.22, 0.28, 0.7),
			CFrame.new(0, 0.2, 0.55),
			color:Lerp(Color3.fromRGB(25, 25, 28), 0.3)
		),
		makePart("Handguard", Vector3.new(0.36, 0.3, 0.7), CFrame.new(0, 0.22, -1.0), color),
		mag,
	})
end

local function buildShotgun(color: Color3): Model
	local dark = color:Lerp(Color3.new(0.15, 0.15, 0.15), 0.45)
	local wood = color:Lerp(Color3.fromRGB(80, 55, 30), 0.1)
	local handle = makePart(
		"Handle",
		Vector3.new(0.34, 0.75, 0.42),
		CFrame.new(),
		color:Lerp(Color3.fromRGB(60, 40, 25), 0.2),
		Enum.Material.Wood
	)
	return assemble(handle, {
		makePart("Receiver", Vector3.new(0.4, 0.42, 1.1), CFrame.new(0, 0.28, -0.4), color),
		makePart("Barrel", Vector3.new(0.28, 0.28, 2.0), CFrame.new(0, 0.32, -1.6), dark),
		makePart(
			"Pump",
			Vector3.new(0.36, 0.34, 0.55),
			CFrame.new(0, 0.18, -1.05),
			wood,
			Enum.Material.Wood
		),
		makePart(
			"Stock",
			Vector3.new(0.3, 0.4, 0.95),
			CFrame.new(0, 0.15, 0.7),
			wood,
			Enum.Material.Wood
		),
	})
end

local function buildAssault(color: Color3, carryingHandle: boolean, akish: boolean): Model
	local dark = color:Lerp(Color3.new(0.1, 0.1, 0.1), 0.5)
	local handle = makePart(
		"Handle",
		Vector3.new(0.34, 0.78, 0.4),
		CFrame.new(),
		color:Lerp(Color3.fromRGB(35, 35, 35), 0.35),
		Enum.Material.SmoothPlastic
	)
	local pieces = {
		makePart("Receiver", Vector3.new(0.42, 0.45, 1.55), CFrame.new(0, 0.28, -0.55), color),
		makePart("Barrel", Vector3.new(0.16, 0.16, 1.35), CFrame.new(0, 0.32, -1.85), dark),
		makePart("Handguard", Vector3.new(0.4, 0.36, 0.95), CFrame.new(0, 0.26, -1.25), color),
		makePart(
			"Mag",
			Vector3.new(0.3, if akish then 0.95 else 0.8, 0.38),
			CFrame.new(0, -0.55, -0.35)
				* (if akish then CFrame.Angles(0, 0, math.rad(8)) else CFrame.new()),
			color:Lerp(Color3.fromRGB(40, 42, 30), 0.25)
		),
		makePart(
			"Stock",
			Vector3.new(0.28, 0.32, if akish then 0.85 else 0.75),
			CFrame.new(0, 0.22, 0.65),
			color:Lerp(Color3.fromRGB(45, 50, 40), 0.2)
		),
	}
	if carryingHandle then
		table.insert(
			pieces,
			makePart(
				"CarryHandle",
				Vector3.new(0.2, 0.35, 0.55),
				CFrame.new(0, 0.62, -0.35),
				color:Lerp(Color3.new(0.2, 0.25, 0.2), 0.2)
			)
		)
	else
		table.insert(
			pieces,
			makePart(
				"RearSight",
				Vector3.new(0.18, 0.22, 0.2),
				CFrame.new(0, 0.55, -0.1),
				color:Lerp(Color3.new(0.15, 0.15, 0.15), 0.3)
			)
		)
	end
	if akish then
		table.insert(
			pieces,
			makePart(
				"GasTube",
				Vector3.new(0.12, 0.12, 0.9),
				CFrame.new(0, 0.48, -1.2),
				color:Lerp(Color3.new(0.2, 0.2, 0.15), 0.3)
			)
		)
	end
	return assemble(handle, pieces)
end

local function buildLMG(color: Color3): Model
	local dark = color:Lerp(Color3.new(0.12, 0.12, 0.1), 0.45)
	local handle = makePart(
		"Handle",
		Vector3.new(0.38, 0.85, 0.45),
		CFrame.new(),
		color:Lerp(Color3.fromRGB(40, 40, 30), 0.3),
		Enum.Material.SmoothPlastic
	)
	return assemble(handle, {
		makePart("Receiver", Vector3.new(0.55, 0.55, 1.8), CFrame.new(0, 0.32, -0.6), color),
		makePart("Barrel", Vector3.new(0.22, 0.22, 1.6), CFrame.new(0, 0.38, -2.0), dark),
		makePart(
			"BoxMag",
			Vector3.new(0.7, 0.55, 0.9),
			CFrame.new(0.15, -0.35, -0.4),
			color:Lerp(Color3.fromRGB(50, 55, 35), 0.2)
		),
		makePart(
			"Stock",
			Vector3.new(0.35, 0.4, 0.9),
			CFrame.new(0, 0.25, 0.75),
			color:Lerp(Color3.fromRGB(45, 48, 35), 0.2)
		),
		makePart("BipodL", Vector3.new(0.08, 0.7, 0.08), CFrame.new(-0.25, -0.35, -1.5), dark),
		makePart("BipodR", Vector3.new(0.08, 0.7, 0.08), CFrame.new(0.25, -0.35, -1.5), dark),
	})
end

local function buildSniper(color: Color3): Model
	local dark = color:Lerp(Color3.new(0.1, 0.1, 0.1), 0.5)
	local handle = makePart(
		"Handle",
		Vector3.new(0.34, 0.8, 0.42),
		CFrame.new(),
		color:Lerp(Color3.fromRGB(35, 40, 30), 0.25),
		Enum.Material.SmoothPlastic
	)
	return assemble(handle, {
		makePart("Receiver", Vector3.new(0.4, 0.4, 1.4), CFrame.new(0, 0.28, -0.45), color),
		makePart("Barrel", Vector3.new(0.14, 0.14, 2.4), CFrame.new(0, 0.34, -2.15), dark),
		makePart(
			"Stock",
			Vector3.new(0.32, 0.38, 1.1),
			CFrame.new(0, 0.18, 0.8),
			color:Lerp(Color3.fromRGB(50, 55, 40), 0.15)
		),
		makePart(
			"Mag",
			Vector3.new(0.28, 0.55, 0.35),
			CFrame.new(0, -0.4, -0.25),
			color:Lerp(Color3.fromRGB(40, 42, 35), 0.2)
		),
		makePart("ScopeBody", Vector3.new(0.22, 0.22, 0.85), CFrame.new(0, 0.62, -0.35), dark),
		makePart(
			"ScopeLens",
			Vector3.new(0.26, 0.26, 0.12),
			CFrame.new(0, 0.62, 0.15),
			Color3.fromRGB(40, 80, 120),
			Enum.Material.Glass
		),
	})
end

function WeaponVisuals.buildModel(weaponId: string): Model?
	local def = WeaponDefs.get(weaponId)
	if not def then
		return nil
	end
	local color = def.color
	local class = WeaponVisuals.visualClass(def)

	local model: Model
	if class == "Pistol" then
		model = buildPistol(
			color,
			weaponId == "Deagle" or weaponId == "M1911",
			weaponId == "Deagle" or weaponId == "Pernach"
		)
	elseif class == "SMG" then
		model = buildSMG(color, weaponId == "Bizon")
	elseif class == "Shotgun" then
		model = buildShotgun(color)
	elseif class == "LMG" then
		model = buildLMG(color)
	elseif class == "Sniper" then
		model = buildSniper(color)
	else
		model = buildAssault(
			color,
			weaponId == "M16A4" or weaponId == "M4A1",
			weaponId == "AKM" or weaponId == "AK74M"
		)
	end

	model.Name = "WeaponModel_" .. weaponId
	model:SetAttribute("WeaponId", weaponId)
	model:SetAttribute("VisualClass", class)
	return model
end

--[[
	R15 RightHand grip for a raised ready/aim arm (WeaponHoldController).
	Model space: +Z muzzle, +Y up, Handle at grip.
	With the arm raised forward, this seats the grip in the palm and points
	the barrel character-forward — not hanging at the hip.
]]
function WeaponVisuals.handAttachCFrame(def: WeaponDefs.WeaponDef): CFrame
	local class = WeaponVisuals.visualClass(def)
	-- Hand local → gun: pitch so +Z (muzzle) exits along fingers/forward.
	local orient = CFrame.Angles(math.rad(-90), math.rad(180), 0)
	if class == "Pistol" then
		return CFrame.new(0, -0.12, -0.05) * orient * CFrame.Angles(math.rad(6), math.rad(-4), 0)
	elseif class == "SMG" then
		return CFrame.new(0.02, -0.14, -0.08) * orient * CFrame.Angles(math.rad(4), math.rad(-2), 0)
	elseif class == "Shotgun" then
		return CFrame.new(0.04, -0.16, -0.1) * orient * CFrame.Angles(math.rad(2), 0, 0)
	elseif class == "LMG" then
		return CFrame.new(0.05, -0.18, -0.12) * orient * CFrame.Angles(math.rad(0), 0, 0)
	elseif class == "Sniper" then
		return CFrame.new(0.04, -0.16, -0.1) * orient * CFrame.Angles(math.rad(2), 0, 0)
	end
	-- Assault
	return CFrame.new(0.03, -0.15, -0.09) * orient * CFrame.Angles(math.rad(3), math.rad(-2), 0)
end

export type ArmMotors = {
	RightShoulder: Motor6D?,
	RightElbow: Motor6D?,
	RightWrist: Motor6D?,
}

--- RightShoulder / RightElbow / RightWrist Motor6Ds when present (R15).
function WeaponVisuals.findArmMotors(character: Model): ArmMotors
	local found: ArmMotors = {
		RightShoulder = nil,
		RightElbow = nil,
		RightWrist = nil,
	}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			local name = d.Name
			if name == "RightShoulder" then
				found.RightShoulder = d
			elseif name == "RightElbow" then
				found.RightElbow = d
			elseif name == "RightWrist" then
				found.RightWrist = d
			end
		end
	end
	return found
end

--[[
	Ready/aim Transform overrides (applied after Animate on Stepped).
	Raises the right arm so the welded gun sits chest-high, not at the hip.
]]
function WeaponVisuals.readyArmTransforms(): (CFrame, CFrame, CFrame)
	local shoulder = CFrame.Angles(math.rad(-95), math.rad(25), math.rad(15))
	local elbow = CFrame.Angles(math.rad(-25), 0, math.rad(-8))
	local wrist = CFrame.Angles(math.rad(12), math.rad(-5), math.rad(5))
	return shoulder, elbow, wrist
end

function WeaponVisuals.clearFromCharacter(character: Model)
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

function WeaponVisuals.attachToCharacter(character: Model, weaponId: string): Model?
	WeaponVisuals.clearFromCharacter(character)
	local def = WeaponDefs.get(weaponId)
	if not def then
		return nil
	end

	local rightHand = character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")
	if not rightHand or not rightHand:IsA("BasePart") then
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character

	local model = WeaponVisuals.buildModel(weaponId)
	if not model then
		folder:Destroy()
		return nil
	end
	model.Parent = folder

	local handle = model.PrimaryPart
	if not handle then
		folder:Destroy()
		return nil
	end

	local weld = Instance.new("Weld")
	weld.Name = "WeaponHandWeld"
	weld.Part0 = rightHand
	weld.Part1 = handle
	weld.C0 = WeaponVisuals.handAttachCFrame(def)
	weld.C1 = CFrame.new()
	weld.Parent = handle

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	local barrel = model:FindFirstChild("Barrel")
	if barrel and barrel:IsA("BasePart") then
		muzzle.Parent = barrel
		muzzle.Position = Vector3.new(0, 0, -barrel.Size.Z * 0.5)
	else
		muzzle.Parent = handle
		muzzle.Position = Vector3.new(0, 0.3, -1.2)
	end

	return model
end

function WeaponVisuals.buildPreview(weaponId: string): (Model?, CFrame)
	local model = WeaponVisuals.buildModel(weaponId)
	if not model or not model.PrimaryPart then
		return nil, CFrame.new()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local cf = CFrame.new(Vector3.new(1.8, 0.6, 2.4), model.PrimaryPart.Position)
	return model, cf
end

function WeaponVisuals.buildArmorPreview(armorId: string): (Model?, CFrame)
	local model = Instance.new("Model")
	model.Name = "ArmorPreview_" .. armorId
	local torso = Instance.new("Part")
	torso.Name = "Handle"
	torso.Size = Vector3.new(1.6, 1.8, 0.55)
	torso.Color = if armorId == "Heavy"
		then Color3.fromRGB(55, 70, 90)
		else Color3.fromRGB(70, 78, 70)
	torso.Material = Enum.Material.Metal
	torso.Anchored = true
	torso.CanCollide = false
	torso.Parent = model
	model.PrimaryPart = torso

	if armorId == "Heavy" then
		local helm = Instance.new("Part")
		helm.Name = "Helmet"
		helm.Size = Vector3.new(1.1, 0.55, 1.1)
		helm.Color = Color3.fromRGB(45, 55, 65)
		helm.Material = Enum.Material.Metal
		helm.Anchored = true
		helm.CanCollide = false
		helm.CFrame = torso.CFrame * CFrame.new(0, 1.25, 0)
		helm.Parent = model
	end

	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Size = Vector3.new(1.2, 1.0, 0.2)
	plate.Color = if armorId == "Heavy"
		then Color3.fromRGB(90, 100, 70)
		else Color3.fromRGB(100, 110, 90)
	plate.Material = Enum.Material.DiamondPlate
	plate.Anchored = true
	plate.CanCollide = false
	plate.CFrame = torso.CFrame * CFrame.new(0, 0.1, -0.35)
	plate.Parent = model

	return model, CFrame.new(Vector3.new(2.0, 0.4, 2.4), torso.Position)
end

return WeaponVisuals
