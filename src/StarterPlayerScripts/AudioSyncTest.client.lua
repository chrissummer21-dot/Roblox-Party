-- Cliente: recibe la orden del server, reproduce la canción y avisa "ready"
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local RE  = RS:WaitForChild("Game"):WaitForChild("Net"):WaitForChild("RemoteEvents")
local UIEvent  = RE:WaitForChild("UIEvent")
local MGRemotes = RE:WaitForChild("MinigameRemotes")
local ReadyEvt = MGRemotes:WaitForChild("AudioRun_ClientReady")

local song
local currentSessionId

local function playSong(assetId, delayStart)
	if song then song:Destroy() end
	song = Instance.new("Sound")
	song.Name = "AudioSync_Song"
	song.SoundId = assetId
	song.Volume = 0.6
	song.RollOffMaxDistance = 10000
	song.Parent = SoundService
	task.delay(delayStart or 0, function()
		song:Play()
	end)
end

UIEvent.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	if msg.type == "MinigameUI" and (msg.minigame == "AudioSyncTest" or msg.minigame == "AudioRun") then
		currentSessionId = msg.payload.sessionId
		local sid = msg.payload.songId or "rbxassetid://18434858608"
		local ofs = msg.payload.offset or 0.60
		playSong(sid, ofs)
		ReadyEvt:FireServer(currentSessionId)
	end
end)


-- === Cliente: metrónomo con fallback visual si el audio no carga ===
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local RE        = RS:WaitForChild("Game"):WaitForChild("Net"):WaitForChild("RemoteEvents")
local MGRemotes = RE:WaitForChild("MinigameRemotes")
local BeepEvt   = MGRemotes:WaitForChild("AudioSync_Beep")

-- 👇 PON AQUÍ TUS AUDIOS DE CLICK (deben ser Audio assets válidos)
local BEEP_SOUND_ID_STRONG = "rbxassetid://138182247360165"
local BEEP_SOUND_ID_WEAK   = "rbxassetid://138182247360165"

-- UI flash (fallback)
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "MetronomeFlash"
flashGui.ResetOnSpawn = false
flashGui.IgnoreGuiInset = true
flashGui.Parent = pg

local flash = Instance.new("Frame")
flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flash.BackgroundTransparency = 1
flash.Size = UDim2.fromScale(1, 1)
flash.Parent = flashGui

local function flashBeat(isStrong)
	flash.BackgroundColor3 = isStrong and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
	flash.BackgroundTransparency = 0.85
	TweenService:Create(flash, TweenInfo.new(0.08), {BackgroundTransparency = 1}):Play()
end

-- mini shake (solo acento)
local function smallShake()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local o = cam.CFrame
	for i = 1, 4 do
		cam.CFrame = o * CFrame.new((math.random()-0.5)*0.3, (math.random()-0.5)*0.3, 0)
		task.wait(0.015)
	end
	cam.CFrame = o
end

-- Crear/preparar sonidos
local strong = Instance.new("Sound")
strong.Name = "Metronome_Strong"
strong.SoundId = BEEP_SOUND_ID_STRONG
strong.Volume = 0.7
strong.PlaybackSpeed = 1.0
strong.Parent = SoundService

local weak = Instance.new("Sound")
weak.Name = "Metronome_Weak"
weak.SoundId = BEEP_SOUND_ID_WEAK
weak.Volume = 0.5
weak.PlaybackSpeed = 1.2
weak.Parent = SoundService

-- Preload (no revienta si falla)
pcall(function() ContentProvider:PreloadAsync({strong, weak}) end)

local function safePlay(snd, isStrong)
	-- Si el asset no es válido o no cargó, usa fallback visual
	if not snd.SoundId or snd.SoundId == "" or (snd.IsLoaded == false and snd.TimeLength == 0) then
		flashBeat(isStrong)
		if isStrong then smallShake() end
		return
	end
	-- Algunos audios tardan en marcar IsLoaded: intenta igual
	local ok = pcall(function() snd:Play() end)
	if not ok then
		flashBeat(isStrong)
		if isStrong then smallShake() end
	end
end

-- Reproducir con acento 1-2-3-4
BeepEvt.OnClientEvent:Connect(function(beatIndex)
	local isStrong = ((beatIndex - 1) % 4) == 0
	if isStrong then
		safePlay(strong, true)
	else
		safePlay(weak, false)
	end
end)
