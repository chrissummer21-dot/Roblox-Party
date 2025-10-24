-- ReplicatedStorage/Game/Config/GlobalConfig.lua  (UTF-8 sin BOM)
local M = {
    -- Partidas
    MAX_PLAYERS_PER_SESSION   = 8,
    SESSION_TIMEOUT_TO_START  = 45,
    ROUNDS_PER_MATCH          = 5,
    POINTS_RULES              = { first = 5, second = 3, third = 1 },
    PARALLEL_SESSIONS_LIMIT   = 4,

    -- Torneos
    TOURNAMENT_MAX_PLAYERS    = 32,
    HEAT_SIZES                = {8, 4},
    MINIGAMES_PER_TOURNAMENT  = 5,

    -- UI
    UI_THEME = { primary = Color3.fromRGB(255,255,255) },

    -- Lobby (cola de inicio)
    LOBBY = {
        REQUIRED_PLAYERS = 8,   -- jugadores que deben tocar la StartZone
        START_TIMEOUT    = 5,  -- segundos desde el primer jugador en cola
    },
}

return M
