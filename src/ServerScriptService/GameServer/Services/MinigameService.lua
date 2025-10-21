-- MinigameService.lua  (UTF-8 sin BOM)
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Game.Config.GlobalConfig)
local Catalog = require(RS.Game.Minigames.__catalog__)

local MinigameService = {}
MinigameService.__index = MinigameService

local RNG = Random.new() -- usa Random para shuffles/samples

local function safeRequire(mod)
	local ok, res = pcall(require, mod)
	if ok then return res end
	return nil
end

local function supportsPlayers(meta, count)
	if not meta then return true end
	if typeof(meta) ~= "table" then return true end
	local minP = meta.minPlayers
	local maxP = meta.maxPlayers
	if minP and count and count < minP then return false end
	if maxP and count and count > maxP then return false end
	return true
end

local function fisherYatesShuffle(t)
	for i = #t, 2, -1 do
		local j = RNG:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Colecciona minijuegos disponibles (enabled y que soporten N jugadores)
local function collectAvailable(playersCount)
	local out = {}
	for _, entry in ipairs(Catalog) do
		if entry.enabled ~= false and entry.path then
			local api = safeRequire(entry.path)
			local meta = nil
			if api and typeof(api) == "table" and api.GetMeta then
				local ok, m = pcall(api.GetMeta)
				if ok then meta = m end
			end
			if supportsPlayers(meta, playersCount) then
				table.insert(out, {
					id = entry.id,
					module = entry.path,
					meta = meta
				})
			end
		end
	end
	return out
end

-- Devuelve una rotaciÃ³n de minijuegos respetando MINIGAMES_PER_TOURNAMENT
function MiniggameCap()
	return Config.MINIGAMES_PER_TOURNAMENT or 5
end

function MinigameService.GetRotation(playersArray)
	local playersCount = playersArray and #playersArray or nil
	local available = collectAvailable(playersCount)
	local cap = MiniggameCap()

	if #available == 0 then
		warn("[MinigameService] No hay minijuegos disponibles. Revisa el catÃ¡logo o 'enabled'.")
		return {}
	end

	-- si disponibles <= cap â†’ todos (ordena aleatorio para variety)
	if #available <= cap then
		fisherYatesShuffle(available)
		-- regresa solo los IDs (o mÃ³dulos si prefieres)
		local ids = {}
		for i, it in ipairs(available) do ids[i] = it.id end
		return ids
	end

	-- disponibles > cap â†’ muestreo aleatorio sin reemplazo
	fisherYatesShuffle(available)
	local ids = {}
	for i = 1, cap do
		ids[i] = available[i].id
	end
	return ids
end

return MinigameService
