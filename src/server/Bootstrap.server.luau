--!strict
-- Server entrypoint: wire remotes and start VIP slice 0.

local Remotes = require(script.Parent.Remotes)
local RoundService = require(script.Parent.RoundService)

Remotes.init()
RoundService.init()

print("[VIP] Server bootstrap complete.")
