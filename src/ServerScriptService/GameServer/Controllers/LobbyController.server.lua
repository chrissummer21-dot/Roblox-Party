local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local MatchmakingEvent = RS.Game.Net.RemoteEvents:WaitForChild("MatchmakingEvent")
local LobbyMap = SS.Maps:WaitForChild("LobbyMap"):Clone()
LobbyMap.Parent = workspace

local Lobby = {}
Lobby.Players = {}

function Lobby:AddPlayer(player)
	if not table.find(self.Players, player) then
		table.insert(self.Players, player)
		print(player.Name .. " se uniÃ³ al lobby (" .. #self.Players .. " jugadores).")
	end
end

function Lobby:RemovePlayer(player)
	local i = table.find(self.Players, player)
	if i then
		table.remove(self.Players, i)
		print(player.Name .. " saliÃ³ del lobby.")
	end
end

Players.PlayerAdded:Connect(function(p)
	Lobby:AddPlayer(p)
end)

Players.PlayerRemoving:Connect(function(p)
	Lobby:RemovePlayer(p)
end)

-- Inicia sesiÃ³n cuando haya suficientes jugadores
task.spawn(function()
	while true do
		if #Lobby.Players >= 4 then -- mÃ­nimo para iniciar
			print("ðŸŽ® Iniciando partida con " .. #Lobby.Players .. " jugadores...")
			MatchmakingEvent:FireAllClients("StartSession", Lobby.Players)
			Lobby.Players = {}
		end
		task.wait(5)
	end
end)

print("âœ… LobbyController activo.")
