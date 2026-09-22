--!strict
-- Server entrypoint: build the greybox first, then wire remotes / round loop.
-- Map must appear on any Play (including solo) even if later services error.

local MapService = require(script.Parent.MapService)
local MapValidator = require(script.Parent.MapValidator)

MapService.build()
MapValidator.runAndPrint()

local Remotes = require(script.Parent.Remotes)
local RoundService = require(script.Parent.RoundService)

Remotes.init()
RoundService.init()

print("[VIP] Server bootstrap complete.")
