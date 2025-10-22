-- ReplicatedStorage/Game/Minigames/AudioSyncTest/GameController.lua
-- Eventos por NOTAS del JSON; espera previa; arranque absoluto; telemetría de inicio.

local RS           = game:GetService("ReplicatedStorage")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- ========= Ensure de estructura / remotos =========
local function ensure(parent, className, name)
	local x = parent:FindFirstChild(name)
	if x and x.ClassName == className then return x end
	if x then x:Destroy() end
	x = Instance.new(className); x.Name = name; x.Parent = parent
	return x
end

local GameFolder    = ensure(RS, "Folder", "Game")
local NetFolder     = ensure(GameFolder, "Folder", "Net")
local RemoteEvents  = ensure(NetFolder, "Folder", "RemoteEvents")
local MGRemotes     = ensure(RemoteEvents, "Folder", "MinigameRemotes")
local UIEvent       = ensure(RemoteEvents, "RemoteEvent", "UIEvent")
local ReadyEvt      = ensure(MGRemotes, "RemoteEvent", "AudioRun_ClientReady")
local BeepEvt       = ensure(MGRemotes, "RemoteEvent", "AudioSync_Beep")
local StartRptEvt   = ensure(MGRemotes, "RemoteEvent", "AudioSync_ReportStart") -- 🔎 telemetría

-- ========= Tuning / opciones =========
local DEFAULT_SONG_ID   = "rbxassetid://18434858608"
local DEFAULT_OFFSET    = 0.60
local PREVIEW_AHEAD     = 0.10

-- Espera previa para cargar mapa/recursos antes de armar todo
local PRE_LAUNCH_WAIT   = 2.0   -- segundos

-- Fuente: "notes" o "beats"
local EVENT_SOURCE      = "notes"

-- Track de notas
local NOTE_TRACK_NAME   = "808 Clap 1" -- cambia si quieres otro
local NOTE_TRACK_INDEX  = 1
local MIN_VELOCITY      = 1

-- Visual
local MODE_VISUAL       = "drop"  -- "drop" | "pop"
local DIST_AHEAD        = 10
local BASE_Y            = 4
local DROP_HEIGHT_Y     = 12
local DROP_CAN_COLLIDE  = false
local DROP_SPLASH       = true
local POP_TIME          = 0.35
local PART_LIFETIME     = 3.0

-- Spawn
local SPAWN_PER_PLAYER  = false

-- Metrónomo
local METRONOME_ENABLED = true
local METRONOME_SOURCE  = "notes"

-- Colores
local ACCENT_COLORS = {
	Color3.fromRGB(255, 70, 200),
	Color3.fromRGB(140, 180, 255),
	Color3.fromRGB(255, 170, 80),
	Color3.fromRGB(180, 255, 140),
}
local DEFAULT_COLOR = Color3.fromRGB(255, 70, 200)
local PITCH_COLORING = true

-- ========= Utilidades =========
local function colorForBeatIndex(idx)
	local i = ((idx - 1) % 4) + 1
	return ACCENT_COLORS[i] or DEFAULT_COLOR
end

local function colorForPitch(noteNumber)
	local hue = ((noteNumber % 12) / 12)
	return Color3.fromHSV(hue, 0.9, 1.0)
end

local function makeSplash(position, baseColor)
	local p = Instance.new("Part")
	p.Name = "Beat_Splash"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Size = Vector3.new(0.5, 0.2, 0.5)
	p.CFrame = CFrame.new(position.X, math.max(0.5, position.Y), position.Z)
	p.Material = Enum.Material.Neon
	p.Color = baseColor
	p.Transparency = 0.2
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 1, Size = Vector3.new(6, 0.2, 6)}):Play()
	Debris:AddItem(p, 0.35)
end

local function makeBallDrop(spawnAt, col)
	local p = Instance.new("Part")
	p.Name = "EventBall"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.3,1.3,1.3)
	p.Material = Enum.Material.Neon
	p.Color = col
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = DROP_CAN_COLLIDE
	p.CanTouch = true
	p.CanQuery = true
	p.Position = spawnAt + Vector3.new(0, DROP_HEIGHT_Y, 0)
	p.Parent = workspace
	Debris:AddItem(p, PART_LIFETIME)
	-- splash al tocar (aprox)
	local g = workspace.Gravity
	local t = math.sqrt(2 * DROP_HEIGHT_Y / math.max(1, g))
	task.delay(t, function()
		if p and p.Parent then
			makeSplash(Vector3.new(spawnAt.X, 0.6, spawnAt.Z), p.Color)
		end
	end)
	return p
end

local function makeBallPop(spawnAt, col)
	local p = Instance.new("Part")
	p.Name = "EventBall"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.3,1.3,1.3)
	p.Material = Enum.Material.Neon
	p.Color = col
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Position = spawnAt
	p.Parent = workspace
	Debris:AddItem(p, PART_LIFETIME)
	TweenService:Create(p, TweenInfo.new(POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 1, Size = Vector3.new(0.5,0.5,0.5)}):Play()
	return p
end

local function spawnVisual(spawnAt, color)
	if MODE_VISUAL == "drop" then return makeBallDrop(spawnAt, color) end
	return makeBallPop(spawnAt, color)
end

local function readActiveBeatmap()
	local cfg = RS:FindFirstChild("Game") and RS.Game:FindFirstChild("Config")
	if not cfg then return nil end
	local bmp = cfg:FindFirstChild("Beatmaps")
	if not bmp then return nil end

	local activeMod = bmp:FindFirstChild("ActiveBeatmap")
	if activeMod and activeMod:IsA("ModuleScript") then
		local ok, data = pcall(require, activeMod)
		if ok and type(data) == "table" then return data end
	end

	local activeStr = bmp:FindFirstChild("Active")
	if activeStr and activeStr:IsA("StringValue") and activeStr.Value ~= "" then
		local ok, data = pcall(function() return HttpService:JSONDecode(activeStr.Value) end)
		if ok and type(data) == "table" then return data end
	end
	return nil
end

local AudioSync = {}
AudioSync.__index = AudioSync

function AudioSync.GetMeta()
	return {
		id = "AudioSyncTest",
		name = "Audio Sync Test (Notes)",
		recommendedPlayers = {1, 8},
		description = "Notas del beatmap → esferas + metrónomo; arranque absoluto + telemetría.",
	}
end

function AudioSync.new(context)
	return setmetatable({
		_context      = context,
		players       = {},
		startClock    = 0,     -- hora absoluta (os.clock()) cuando debe iniciar todo
		readyCount    = 0,
		heartbeatConn = nil,
		eventTimesAbs = {},
		eventMeta     = {},
		songId        = DEFAULT_SONG_ID,
		offset        = DEFAULT_OFFSET,

		_startDrifts  = {},    -- telemetría de clientes (desfases reportados)
	}, AudioSync)
end

local function pickTrack(data)
	if type(data.tracks) ~= "table" or #data.tracks == 0 then return nil end
	if NOTE_TRACK_NAME then
		for _, tr in ipairs(data.tracks) do
			if typeof(tr.name) == "string" and tr.name == NOTE_TRACK_NAME then
				return tr
			end
		end
	end
	local idx = math.clamp(NOTE_TRACK_INDEX or 1, 1, #data.tracks)
	return data.tracks[idx]
end

function AudioSync:Setup(context)
	self.players = context.players

	-- Espera previa para cargar mapa/recursos
	task.wait(PRE_LAUNCH_WAIT)

	-- Coloca/limita movimiento (opcional)
	for _, plr in ipairs(self.players) do
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hrp  = char:WaitForChild("HumanoidRootPart")
		hrp.CFrame = CFrame.new(0, BASE_Y, 0)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 0 hum.JumpPower = 0 end
	end

	-- Carga beatmap
	local data = readActiveBeatmap()
	if not data then
		warn("[AudioSyncTest] No hay beatmap. Fallback a 120 BPM (30s).")
		local beatDur = 60/120
		self.songId = DEFAULT_SONG_ID
		self.offset = DEFAULT_OFFSET
		self.startClock = os.clock() + self.offset
		for i = 0, math.floor(30/beatDur) do
			self.eventTimesAbs[#self.eventTimesAbs+1] = self.startClock + i*beatDur
			self.eventMeta[#self.eventMeta+1] = { kind="beat", idx=i+1 }
		end
	else
		self.songId = data.songId or DEFAULT_SONG_ID
		self.offset = tonumber(data.offset) or DEFAULT_OFFSET

		-- ⚠️ Arranque absoluto compartido (tras PRE_LAUNCH_WAIT + offset)
		self.startClock = os.clock() + self.offset

		self.eventTimesAbs = {}
		self.eventMeta     = {}

		if EVENT_SOURCE == "notes" and type(data.tracks) == "table" then
			local tr = pickTrack(data)
			if tr and type(tr.notes) == "table" and #tr.notes > 0 then
				table.sort(tr.notes, function(a,b) return (tonumber(a.t) or 0) < (tonumber(b.t) or 0) end)
				for _, n in ipairs(tr.notes) do
					local t = tonumber(n.t)
					local vel = tonumber(n.vel) or 0
					local noteNum = tonumber(n.note) or 60
					if t and t >= 0 and vel >= MIN_VELOCITY then
						self.eventTimesAbs[#self.eventTimesAbs+1] = self.startClock + t
						self.eventMeta[#self.eventMeta+1] = { kind="note", note=noteNum, vel=vel, name=tr.name }
					end
				end
			end
		end

		-- Si no hubo notas válidas, cae a beats
		if #self.eventTimesAbs == 0 and type(data.beats) == "table" then
			for i, t in ipairs(data.beats) do
				self.eventTimesAbs[#self.eventTimesAbs+1] = self.startClock + (tonumber(t) or 0)
				self.eventMeta[#self.eventMeta+1] = { kind="beat", idx=i }
			end
		end

		-- Telemetría: escucha reporte de inicio desde clientes
		self._startRptConn = StartRptEvt.OnServerEvent:Connect(function(plr, payload)
			-- payload: { plannedStart = <sec>, actualStart = <sec> }
			if typeof(payload) ~= "table" then return end
			local drift = (tonumber(payload.actualStart) or 0) - (tonumber(payload.plannedStart) or 0)
			self._startDrifts[plr.UserId] = drift
			print(("[AudioSyncTest] Start drift %s: %+0.4fs"):format(plr.Name, drift))
		end)
	end

	-- Clientes: reproducir canción a la hora absoluta planificada
	for _, plr in ipairs(self.players) do
		UIEvent:FireClient(plr, {
			type = "MinigameUI",
			minigame = "AudioSyncTest",
			payload = {
				sessionId = context.sessionId,
				songId    = self.songId,
				-- enviamos la HORA ABSOLUTA (no solo el offset) para máxima precisión:
				absoluteStart = self.startClock,
				offset    = self.offset, -- (por compatibilidad, pero ya no dependemos de este en cliente)
			}
		})
	end

	-- Espera confirmaciones (ready) un momento
	local t0 = os.clock()
	repeat task.wait(0.05) until self.readyCount >= #self.players or (os.clock() - t0) > 2.0
end

function AudioSync:Start()
	local nextIdx = 1

	self.heartbeatConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		while self.eventTimesAbs[nextIdx] and (now + PREVIEW_AHEAD) >= self.eventTimesAbs[nextIdx] do
			local meta = self.eventMeta[nextIdx] or {}
			local color = (meta.kind == "note" and PITCH_COLORING) and colorForPitch(meta.note or 60)
				or colorForBeatIndex(meta.idx or nextIdx)

			-- Spawn visual
			if SPAWN_PER_PLAYER then
				for _, plr in ipairs(self.players) do
					local char = plr.Character
					if char and char:FindFirstChild("HumanoidRootPart") then
						local hrp = char.HumanoidRootPart
						local ahead = hrp.CFrame.LookVector * DIST_AHEAD
						local spawnPoint = Vector3.new(hrp.Position.X + ahead.X, BASE_Y, hrp.Position.Z + ahead.Z)
						spawnVisual(spawnPoint, color)
					end
				end
			else
				local ref = self.players[1]
				if ref and ref.Character and ref.Character:FindFirstChild("HumanoidRootPart") then
					local hrp = ref.Character.HumanoidRootPart
					local ahead = hrp.CFrame.LookVector * DIST_AHEAD
					local spawnPoint = Vector3.new(hrp.Position.X + ahead.X, BASE_Y, hrp.Position.Z + ahead.Z)
					spawnVisual(spawnPoint, color)
				else
					spawnVisual(Vector3.new(0, BASE_Y, DIST_AHEAD), color)
				end
			end

			-- Beep (por notas)
			if METRONOME_ENABLED and METRONOME_SOURCE == "notes" and meta.kind == "note" then
				for _, plr in ipairs(self.players) do
					BeepEvt:FireClient(plr, nextIdx)
				end
			end

			nextIdx += 1
		end
	end)

	-- Espera al final y sugiere offset si hay telemetría
	local last = self.eventTimesAbs[#self.eventTimesAbs] or (os.clock()+1.0)
	while os.clock() < last + 0.2 do task.wait(0.1) end

	-- Telemetría: sugerir nuevo offset (promedio)
	if next(self._startDrifts) ~= nil then
		local sum, n = 0, 0
		for _, d in pairs(self._startDrifts) do sum += d; n += 1 end
		local avg = (n > 0) and (sum / n) or 0
		-- Si avg > 0 → empezaron tarde → sube offset; si < 0 → empezaron antes → baja offset.
		print(("[AudioSyncTest] Drift promedio: %+0.4fs → sugerencia offset = %.2f + (%+.2f) = %.2f")
			:format(avg, self.offset, avg, self.offset + avg))
	end
end

function AudioSync:GetResults()
	local order = {}
	for i, plr in ipairs(self.players) do order[i] = plr.UserId end
	return { placement = order, stats = {} }
end

function AudioSync:Teardown()
	if self.heartbeatConn then self.heartbeatConn:Disconnect() end
	if self._readyConn then self._readyConn:Disconnect() end
	if self._startRptConn then self._startRptConn:Disconnect() end
end

-- Ready handler
ReadyEvt.OnServerEvent:Connect(function(plr, sessionId)
	-- Nota: también llevamos un readyCount por instancia en :Setup()
end)

return {
	GetMeta = AudioSync.GetMeta,
	Create = function(ctx) return AudioSync.new(ctx) end
}
