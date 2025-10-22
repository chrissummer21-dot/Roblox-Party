-- ReplicatedStorage/Game/Config/MinigameCatalog.lua
-- Catálogo central y único de minijuegos (client-safe).

local RS = game:GetService("ReplicatedStorage")
local GameFolder = RS:WaitForChild("Game")
local MinigamesFolder = GameFolder:WaitForChild("Minigames")
local GlobalConfig = require(GameFolder:WaitForChild("Config"):WaitForChild("GlobalConfig"))

local Catalog = {}   -- [id] = { module = table, meta = table }
local Order = {}     -- ids en orden de registro

local function add(moduleScript)
	local ok, mod = pcall(function() return require(moduleScript) end)
	if not ok then warn("[MinigameCatalog] require falló:", moduleScript:GetFullName(), mod); return end
	if type(mod) ~= "table" or type(mod.GetMeta) ~= "function" then
		warn("[MinigameCatalog] módulo inválido (sin GetMeta):", moduleScript:GetFullName()); return
	end
	local okMeta, meta = pcall(mod.GetMeta)
	if not okMeta or type(meta) ~= "table" or not meta.id then
		warn("[MinigameCatalog] meta inválida:", moduleScript:GetFullName()); return
	end
	if meta.name == nil then meta.name = meta.id end
	if meta.weight == nil then meta.weight = 1 end
	Catalog[meta.id] = { module = mod, meta = meta }
	table.insert(Order, meta.id)
	print(("[MinigameCatalog] Registrado: %s (enabled=%s, weight=%s)")
		:format(meta.id, tostring(meta.enabled ~= false), tostring(meta.weight)))
end

-- ======= Registro de minijuegos (agrega aquí los que tengas) =======
do
	-- AudioRun
	local f = MinigamesFolder:FindFirstChild("AudioRun")
	if f and f:FindFirstChild("GameController") then add(f.GameController)
	else warn("[MinigameCatalog] No se encontró AudioRun/GameController") end

	-- Ejemplos (descomenta cuando existan)
	-- local ex = MinigamesFolder:FindFirstChild("ExampleMinigame"); if ex and ex:FindFirstChild("GameController") then add(ex.GameController) end
	-- local sync = MinigamesFolder:FindFirstChild("AudioSyncTest"); if sync and sync:FindFirstChild("GameController") then add(sync.GameController) end
end
-- ===================================================================

-- Helpers de elegibilidad
local function minP(meta) return meta.minPlayers or GlobalConfig.MIN_PLAYERS_FALLBACK or 1 end
local function maxP(meta) return meta.maxPlayers or math.huge end
local function weight(meta) return tonumber(meta.weight) or 0 end
local function enabled(meta) return meta.enabled ~= false end
local function okSize(meta, count)
	local sizes = meta.heatSizes
	if sizes and #sizes > 0 then
		if GlobalConfig.ALLOW_SOLO_HEATS and count == 1 then return true end
		return table.find(sizes, count) ~= nil
	end
	return true
end

-- API pública
local API = {}

function API.Get(id) return Catalog[id] and Catalog[id].module or nil end
function API.GetMeta(id) return Catalog[id] and Catalog[id].meta or nil end

function API.All()
	local list = {}
	for _, id in ipairs(Order) do
		local e = Catalog[id]; if e then table.insert(list, { id = id, meta = e.meta }) end
	end
	return list
end

function API.EligibleForPlayerCount(count)
	local out = {}
	for _, id in ipairs(Order) do
		local e = Catalog[id]; local meta = e.meta
		if enabled(meta) and weight(meta) > 0 and count >= minP(meta) and count <= maxP(meta) and okSize(meta, count) then
			table.insert(out, { id = id, module = e.module, meta = meta, weight = weight(meta) })
		end
	end
	return out
end

function API.BuildRotation(rounds, count, allowRepeats)
	rounds = math.max(1, tonumber(rounds) or 1)
	local elig = API.EligibleForPlayerCount(count)
	if #elig == 0 then return {} end
	if #elig == 1 or allowRepeats then
		local id = elig[1].id; local rot = {}
		for i=1,rounds do table.insert(rot, id) end; return rot
	end
	local rot, pool = {}, table.clone(elig)
	for i=1,rounds do
		if #pool == 0 then pool = table.clone(elig) end
		table.insert(rot, table.remove(pool, 1).id) -- simple no-repeats
	end
	return rot
end

return API
