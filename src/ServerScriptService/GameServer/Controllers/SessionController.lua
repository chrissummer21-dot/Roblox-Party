-- ServerScriptService/GameServer/Controllers/SessionController.lua
-- Controla el ciclo de vida de una sesión: Setup → Start → GetResults → Teardown

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local NetFolder   = RS:WaitForChild("Game"):WaitForChild("Net")
local RemoteEvents= NetFolder:WaitForChild("RemoteEvents")
local MatchmakingEvent = RemoteEvents:WaitForChild("MatchmakingEvent")

local GameFolder  = RS:WaitForChild("Game")
local Config      = require(GameFolder:WaitForChild("Config"):WaitForChild("GlobalConfig"))
local Catalog     = require(GameFolder:WaitForChild("Config"):WaitForChild("MinigameCatalog"))

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
	task.spawn(function()
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hum  = char:WaitForChild("Humanoid")
		local hrp  = char:WaitForChild("HumanoidRootPart")

		-- “libera” por si algún LocalScript lo dejó atado
		hum.PlatformStand = false
		hrp.Anchored = false

		for i = 1, 8 do
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

	local sessionId  = sessionSpec.sessionId
	local ctx        = buildContext(sessionId, sessionSpec.playerIds)
	local playerCount= #ctx.players

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
	for idx, minigameId in ipairs(rotation) do
		local mod = Catalog.Get(minigameId)
		if not mod then
			warn(("[SessionController] %s: %s no está en el catálogo; saltando."):format(sessionId, tostring(minigameId)))
		else
			-- ===== Setup =====
			local state
			local ok, err = pcall(function()
				state = mod.Setup(ctx)
			end)
			if not ok or not state or not state.map then
				warn(("[SessionController] %s: %s.Setup falló: %s"):format(sessionId, minigameId, tostring(err)))
				continue
			end

			-- TP robusto extra (además del TP interno del minijuego)
			local startPad = state.startPad or state.map:FindFirstChild("StartPad", true)
			if startPad and startPad:IsA("BasePart") then
				for _, plr in ipairs(ctx.players) do
					tpToPartReliable(plr, startPad)
				end
			else
				warn(("[SessionController] %s: %s sin StartPad visible."):format(sessionId, minigameId))
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
			pcall(function()
				mod.Teardown(state)
			end)

			-- Pequeña pausa entre rondas
			task.wait(1)
		end
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
