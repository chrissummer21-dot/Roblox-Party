-- ReplicatedStorage/Game/Minigames/MinigameCatalog.lua
-- Catálogo central de minijuegos: registro, consulta y selección por elegibilidad/peso.

local RS = game:GetService("ReplicatedStorage")
local GameFolder = RS:WaitForChild("Game")
local MinigamesFolder = GameFolder:WaitForChild("Minigames")
local ConfigFolder = GameFolder:WaitForChild("Config")
local GlobalConfig = require(ConfigFolder:WaitForChild("GlobalConfig"))

local Catalog = {}         -- [id] = { module = ModuleTable, meta = table }
local Order = {}           -- lista de ids en orden de registro

-- =========================
-- Utilidades
-- =========================
local function defaultMinPlayers(meta)
	-- Fallback global si no se define; por defecto 1 para permitir pruebas en solo.
	if meta.minPlayers ~= nil then return meta.minPlayers end
	return GlobalConfig.MIN_PLAYERS_FALLBACK or 1
end

local function defaultMaxPlayers(meta)
	return meta.maxPlayers or math.huge
end

local function isEnabled(meta)
	if meta.enabled == nil then return true end
	return meta.enabled == true
end

local function normalizeHeatSizes(meta)
	-- Si el allocator usa tamaños exactos y no vienen del meta,
	-- podemos aceptar cualquiera de los declarados globalmente.
	if meta.heatSizes and #meta.heatSizes > 0 then
		return meta.heatSizes
	end
	return GlobalConfig.HEAT_SIZES or {} -- puede estar vacío; entonces no restringe por tamaño
end

local function eligibleForCount(meta, playerCount)
	local minP = defaultMinPlayers(meta)
	local maxP = defaultMaxPlayers(meta)
	if playerCount < minP or playerCount > maxP then return false end

	local sizes = normalizeHeatSizes(meta)
	if sizes and #sizes > 0 then
		-- Si definiste permitir solo heats:
		if GlobalConfig.ALLOW_SOLO_HEATS and playerCount == 1 then
			return true
		end
		return table.find(sizes, playerCount) ~= nil
	end

	return true
end

local function weightOf(meta)
	local w = tonumber(meta.weight)
	if not w or w < 0 then return 0 end
	return w
end

local function pickWeighted(eligibleList)
	-- eligibleList: array de {id, meta, module, weight}
	local total = 0
	for _, it in ipairs(eligibleList) do
		total += (it.weight or 0)
	end
	if total <= 0 then
		-- sin pesos, devolver primero
		return eligibleList[1]
	end
	local r = math.random() * total
	local acc = 0
	for _, it in ipairs(eligibleList) do
		acc += (it.weight or 0)
		if r <= acc then return it end
	end
	return eligibleList[#eligibleList]
end

-- =========================
-- API de Registro
-- =========================
local function add(moduleScript)
	-- Registra un ModuleScript de minijuego (GameController.lua)
	local ok, mod = pcall(function() return require(moduleScript) end)
	if not ok then
		warn(("[MinigameCatalog] No se pudo require '%s': %s"):format(moduleScript:GetFullName(), tostring(mod)))
		return
	end
	if type(mod) ~= "table" or type(mod.GetMeta) ~= "function" then
		warn(("[MinigameCatalog] Módulo inválido (sin GetMeta): %s"):format(moduleScript:GetFullName()))
		return
	end

	local metaOk, meta = pcall(mod.GetMeta)
	if not metaOk or type(meta) ~= "table" or not meta.id then
		warn(("[MinigameCatalog] Meta inválida en '%s'"):format(moduleScript:GetFullName()))
		return
	end

	-- Normalizaciones mínimas
	if meta.name == nil then meta.name = meta.id end
	if meta.weight == nil then meta.weight = 1 end

	Catalog[meta.id] = { module = mod, meta = meta }
	table.insert(Order, meta.id)
	print(("[MinigameCatalog] Registrado: %s (weight=%s, enabled=%s)")
		:format(meta.id, tostring(meta.weight), tostring(meta.enabled)))
end

-- =========================
-- Poblado del catálogo
-- =========================
-- ✅ Con un solo minijuego:
do
	-- ReplicatedStorage/Game/Minigames/AudioRun/GameController
	local audioRun = MinigamesFolder:FindFirstChild("AudioRun")
	if audioRun and audioRun:FindFirstChild("GameController") then
		add(audioRun.GameController)
	else
		warn("[MinigameCatalog] AudioRun no encontrado. Revisa la ruta: ReplicatedStorage/Game/Minigames/AudioRun/GameController")
	end

	-- Si luego agregas más, repite `add`:
	-- add(MinigamesFolder.ObstacleRun.GameController)
	-- add(MinigamesFolder.ButtonMash.GameController)
end

-- =========================
-- API de Consulta
-- =========================
local API = {}

function API.Get(id)
	-- Devuelve el módulo (tabla) del minijuego (para llamar Setup/Start/GetResults/Teardown).
	return Catalog[id] and Catalog[id].module or nil
end

function API.GetMeta(id)
	return Catalog[id] and Catalog[id].meta or nil
end

function API.All()
	-- Devuelve array con {id, meta}
	local list = {}
	for _, id in ipairs(Order) do
		local entry = Catalog[id]
		if entry then
			table.insert(list, { id = id, meta = entry.meta })
		end
	end
	return list
end

function API.EligibleForPlayerCount(playerCount, opts)
	-- Devuelve array de elegibles con {id, meta, module, weight}
	opts = opts or {}
	local out = {}
	for _, id in ipairs(Order) do
		local entry = Catalog[id]
		if entry then
			local meta = entry.meta
			if isEnabled(meta) and (weightOf(meta) > 0) and eligibleForCount(meta, playerCount) then
				table.insert(out, {
					id = id,
					meta = meta,
					module = entry.module,
					weight = weightOf(meta)
				})
			end
		end
	end
	return out
end

function API.BuildRotation(rounds, playerCount, allowRepeats)
	-- rounds: número de rondas a jugar
	-- playerCount: jugadores en el heat
	-- allowRepeats: si false, intenta no repetir hasta agotar opciones
	rounds = math.max(1, tonumber(rounds) or 1)
	local elig = API.EligibleForPlayerCount(playerCount) -- ya filtra enabled/weight>0

	if #elig == 0 then
		warn(("[MinigameCatalog] Sin minijuegos elegibles para %d jugadores."):format(playerCount))
		return {}
	end

	-- Caso trivial: solo uno y/o permitidos repetidos
	if #elig == 1 or allowRepeats == true then
		local id = elig[1].id
		local rot = {}
		for i = 1, rounds do table.insert(rot, id) end
		return rot
	end

	-- Intento sin repetición, usando peso en cada elección
	local rot = {}
	local pool = table.clone(elig)
	for i = 1, rounds do
		if #pool == 0 then
			-- se acabaron opciones, repetimos desde cero
			pool = table.clone(elig)
		end
		local pick = pickWeighted(pool)
		table.insert(rot, pick.id)

		-- eliminar elegido para evitar repetir inmediatamente
		for idx, it in ipairs(pool) do
			if it.id == pick.id then
				table.remove(pool, idx)
				break
			end
		end
	end
	return rot
end

return API
