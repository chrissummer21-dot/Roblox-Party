-- Cliente: manejar input de carril, reproducir música y feedback de golpe
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Net = RS.Game.Net
local RE  = Net.RemoteEvents
local MG  = RE.MinigameRemotes
local LaneEvt  = MG:WaitForChild("AudioRun_LaneInput")
local ReadyEvt = MG:WaitForChild("AudioRun_ClientReady")
local HitEvt   = MG:WaitForChild("AudioRun_Hit")
local UIEvent  = RE:WaitForChild("UIEvent") -- si lo usas para mostrar una micro-UI

local localSong -- Sound

local function playSong(assetId, startDelay)
	if localSong then localSong:Destroy() end
	localSong = Instance.new("Sound")
	localSong.SoundId = assetId
	localSong.Volume = 0.6
	localSong.Looped = false
	localSong.Parent = SoundService
	task.delay(startDelay or 0, function() localSong:Play() end)
end

-- efecto básico de golpe (shake de cámara leve)
local function smallShake()
	local cam = workspace.CurrentCamera
	local o = cam.CFrame
	for i=1,6 do
		cam.CFrame = o * CFrame.new((math.random()-0.5)*0.2, (math.random()-0.5)*0.2, 0)
		task.wait(0.02)
	end
	cam.CFrame = o
end

HitEvt.OnClientEvent:Connect(function(msg)
	if msg and msg.shake then smallShake() end
end)

-- Puedes disparar esto desde UIEvent para inyectar parámetros:
local currentSessionId = nil
UIEvent.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	if msg.type == "MinigameUI" and msg.minigame == "AudioRun" then
		currentSessionId = msg.payload.sessionId
		local song = msg.payload.songId or "rbxassetid://18434858608"
		local offset = msg.payload.offset or 0.6
		playSong(song, offset)
		ReadyEvt:FireServer(currentSessionId) -- listo para arrancar
	end
end)

-- Input de carril: A/D o ←/→
UIS.InputBegan:Connect(function(input, gp)
	if gp or not currentSessionId then return end
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
		LaneEvt:FireServer(currentSessionId, -1)   -- OK
	elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
		LaneEvt:FireServer(currentSessionId, 1)    -- <— antes tenías +1
	end
end)
