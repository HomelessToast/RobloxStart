--!strict
--[[
	Per-role classic clothing kits (public catalog Shirt/Pants asset IDs).

	Applied via HumanoidDescription on spawn / role assign (AppearanceService).
	IDs are catalog clothing assets (types 11/12), not private place assets —
	experiences may ApplyDescription them without the player owning the items.

	Swap IDs here if a catalog item goes off-sale or looks wrong in Studio.
]]

local Enums = require(script.Parent.Enums)

export type RoleKit = {
	displayName: string,
	look: string,
	shirtAssetId: number,
	pantsAssetId: number,
	shirtCatalogName: string,
	pantsCatalogName: string,
}

local RoleAppearances = {}

-- President: clean formal black suit
local PRESIDENT: RoleKit = {
	displayName = "President",
	look = "Clean black formal suit",
	shirtAssetId = 132833751, -- Black Suit (classic Shirt)
	pantsAssetId = 132833761, -- Black Suit Pants (classic Pants)
	shirtCatalogName = "Black Suit",
	pantsCatalogName = "Black Suit Pants",
}

-- Bodyguard: agent / security suit — distinct from President's solid black
local BODYGUARD: RoleKit = {
	displayName = "Bodyguard",
	look = "Dark agent / security suit (distinct from President)",
	shirtAssetId = 1997169394, -- Agent [+]
	pantsAssetId = 1997178515, -- Agent [-]
	shirtCatalogName = "Agent [+]",
	pantsCatalogName = "Agent [-]",
}

-- Terrorist: woodland camo hostile ops (not default Roblox noob)
local TERRORIST: RoleKit = {
	displayName = "Terrorist",
	look = "Woodland camo hostile-ops uniform (RU / militia read)",
	shirtAssetId = 5792532898, -- US Marine Woodland LS+ (camo shirt)
	pantsAssetId = 5792530645, -- US Marine Woodland - (camo pants)
	shirtCatalogName = "US Marine Woodland LS+",
	pantsCatalogName = "US Marine Woodland -",
}

local BY_ROLE: { [string]: RoleKit } = {
	[Enums.Role.President] = PRESIDENT,
	[Enums.Role.Bodyguard] = BODYGUARD,
	[Enums.Role.Terrorist] = TERRORIST,
}

function RoleAppearances.getKit(role: string): RoleKit?
	return BY_ROLE[role]
end

function RoleAppearances.allKits(): { [string]: RoleKit }
	return BY_ROLE
end

return RoleAppearances
