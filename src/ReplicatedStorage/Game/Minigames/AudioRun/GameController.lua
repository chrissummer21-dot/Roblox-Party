-- ReplicatedStorage/Game/Minigames/AudioRun/GameController.lua
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

local M = {}
M.__index = M

-- ====== META ======
function M.GetMeta()
	return {
		id = "AudioRun",
		name = "Audio Run",
		enabled = true,
		weight = 10,
		minPlayers = 1,           -- 👉 permite solo
		maxPlayers = 8,
		heatSizes = {1,4,8},      -- 👉 incluye 1
		recommendedPlayers = 1,
	}
end

-- ====== SETUP ======
function M.Setup(context)
	-- context: { sessionId, players, mountFolder }
	assert(context and context.mountFolder, "AudioRun.Setup: falta context.mountFolder")

	-- Traer mapa base
	local mapSrc = game.ServerStorage.Maps.MinigameMaps:FindFirstChild("AudioRunMap")
	assert(mapSrc, "AudioRunMap no existe en ServerStorage/Maps/MinigameMaps")

	-- Clonar en la carpeta de la sesión
	local map = mapSrc:Clone()
	map.Name = "AudioRunMap_runtime"
	map.Parent = context.mountFolder

	-- Hallar marcadores
	local markers = map:FindFirstChild("Markers")
	assert(markers, "AudioRun: falta folder Markers")
	local startPad = markers:FindFirstChild("StartPad")
	local goal = markers:FindFirstChild("Goal")
	assert(startPad and goal, "AudioRun: faltan StartPad o Goal")

	-- Audio
	local sound = map:FindFirstChild("Song", true)
	assert(sound and sound:IsA("Sound") and sound.SoundId ~= "", "AudioRun: Sound (Song) inválido")
	ContentProvider:PreloadAsync({sound})

	-- Lista de jugadores (fallback si el servicio no la pasa)
	local plist = {}
	if context.players and #context.players > 0 then
		for _, p in ipairs(context.players) do table.insert(plist, p) end
	else
		for _, p in ipairs(Players:GetPlayers()) do table.insert(plist, p) end
	end

	-- Teleport suave a StartPad
	for _, p in ipairs(plist) do
		local char = p.Character or p.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart")
		hrp.CFrame = CFrame.new(startPad.Position + Vector3.new(0, 3, 0))
	end

	-- Estado del minijuego
	local state = {
		map = map,
		startPad = startPad,
		goal = goal,
		sound = sound,
		startTime = 0,
		finishTimes = {},  -- userId -> seconds
		finished = {},     -- userId -> true
		results = nil,
		players = plist,
	}

	-- Conexion de meta
	state.goalConn = goal.Touched:Connect(function(hit)
		local char = hit and hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
		local plr = Players:GetPlayerFromCharacter(char); if not plr then return end

		if not state.finished[plr.UserId] and state.startTime > 0 then
			state.finished[plr.UserId] = true
			local t = os.clock() - state.startTime
			state.finishTimes[plr.UserId] = t
			print(("[AudioRun] %s terminó en %.2fs"):format(plr.Name, t))
		end
	end)

	return state
end

-- ====== START ======
function M.Start(state)
	print("[AudioRun] Start")
	-- Cuenta regresiva simple (servidor)
	for i = 3,1,-1 do
		print("[AudioRun] "..i)
		task.wait(1)
	end

	-- Reproducir música y arrancar cronómetro
	state.sound:Play()
	state.startTime = os.clock()

	-- Duración máxima de la prueba (fallback) — 90s
	local TIMEOUT = 90
	local t0 = os.clock()
	while os.clock() - t0 < TIMEOUT do
		-- si todos terminaron, salimos antes
		local allDone = true
		for _, p in ipairs(state.players) do
			if not state.finished[p.UserId] then allDone = false break end
		end
		if allDone then break end
		task.wait(0.2)
	end

	-- Armar resultados (orden por menor tiempo; quien no llegó, al final)
	local scored = {}
	for _, p in ipairs(state.players) do
		local ft = state.finishTimes[p.UserId]
		table.insert(scored, {player = p, time = ft or math.huge})
	end
	table.sort(scored, function(a,b) return a.time < b.time end)

	local placement = {}
	for rank, row in ipairs(scored) do
		table.insert(placement, {
			userId = row.player.UserId,
			name = row.player.Name,
			time = (row.time ~= math.huge) and row.time or nil,
			rank = rank
		})
	end

	state.results = { placement = placement }
	print("[AudioRun] Start OK. Resultados listos.")
	return true
end

-- ====== GET RESULTS ======
function M.GetResults(state)
	return state.results or { placement = {} }
end

-- ====== TEARDOWN ======
function M.Teardown(state)
	if state.goalConn then
		pcall(function() state.goalConn:Disconnect() end)
	end
	if state.map and state.map.Parent then
		state.map:Destroy()
	end
end

return M
