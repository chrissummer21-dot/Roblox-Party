local RS = game:GetService("ReplicatedStorage")
local PlayerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local MatchmakingEvent = RS.Game.Net.RemoteEvents:WaitForChild("MatchmakingEvent")

local lobbyGui = Instance.new("ScreenGui", PlayerGui)
local status = Instance.new("TextLabel", lobbyGui)
status.Size = UDim2.new(0, 300, 0, 50)
status.Position = UDim2.new(0.5, -150, 0.9, 0)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(255, 255, 255)
status.Text = "Esperando jugadores..."

MatchmakingEvent.OnClientEvent:Connect(function(event, data)
	if event == "StartSession" then
		status.Text = "Â¡Partida iniciando!"
	end
end)
