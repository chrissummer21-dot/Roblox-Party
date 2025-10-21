local RS = game:GetService("ReplicatedStorage")
local PlayerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")

local Net = RS:WaitForChild("Game"):WaitForChild("Net")
local RE = Net:WaitForChild("RemoteEvents")
local UIEvent = RE:WaitForChild("UIEvent")
local MatchmakingEvent = RE:WaitForChild("MatchmakingEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyStatus"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 420, 0, 40)
label.Position = UDim2.new(0.5, -210, 0.9, 0)
label.BackgroundTransparency = 1
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(255,255,255)
label.Font = Enum.Font.GothamMedium
label.Text = "Entra a la zona de inicio para unirte"
label.Parent = gui

UIEvent.OnClientEvent:Connect(function(event, data)
	if event == "LobbyStatus" then
		local count = data.count or 0
		local req = data.required or 8
		local s = data.secondsLeft
		if s then
			label.Text = string.format("Jugadores en cola: %d/%d  â€¢  Inicio en: %ds", count, req, s)
		else
			label.Text = string.format("Jugadores en cola: %d/%d", count, req)
		end
	end
end)

MatchmakingEvent.OnClientEvent:Connect(function(event, data)
	if event == "StartSession" then
		label.Text = "Â¡Partida iniciando!"
	end
end)
