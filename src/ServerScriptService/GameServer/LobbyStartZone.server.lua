-- ServerScriptService/GameServer/LobbyStartZone.server.lua
-- Cola de inicio: hay que tocar el Part "StartZone". Arranca con N jugadores o a los T segundos.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local SSS     = game:GetService("ServerScriptService")

local MinigameService   = require(SSS.GameServer.Services.MinigameService)
local Config            = require(RS.Game.Config.GlobalConfig)
local SessionController = require(SSS.GameServer.Controllers.SessionController)

-- =========================
-- UBICAR LA START ZONE (simple y robusto)
-- =========================
local StartZone = workspace:WaitForChild("StartZone", 15) -- espera hasta 15 s
if StartZone and StartZone:IsA("Model") then
	-- Si es un Model, toma su primer BasePart descendiente
	local found
	for _, d in ipairs(StartZone:GetDescendants()) do
		if d:IsA("BasePart") then found = d break end
	end
	StartZone = found
end

assert(StartZone and StartZone:IsA("BasePart"),
	"[LobbyStartZone] No se encontró un BasePart para 'StartZone' en workspace (puede ser Model sin partes).")

-- =========================
-- REMOTOS
-- =========================
local Net           = RS:WaitForChild("Game"):WaitForChild("Net")
local RemoteEvents  = Net:WaitForChild("RemoteEvents")
local MatchmakingEvent = RemoteEvents:WaitForChild("MatchmakingEvent")
local UIEvent          = RemoteEvents:FindFirstChild("UIEvent") -- opcional en cliente

-- =========================
-- CONFIG (desde GlobalConfig)
-- =========================
local REQUIRED_PLAYERS = (Config.LOBBY and Config.LOBBY.REQUIRED_PLAYERS) or Config.MAX_PLAYERS_PER_SESSION or 8
local START_TIMEOUT    = (Config.LOBBY and Config.LOBBY.START_TIMEOUT)    or 30
local ROUNDS_PER_MATCH = Config.ROUNDS_PER_MATCH or 1

-- =========================
-- STATE
-- =========================
local queue         = {}   -- array de Players en cola (orden de llegada)
local queuedSet     = {}   -- set rápido: [player] = true
local firstJoinAt   = nil  -- os.clock() del primer jugador en cola
local timerRunning  = false
local sessionCounter= 0
local lockingStart  = false

-- =========================
-- HELPERS
-- =========================
local function addToQueue(plr: Player)
	if queuedSet[plr] then return false end
	table.insert(queue, plr)
	queuedSet[plr] = true
	plr:SetAttribute("InLobbyQueue", true)
	if not firstJoinAt then firstJoinAt = os.clock() end
	return true
end

local function removeFromQueue(plr: Player)
	if not queuedSet[plr] then return false end
	queuedSet[plr] = nil
	plr:SetAttribute("InLobbyQueue", nil)
	for i = #queue, 1, -1 do
		if queue[i] == plr then
			table.remove(queue, i)
			break
		end
	end
	if #queue == 0 then
		firstJoinAt  = nil
		timerRunning = false
	end
	return true
end

local function toUserIds(list)
	local ids = table.create(#list)
	for i, p in ipairs(list) do ids[i] = p.UserId end
	return ids
end

local function broadcastStatus()
	if UIEvent then
		local secondsLeft = nil
		if firstJoinAt then
			local elapsed = os.clock() - firstJoinAt
			secondsLeft = math.max(0, math.ceil(START_TIMEOUT - elapsed))
		end
		UIEvent:FireAllClients("LobbyStatus", {
			count    = #queue,
			required = REQUIRED_PLAYERS,
			secondsLeft = secondsLeft,
		})
	end
end

-- =========================
-- INICIO DE PARTIDA (¡ahora sí en servidor!)
-- =========================
local function startMatch(playersForMatch: {Player})
	lockingStart = true
	sessionCounter += 1
	local sessionId = ("S%04d"):format(sessionCounter)

	-- Selección de minijuegos desde el servicio (devuelve ids)
	local rotation = {}
	do
		local ok, res = pcall(function()
			return MinigameService.GetRotation(playersForMatch)
		end)
		if ok and type(res) == "table" and #res > 0 then
			rotation = res
		else
			-- Fallback por si el servicio aún no implementa GetRotation o quedó vacío:
			rotation = { "AudioRun" }
		end
	end

	print(("[LobbyStartZone] Iniciando %s con %d jugadores. Rotación: %s")
		:format(sessionId, #playersForMatch, table.concat(rotation, ", ")))

	-- Aviso a clientes (opcional, útil para UI/FX)
	local userIds = toUserIds(playersForMatch)
	MatchmakingEvent:FireAllClients("StartSession", {
		sessionId      = sessionId,
		playerUserIds  = userIds,
		rotation       = rotation,
	})

	-- Apaga FlightSwim en clientes (si existiera) para no interferir con TP
	if UIEvent then
		for _, p in ipairs(playersForMatch) do
			UIEvent:FireClient(p, "StopFlightSwim")
		end
	end

	-- >>>> ARRANQUE REAL EN SERVIDOR (SessionController) <<<<
	local ok, err = pcall(function()
		SessionController.StartSession({
			sessionId     = sessionId,
			roundCount    = ROUNDS_PER_MATCH,
			playerIds     = userIds,
			forceMinigames= rotation, -- respetamos la rotación ya elegida
		})
	end)
	if not ok then
		warn(("[LobbyStartZone] %s: error al iniciar sesión en servidor: %s"):format(sessionId, tostring(err)))
	end

	-- Limpia los que iniciaron de la cola
	for _, p in ipairs(playersForMatch) do
		removeFromQueue(p)
	end

	lockingStart = false
end

local function ensureTimer()
	if timerRunning or #queue == 0 then return end
	timerRunning = true
	task.spawn(function()
		while timerRunning do
			if lockingStart then task.wait(0.1) continue end

			local enoughPlayers = (#queue >= REQUIRED_PLAYERS)
			local timedOut      = false
			if firstJoinAt then
				timedOut = (os.clock() - firstJoinAt) >= START_TIMEOUT
			end

			broadcastStatus()

			if enoughPlayers or timedOut then
				local count = math.min(REQUIRED_PLAYERS, #queue)
				if timedOut and count == 0 then
					timerRunning = false
					firstJoinAt  = nil
					break
				end
				local pick = table.create(count)
				for i = 1, count do
					pick[i] = queue[i]
				end
				startMatch(pick)
				if #queue > 0 then
					firstJoinAt = os.clock()
				else
					timerRunning = false
					firstJoinAt  = nil
				end
			end

			task.wait(0.25)
		end
	end)
end

-- =========================
-- TOUCH HANDLERS
-- =========================
local function characterFromHit(hit: BasePart?)
	if not hit or not hit.Parent then return nil end
	local hum = hit.Parent:FindFirstChildOfClass("Humanoid")
	if hum then return hit.Parent end
	return nil
end

local function onTouched(hit: BasePart)
	local character = characterFromHit(hit)
	if not character then return end
	local plr = Players:GetPlayerFromCharacter(character)
	if not plr then return end

	if addToQueue(plr) then
		print(("[LobbyStartZone] %s entró a la cola (%d/%d)"):format(plr.Name, #queue, REQUIRED_PLAYERS))
		broadcastStatus()
		ensureTimer()
	end
end

StartZone.Touched:Connect(onTouched)

-- =========================
-- HOUSEKEEPING
-- =========================
Players.PlayerRemoving:Connect(function(plr)
	removeFromQueue(plr)
end)

print("[LobbyStartZone] Zona de inicio lista (espera " .. REQUIRED_PLAYERS .. " jugadores o " .. START_TIMEOUT .. "s).")
