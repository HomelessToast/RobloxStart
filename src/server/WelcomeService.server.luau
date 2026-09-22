local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Welcome = require(ReplicatedStorage.Shared.Welcome)

local welcomeRemote = ReplicatedStorage.Remotes[Welcome.RemoteName]

local function greet(player: Player)
	local message = Welcome.buildMessage(player.Name, #Players:GetPlayers())
	print(string.format("[WelcomeService] %s joined. %s", player.Name, message))
	welcomeRemote:FireClient(player, message)
end

-- Covers players who joined before this script started, e.g. after a Rojo sync reload.
for _, player in Players:GetPlayers() do
	task.spawn(greet, player)
end

Players.PlayerAdded:Connect(greet)

print(string.format("[WelcomeService] %s server code is live.", Welcome.GameName))
