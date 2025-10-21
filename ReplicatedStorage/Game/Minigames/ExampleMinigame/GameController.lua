-- GameControllerExampleMinigame (contrato base)
local GameController = {}

function GameController.GetMeta()
    return { id = "ExampleMinigame", displayName = "ExampleMinigame", recommendedPlayers = "4-8", version = "0.1.0", tags = {}, weight = 1 }
end

function GameController.Setup(context)  -- sessionId, players, roundIndex, mountFolder
    -- Instancia mapa/arena en context.mountFolder
end

function GameController.Start()
    -- Inicia la lógica del minijuego
end

function GameController.GetResults()
    -- Debe devolver ranking normalizado
    return { placement = {}, times = {}, stats = {} }
end

function GameController.Teardown()
    -- Limpia objetos y conexiones
end

return GameController
