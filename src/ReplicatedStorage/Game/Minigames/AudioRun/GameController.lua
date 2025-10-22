-- ReplicatedStorage/Game/Minigames/AudioRun/GameController.lua
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Net = RS.Game.Net
local RE  = Net.RemoteEvents
local MG  = RE.MinigameRemotes
local LaneEvt   = MG:WaitForChild("AudioRun_LaneInput")
local ReadyEvt  = MG:WaitForChild("AudioRun_ClientReady")
local HitEvt    = MG:WaitForChild("AudioRun_Hit")

local AudioRun = {}
AudioRun.__index = AudioRun

-- ==== TUNING (ajústalo en Setup con context.config si quieres) ====
local SONG_ASSET_ID   = "rbxassetid://18434858608" -- ← pon tu canción
local BPM             = 120
local SONG_OFFSET_SEC = 0.6
local BEAT_DISTANCE   = 12      -- studs por beat
local LANE_XS         = {-6,0,6}
local TRACK_Z_START   = 60
local TRACK_Z_END     = 1150
local BEAT_SPAWN_P    = 0.7     -- probabilidad de obstáculo por beat

-- Objeto simple para obstáculo
local function makeObstacle(parent, laneIdx, zSpawn)
	local p = Instance.new("Part")
	p.Name="Obstacle"; p.Anchored=true; p.Size=Vector3.new(5,5,5); p.Material=Enum.Material.Metal
	p.Position = Vector3.new(LANE_XS[laneIdx], 3, zSpawn)
	p.Parent = parent
	return p
end

function AudioRun.GetMeta()
	return {
		id="AudioRun",
		name="Audio Run",
		recommendedPlayers={4,8},
		description="Esquiva bloques al ritmo en 3 carriles. Chocar te retrasa 1 compás.",
	}
end

function AudioRun.new(context)
	return setmetatable({
		_context = context,
		_map = nil,
		players = {},
		state = {},      -- por jugador: lane, progressBeats, penaltyBeats
		obstacles = {},  -- array of Parts
		heartbeatConn = nil,
		beatSchedule = {}, -- tiempos absolutos (s) para beats
		startClock = 0,
		endClock = math.huge,
		songLength = 60, -- fallback, lo ajustamos con Sound.TimeLength si está disponible
	}, AudioRun)
end

function AudioRun:Setup(context)
	self._context = context
	-- Mapa
	local src = ServerStorage.Maps.MinigameMaps.AudioRunMap
	self._map = src:Clone(); self._map.Parent = context.mountFolder

	-- Trackear jugadores
	self.players = context.players
	for _,plr in ipairs(self.players) do
		self.state[plr.UserId] = { lane = 2, progressBeats = 0, penaltyBeats = 0, lastHitAt = -math.huge }
		-- Teleport inicial:
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hrp  = char:WaitForChild("HumanoidRootPart")
		hrp.CFrame = CFrame.new(0, 4, TRACK_Z_START)
		-- Congelar input de movimiento normal
		local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed = 0; hum.JumpPower = 0 end
	end

	-- Beat grid (BPM fijo)
	local beatDur = 60/BPM
	-- Intentar usar duración real de la canción (si la reproducimos en cliente, podemos pedirla por RF; aquí estimamos con N beats)
	local approxBeats = math.floor((180)/beatDur) -- 3 min por default
	for i=0, approxBeats do self.beatSchedule[i+1] = i*beatDur end

	-- Eventos de input de carril
	self._laneConn = LaneEvt.OnServerEvent:Connect(function(plr, sessionId, dir)
		if sessionId ~= context.sessionId then return end
		local st = self.state[plr.UserId]; if not st then return end
		local newLane = math.clamp(st.lane + (tonumber(dir) or 0), 1, 3)
		st.lane = newLane
	end)

	-- Listo cliente
	self._readyCount = 0
	self._readyConn = ReadyEvt.OnServerEvent:Connect(function(plr, sessionId)
		if sessionId ~= context.sessionId then return end
		self._readyCount += 1
	end)
end

function AudioRun:Start()
	-- Espera a que todos marquen ready o 2s de timeout
	local t0 = os.clock()
	repeat task.wait(0.1) until self._readyCount >= #self.players or (os.clock()-t0) > 2.0

	-- Arranque
	local beatDur = 60/BPM
	self.startClock = os.clock() + SONG_OFFSET_SEC
	-- Duración real: hasta que el z objetivo alcance TRACK_Z_END o beats agotados
	local totalBeatsByTrack = math.floor((TRACK_Z_END - TRACK_Z_START)/BEAT_DISTANCE)
	local totalBeats = math.min(totalBeatsByTrack, #self.beatSchedule)
	self.endClock   = self.startClock + totalBeats*beatDur

	-- Pre-spawn: nada; generamos en cada beat
	local nextBeatIdx = 1
	local spawnFolder = Instance.new("Folder"); spawnFolder.Name="Obstacles"; spawnFolder.Parent=self._map

	self.heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()

		-- Spawning por beats
		while nextBeatIdx <= totalBeats and (now - self.startClock) >= self.beatSchedule[nextBeatIdx] do
			-- probabilidad
			if math.random() < BEAT_SPAWN_P then
				local lane = math.random(1,3)
				local zSpawn = TRACK_Z_START + (nextBeatIdx+5) * BEAT_DISTANCE -- aparece 5 beats por delante
				if zSpawn < TRACK_Z_END - 5 then
					local ob = makeObstacle(spawnFolder, lane, zSpawn)
					table.insert(self.obstacles, {part=ob, lane=lane, z=zSpawn})
				end
			end
			nextBeatIdx += 1
			-- avance de progreso “global”: todos los que no están penalizados avanzan 1 beat
			for _,plr in ipairs(self.players) do
				local st = self.state[plr.UserId]
				-- aplica penalización pendiente
				if st.penaltyBeats > 0 then
					st.penaltyBeats -= 1 -- consumes one beat as penalty (no avanzas)
				else
					st.progressBeats += 1
				end
			end
		end

		-- Mover jugadores a su posición (X por carril, Z por progreso efectivo)
		for _,plr in ipairs(self.players) do
			local st = self.state[plr.UserId]
			local char = plr.Character
			if char and char.PrimaryPart then
				local targetZ = TRACK_Z_START + st.progressBeats*BEAT_DISTANCE
				local targetX = LANE_XS[st.lane]
				local cur = char.PrimaryPart.CFrame
				local target = CFrame.new(targetX, 4, targetZ)
				-- Lerp suave
				char:SetPrimaryPartCFrame(cur:Lerp(target, 0.35))
			end
		end

		-- Checar colisiones (AABB simple por proximidad por carril)
		for _,plr in ipairs(self.players) do
			local st = self.state[plr.UserId]
			local char = plr.Character
			if char and char.PrimaryPart then
				local pos = char.PrimaryPart.Position
				for _,ob in ipairs(self.obstacles) do
					if ob.lane == st.lane and math.abs(ob.part.Position.Z - pos.Z) < 4 and math.abs(ob.part.Position.X - pos.X) < 4 then
						-- Hit: da 1 beat de penalización y feedback
						if (now - st.lastHitAt) > 0.25 then
							st.penaltyBeats += 1
							st.lastHitAt = now
							HitEvt:FireClient(plr, {shake=true})
						end
					end
				end
			end
		end
	end)

	-- Espera fin de canción / track
	while os.clock() < self.endClock do task.wait(0.1) end

	-- Limpieza visual de obstáculos
	for _,o in ipairs(self.obstacles) do if o.part then o.part:Destroy() end end
end

function AudioRun:GetResults()
	-- Ordenar por progreso (beats) y menos penalizaciones recientes
	local list = {}
	for _,plr in ipairs(self.players) do
		local st = self.state[plr.UserId]
		table.insert(list, {plr=plr, score=st.progressBeats, penalties=st.lastHitAt})
	end
	table.sort(list, function(a,b)
		if a.score ~= b.score then return a.score > b.score end
		return a.penalties < b.penalties
	end)
	local order = {}
	for i,v in ipairs(list) do order[i]=v.plr.UserId end
	return { placement = order, stats = list }
end

function AudioRun:Teardown()
	if self.heartbeatConn then self.heartbeatConn:Disconnect() end
	if self._laneConn then self._laneConn:Disconnect() end
	if self._readyConn then self._readyConn:Disconnect() end
	if self._map then self._map:Destroy() end
end

return {
	GetMeta = AudioRun.GetMeta,
	Create = function(context) return AudioRun.new(context) end
}
