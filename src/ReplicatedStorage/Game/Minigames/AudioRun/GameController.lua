-- ReplicatedStorage/Game/Minigames/AudioRun/GameController.lua
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIEvent = RS:WaitForChild("Game"):WaitForChild("Net"):WaitForChild("RemoteEvents"):WaitForChild("UIEvent")

local M = {}
M.__index = M

-- ================== CONFIGURACIÓN DE ÓRBITA ==================
local ORBIT_RADIUS = 20     -- Distancia (en studs) desde el centro
local ORBIT_Z_DISTANCE = 25 -- Qué tan "delante" del centro orbita
-- =============================================================

-- ====== META ======
function M.GetMeta()
	return {
		id = "AudioRun",
		name = "Audio Run",
		enabled = true,
		weight = 10,
		minPlayers = 1,
		maxPlayers = 8,
		heatSizes = {1,4,8},
		recommendedPlayers = 1,
	}
end

-- ====== SETUP ======
function M.Setup(context)
	assert(context and context.mountFolder, "AudioRun.Setup: falta context.mountFolder")

	-- 1. Buscar el "FloatPoint"
	local floatPoint = workspace:WaitForChild("FloatPoint", 10) 
	assert(floatPoint and floatPoint:IsA("BasePart"), "AudioRun: No se encontró 'FloatPoint' en el workspace.")

	local centerPos = floatPoint.Position

	-- 2. Obtener lista de jugadores
	local plist = {}
	if context.players and #context.players > 0 then
		for _, p in ipairs(context.players) do table.insert(plist, p) end
	else
		for _, p in ipairs(Players:GetPlayers()) do table.insert(plist, p) end
	end

	-- 3. Teletransportar jugadores y enviar evento al cliente
	for i, plr in ipairs(plist) do
		task.spawn(function()
			local char = plr.Character or plr.CharacterAdded:Wait()
            if char:FindFirstChild("HumanoidRootPart") then
			    local startAngle = (i / #plist) * (math.pi * 2)
                local startPos = centerPos + Vector3.new(
                    ORBIT_RADIUS * math.cos(startAngle), 
                    ORBIT_RADIUS * math.sin(startAngle),
                    ORBIT_Z_DISTANCE
                )
			    char:PivotTo(CFrame.new(startPos))
            end
			
            -- 4. Enviar orden al cliente
			UIEvent:FireClient(plr, {
				type = "MinigameUI",
				minigame = "AudioRun",
				payload = {
                    command     = "StartFloat",
                    centerPoint = centerPos,
                    radius      = ORBIT_RADIUS,
                    orbitZ      = centerPos.Z + ORBIT_Z_DISTANCE,
					sessionId   = context.sessionId,
					songId      = "rbxassetid://18434858608",
					offset      = 0.6
				}
			})
		end)
	end

	-- 5. Devolver 'state' mínimo
	local state = {
		map = floatPoint,
		startPad = floatPoint,
		players = plist,
        connections = {},
        hiddenInstances = {} -- <-- Guardaremos todo lo que ocultemos aquí
	}
    
    --
    -- V V V LÓGICA DE OCULTAR MEJORADA V V V
    --
    -- 6. Ocultar partes del workspace
    local instancesToHide = {
        workspace:FindFirstChild("Baseplate"),
        workspace:FindFirstChild("StartZone")
    }

    for _, inst in ipairs(instancesToHide) do
        if inst then
            local originalProperties = {}
            
            -- Recolectar el objeto principal y todos sus descendientes
            local itemsToFade = { inst }
            for _, descendant in ipairs(inst:GetDescendants()) do
                table.insert(itemsToFade, descendant)
            end

            -- Iterar sobre todo (Baseplate, StartZone Y sus hijos/texturas)
            for _, item in ipairs(itemsToFade) do
                if item:IsA("BasePart") then
                    -- Guardar estado original
                    originalProperties[item] = {
                        Transparency = item.Transparency,
                        CanCollide = item.CanCollide
                    }
                    -- Ocultar
                    item.Transparency = 1
                    item.CanCollide = false
                
                elseif item:IsA("Decal") or item:IsA("Texture") then
                    -- ¡Aquí está la clave! Ocultar también texturas y calcomanías
                    originalProperties[item] = {
                        Transparency = item.Transparency
                    }
                    -- Ocultar
                    item.Transparency = 1
                end
            end
            
            -- Guardar todos los cambios hechos
            table.insert(state.hiddenInstances, {
                instance = inst,
                properties = originalProperties
            })
        end
    end
    --
    -- A A A FIN DE LA LÓGICA MEJORADA A A A
    --

	return state
end

-- ====== START ======
function M.Start(state)
	print("[AudioRun] Start (Modo Flotar Orbital)")
    task.wait(30) -- Duración del minijuego
	
	local placement = {}
	for rank, p in ipairs(state.players) do
		table.insert(placement, { userId = p.UserId, name = p.Name, rank = rank })
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
    -- 6. Decir a los clientes que dejen de flotar
	for _, plr in ipairs(state.players) do
        pcall(function()
		    UIEvent:FireClient(plr, {
			    type = "MinigameUI",
			    minigame = "AudioRun",
			    payload = { command = "StopFloat" }
		    })
        end)
	end
    
    --
    -- V V V LÓGICA DE RESTAURAR MEJORADA V V V
    --
    -- 7. Restaurar partes ocultas (incluyendo texturas)
    if state.hiddenInstances then
        for _, data in ipairs(state.hiddenInstances) do
            local inst = data.instance
            
            -- Restaurar todas las propiedades guardadas
            for item, props in pairs(data.properties) do
                -- Verificar si el objeto aún existe antes de cambiarlo
                if item and pcall(function() return item.Parent end) then 
                    if props.Transparency ~= nil then
                        item.Transparency = props.Transparency
                    end
                    if props.CanCollide ~= nil then
                        item.CanCollide = props.CanCollide
                    end
                end
            end
        end
    end
    --
    -- A A A FIN DE LA LÓGICA MEJORADA A A A
    --
end

return M