--!strict

local Welcome = {}

Welcome.GameName = "Untitled Roblox Project"
Welcome.RemoteName = "WelcomeMessage"

function Welcome.buildMessage(playerName: string, playerCount: number): string
	local others = math.max(playerCount - 1, 0)

	if others == 0 then
		return string.format(
			"Welcome to %s, %s. You are the first one here.",
			Welcome.GameName,
			playerName
		)
	elseif others == 1 then
		return string.format(
			"Welcome to %s, %s. One other player is online.",
			Welcome.GameName,
			playerName
		)
	end

	return string.format(
		"Welcome to %s, %s. %d other players are online.",
		Welcome.GameName,
		playerName,
		others
	)
end

return Welcome
