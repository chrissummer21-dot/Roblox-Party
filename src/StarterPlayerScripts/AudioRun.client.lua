-- Cliente: manejar movimiento ORBITAL (Vertical X-Y) y lógica de flotar (SIN MÚSICA)
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Net = RS.Game.Net
local RE  = Net.RemoteEvents
local MG  = RE:WaitForChild("MinigameRemotes") -- Corregido (de v10)
local ReadyEvt = MG:WaitForChild("AudioRun_ClientReady")
local UIEvent  = RE:WaitForChild("UIEvent")

-- ================== CONFIGURACIÓN DE MOVIMIENTO ==================
local ORBIT_SPEED = 1.5     -- Velocidad de rotación (radianes/segundo)
local CAMERA_Z_OFFSET = 30  -- Cámara alejada (desde v9)
local FIELD_OF_VIEW = 95    -- Lente angular (ojo de pez leve)
-- =============================================================

-- Estado del minijuego
local currentSessionId = nil
local isFloating = false

-- Estado de movimiento orbital
local centerPoint = Vector3.zero
local orbitRadius = 20
local orbitZ = 0
local currentAngle = 0
local orbitDirection = 0

-- Estado de la cámara
local FIXED_CAM_POS = Vector3.zero
local originalFOV = 70

-- Conexiones
local stepConn = nil
local swimTrack, swimIdleTrack = nil, nil
local originalCameraType = nil
local hrp, humanoid, animator

-- ===== LÓGICA DE FLOTAR/NADAR (Movimiento) =====

local function getSwimAnimations(character)
	local animate = character:FindFirstChild("Animate")
	if not animate then return nil, nil end
	local swim = animate:FindFirstChild("swim")
	local swimidle = animate:FindFirstChild("swimidle") or animate:FindFirstChild("swimIdle") or animate:FindFirstChild("swimIdle2")
	local swimAnim = swim and swim:FindFirstChildWhichIsA("Animation")
	local swimIdleAnim = swimidle and swimidle:FindFirstChildWhichIsA("Animation")
	return swimAnim, swimIdleAnim
end

local function stopTrack(t) 
    if t then pcall(function() t:Stop(0.15) end) end 
end

-- Función para DETENER el modo flotar
local function cleanupFloat()
    if not isFloating then return end
    isFloating = false
    
	if stepConn then stepConn:Disconnect() stepConn = nil end

	stopTrack(swimTrack); stopTrack(swimIdleTrack)
	swimTrack, swimIdleTrack = nil, nil

    orbitDirection = 0
    centerPoint = Vector3.zero
    FIXED_CAM_POS = Vector3.zero

	if humanoid then
		pcall(function() humanoid.AutoRotate = true end)
		pcall(function() humanoid.WalkSpeed = 16 end)
		pcall(function() humanoid.PlatformStand = false end)
	end

	if hrp then
		pcall(function() hrp.Anchored = false end)
	end

	local cam = workspace.CurrentCamera
	if cam then
        if originalCameraType then
		    cam.CameraType = originalCameraType
            originalCameraType = nil
        end
        cam.FieldOfView = originalFOV -- Restaurar FOV
	end
    
    hrp, humanoid, animator = nil, nil, nil
end

-- Función para INICIAR el modo flotar
local function startFloat()
    -- (Control de 'isFloating' ahora manejado por el evento)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    if not (character and isFloating) then return end

	hrp      = character:WaitForChild("HumanoidRootPart", 5)
	humanoid = character:WaitForChild("Humanoid", 5)
    if not (hrp and humanoid and isFloating) then 
        warn("AudioRun: No se pudo encontrar HRP/Humanoid o el juego terminó.")
        return 
    end
    
	animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	local startPos = hrp.Position
    orbitDirection = 0
    currentAngle = math.atan2(startPos.Y - centerPoint.Y, startPos.X - centerPoint.X)

	-- Bloquear movimiento
    humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
	humanoid.AutoRotate = false
	humanoid.WalkSpeed  = 0
	humanoid.PlatformStand = true
	hrp.Anchored = true

	-- Cargar animaciones (sin cambios)
	local swimAnim, swimIdleAnim = getSwimAnimations(character)
	local animToPlay = nil
	if swimAnim then
		swimTrack = animator:LoadAnimation(swimAnim)
		swimTrack.Priority = Enum.AnimationPriority.Movement
		swimTrack.Looped   = true
        animToPlay = swimTrack
	end
	if swimIdleAnim then
		swimIdleTrack = animator:LoadAnimation(swimIdleAnim)
		swimIdleTrack.Priority = Enum.AnimationPriority.Movement
		swimIdleTrack.Looped   = true
        if not animToPlay then animToPlay = swimIdleTrack end
	end
    if animToPlay then animToPlay:Play(0.1) end
    
    -- Controlar la cámara
    local cam = workspace.CurrentCamera
	if cam then
		originalCameraType = cam.CameraType
        originalFOV = cam.FieldOfView
		cam.CameraType = Enum.CameraType.Scriptable
        cam.FieldOfView = FIELD_OF_VIEW
        
        -- CÁMARA FIJA: Posición
        FIXED_CAM_POS = Vector3.new(centerPoint.X, centerPoint.Y, orbitZ + CAMERA_Z_OFFSET)
	end

	-- Conexión de RenderStepped
	stepConn = RunService.RenderStepped:Connect(function(dt)
		if not (isFloating and hrp and hrp.Parent and humanoid and humanoid.Health > 0 and cam) then
			cleanupFloat()
            if isFloating then task.spawn(startFloat) end -- Reconectar si morimos
            return
		end
        
        -- 1. Actualizar el ÁNGULO
        currentAngle = currentAngle + (orbitDirection * ORBIT_SPEED * dt)
        
        -- 2. Calcular la nueva posición X, Y
        local x = centerPoint.X + orbitRadius * math.cos(currentAngle)
        local y = centerPoint.Y + orbitRadius * math.sin(currentAngle)
        local newPos = Vector3.new(x, y, orbitZ)
        
        -- 3. Vector "Up" (cabeza) del jugador (radial)
        local radialUpVector = (Vector3.new(newPos.X, newPos.Y, 0) - Vector3.new(centerPoint.X, centerPoint.Y, 0)).Unit
        if radialUpVector.Magnitude < 0.9 then
            radialUpVector = Vector3.new(0, 1, 0) -- Fallback si estamos en el centro exacto
        end

        -- 4. JUGADOR mira al centro (igual que antes)
		hrp.CFrame = CFrame.lookAt(newPos, centerPoint, radialUpVector)
		
        -- 5. CÁMARA fija mirando al centro (igual que antes, con nuevo FOV)
        cam.CFrame = CFrame.lookAt(FIXED_CAM_POS, centerPoint)
        
        -- 6. Re-asegurar el estado
        if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
            humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
        end
        if not humanoid.PlatformStand then
            humanoid.PlatformStand = true
        end
        if not hrp.Anchored then
            hrp.Anchored = true
        end
	end)
end

-- ===== MANEJO DE EVENTOS (Sin cambios salvo música eliminada) =====
UIEvent.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	if msg.type == "MinigameUI" and msg.minigame == "AudioRun" then
        local command = msg.payload.command
        
        if command == "StartFloat" then
            if isFloating then return end
            isFloating = true
		    currentSessionId = msg.payload.sessionId
            centerPoint = msg.payload.centerPoint
            orbitRadius = msg.payload.radius
            orbitZ = msg.payload.orbitZ
            -- música eliminada
            task.spawn(startFloat)
            ReadyEvt:FireServer(currentSessionId)
        
        elseif command == "StopFloat" then
            if not isFloating then return end
            isFloating = false
            cleanupFloat()
            -- música eliminada
            currentSessionId = nil
        end
	end
end)

-- Input (SIN CAMBIOS de lógica; solo se corrige el typo de Left)
UIS.InputBegan:Connect(function(input, gp)
	if gp or not isFloating then return end
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
		orbitDirection = 1
	elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
		orbitDirection = -1
	end
end)

UIS.InputEnded:Connect(function(input, gp)
    if gp or not isFloating then return end
    if (input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left) and orbitDirection == 1 then
        orbitDirection = 0
    elseif (input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right) and orbitDirection == -1 then
        orbitDirection = 0
    end
end)

-- Limpieza (Sin cambios)
if LocalPlayer.Character then
    LocalPlayer.Character:WaitForChild("Humanoid").Died:Connect(cleanupFloat)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    cleanupFloat() 
    char:WaitForChild("Humanoid").Died:Connect(cleanupFloat)
    if isFloating then
        task.spawn(startFloat) 
    end
end)
LocalPlayer.CharacterRemoving:Connect(cleanupFloat)
