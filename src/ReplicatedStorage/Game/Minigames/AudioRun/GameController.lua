-- ServerScriptService/GameServer/Controllers/SessionController.lua
-- Controla el ciclo de vida de una sesión: Setup → Start → GetResults → Teardown

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local NetFolder      = RS:WaitForChild("Game"):WaitForChild("Net")
local RemoteEvents   = NetFolder:WaitForChild("RemoteEvents")
local MatchmakingEvent = RemoteEvents:WaitForChild("MatchmakingEvent")

local GameFolder = RS:WaitForChild("Game")
local Config     = require(GameFolder:WaitForChild("Config"):WaitForChild("GlobalConfig"))
local Catalog    = require(GameFolder:WaitForChild("Config"):WaitForChild("MinigameCatalog"))

local C = {}

-- ===========================
-- Helpers
-- ===========================
local SessionsFolder = workspace:FindFirstChild("Sessions") or (function()
	local f = Instance.new("Folder")
	f.Name = "Sessions"
	f.Parent = workspace
	return f
end)()

local function getOrCreateMount(sessionId: string)
	local f = SessionsFolder:FindFirstChild(sessionId)
	if not f then
		f = Instance.new("Folder")
		f.Name = sessionId
		f.Parent = SessionsFolder
	end
	return f
end

local function tpToPartReliable(plr: Player, target: BasePart)
	if not (plr and target and target:IsA("BasePart")) then return end
	task.spawn(function()
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hum  = char:WaitForChild("Humanoid")
		local hrp  = char:WaitForChild("HumanoidRootPart")

		-- “libera” por si algún LocalScript lo dejó atado
		hum.PlatformStand = false
		hrp.Anchored = false

		for _ = 1, 8 do
			char:PivotTo(CFrame.new(target.Position + Vector3.new(0, 4, 0)))
			hrp.AssemblyLinearVelocity = Vector3.zero
			task.wait(0.06)
			if (hrp.Position - target.Position).Magnitude <= 8 then break end
		end
	end)
end

local function buildContext(sessionId: string, playerIds: {number}?)
	local plist = {}

	if playerIds and #playerIds > 0 then
		for _, uid in ipairs(playerIds) do
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == uid then table.insert(plist, p) break end
			end
		end
	else
		-- fallback: todos los jugadores presentes (para pruebas/solo)
		for _, p in ipairs(Players:GetPlayers()) do table.insert(plist, p) end
	end

	return {
		sessionId   = sessionId,
		players     = plist,
		mountFolder = getOrCreateMount(sessionId),
	}
end

-- Normaliza el "state" que viene del minijuego tras Setup:
-- - Acepta módulos que devuelven un state con .map
-- - Acepta módulos que guardan en state._<id>.map (ej. context._audiorun.map)
-- - Acepta módulos que no devuelven nada (usamos ctx como state)
local function normalizeStateAfterSetup(minigameId: string, ctx, setupReturn)
	local state = setupReturn or ctx
	if not state then
		warn(("[SessionController] %s: Setup no devolvió state ni hay ctx; usando tabla vacía."):format(minigameId))
		state = {}
	end

	-- Propaga información básica por si el módulo la espera
	state.sessionId   = state.sessionId or ctx.sessionId
	state.players     = state.players or ctx.players
	state.mountFolder = state.mountFolder or ctx.mountFolder

	-- Intenta localizar el mapa
	if not state.map then
		-- Convención: algunos módulos guardan context._<minijuego>.map
		-- Ejemplo AudioRun: context._audiorun.map
		for _, child in pairs(state) do
			if typeof(child) == "table" and child.map then
				state.map = child.map
				break
			end
		end
	end

	return state
end

-- ===========================
-- API principal
-- ===========================
-- sessionSpec esperado:
-- {
--   sessionId = "S0001",
--   roundCount = number (opcional; default Config.ROUNDS_PER_MATCH),
--   playerIds = {<UserId>...} (opcional),
--   forceMinigames = {"AudioRun", ...} (opcional)
-- }
function C.StartSession(sessionSpec)
	assert(sessionSpec and sessionSpec.sessionId, "[SessionController] sessionSpec.sessionId requerido")

	local sessionId   = sessionSpec.sessionId
	local ctx         = buildContext(sessionId, sessionSpec.playerIds)
	local playerCount = #ctx.players

	if playerCount == 0 then
		warn(("[SessionController] %s: sin jugadores; abortando."):format(sessionId))
		return false
	end

	local rounds = tonumber(sessionSpec.roundCount) or Config.ROUNDS_PER_MATCH or 1

	-- Construir rotación
	local rotation
	if sessionSpec.forceMinigames and #sessionSpec.forceMinigames > 0 then
		rotation = sessionSpec.forceMinigames
	else
		rotation = Catalog.BuildRotation(rounds, math.max(1, playerCount), true)
	end

	if not rotation or #rotation == 0 then
		warn(("[SessionController] %s: sin minijuegos elegibles."):format(sessionId))
		return false
	end

	print(("[SessionController] %s: Rotación -> %s"):format(sessionId, table.concat(rotation, ", ")))

	-- Ejecutar cada minijuego en orden
	for _, minigameId in ipairs(rotation) do
		local mod = Catalog.Get(minigameId)
		if not mod then
			warn(("[SessionController] %s: %s no está en el catálogo; saltando."):format(sessionId, tostring(minigameId)))
			continue
		end

		-- ===== Setup =====
		local setupReturn
		local ok, err = pcall(function()
			setupReturn = mod.Setup(ctx)
		end)
		if not ok then
			warn(("[SessionController] %s: %s.Setup lanzó error: %s"):format(sessionId, minigameId, tostring(err)))
			continue
		end

		local state = normalizeStateAfterSetup(minigameId, ctx, setupReturn)

		-- Validaciones de mapa + logs útiles
		local map = state.map
		if not map then
			local hint = "No se encontró state.map ni state._*.map después de Setup."
			if state.mountFolder == nil then
				hint = hint .. " mountFolder también es nil (revisa buildContext)."
			end
			warn(("[SessionController] %s: %s.Setup sin mapa. %s"):format(sessionId, minigameId, hint))
			continue
		end

		-- ===== TP robusto previo (opcional) =====
		-- Preferimos StartPad si existe; si no, usamos FloatPoint (AudioRun)
		local startPad = map:FindFirstChild("StartPad", true)
		local floatPoint = startPad and nil or map:FindFirstChild("FloatPoint", true)
		local tpTarget = nil

		if startPad and startPad:IsA("BasePart") then
			tpTarget = startPad
		elseif floatPoint and floatPoint:IsA("BasePart") then
			tpTarget = floatPoint
		end

		if tpTarget then
			for _, plr in ipairs(state.players or {}) do
				tpToPartReliable(plr, tpTarget)
			end
		else
			warn(("[SessionController] %s: %s sin StartPad/FloatPoint; se salta TP previo."):format(sessionId, minigameId))
		end

		-- ===== Start =====
		local startedOk, startErr = pcall(function()
			return mod.Start(state)
		end)
		if not startedOk then
			warn(("[SessionController] %s: %s.Start error: %s"):format(sessionId, minigameId, tostring(startErr)))
		end

		-- ===== Results =====
		local results = nil
		local gotRes, resErr = pcall(function()
			results = mod.GetResults(state)
		end)
		if not gotRes then
			warn(("[SessionController] %s: %s.GetResults error: %s"):format(sessionId, minigameId, tostring(resErr)))
		else
			print(("[SessionController] %s: %s resultados listos."):format(sessionId, minigameId))
			-- Aquí podrías enviar resultados a UI/ScoringService
		end

		-- ===== Teardown =====
		local _, tdErr = pcall(function()
			mod.Teardown(state)
		end)
		if tdErr then
			warn(("[SessionController] %s: %s.Teardown error: %s"):format(sessionId, minigameId, tostring(tdErr)))
		end

		-- Pausa pequeña entre rondas
		task.wait(1)
	end

	print(("[SessionController] %s: sesión finalizada."):format(sessionId))
	return true
end

-- ===========================
-- Compat: escucha MatchmakingEvent("StartSession", spec) desde cliente
-- (Mejor llamar C.StartSession() desde el servidor/LobbyStartZone)
-- ===========================
MatchmakingEvent.OnServerEvent:Connect(function(player, cmd, spec)
	if cmd == "StartSession" then
		print(("[SessionController] petición de %s para iniciar sesión."):format(player.Name))
		C.StartSession(spec or { sessionId = ("S%s"):format(tostring(os.time() % 10000)) })
	end
end)

return C
