--!strict
-- Server entrypoint: city greybox first, then elevated VIP lobby, then remotes / round loop.
-- Map must appear on any Play (including solo) even if later services error.

local MapService = require(script.Parent.MapService)
local MapValidator = require(script.Parent.MapValidator)
local LobbyService = require(script.Parent.LobbyService)

MapService.build()
MapValidator.runAndPrint()
LobbyService.build()

local Remotes = require(script.Parent.Remotes)
local AbilityService = require(script.Parent.AbilityService)
local RoundService = require(script.Parent.RoundService)

Remotes.init()
AbilityService.init()
RoundService.init()

print("[VIP] Server bootstrap complete.")
