-- FlyIdleSwim.client.lua
-- Personaje suspendido, sin control de movimiento, anim de nado horizontal SIEMPRE.
-- Cámara scriptable que sigue al personaje con offset (por defecto, vista FRONTAL para ver la cara).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ================== CONFIG ==================
local START_UP_OFFSET   = 3             -- elevar al aparecer (studs)
local USE_SWIM_IDLE     = false         -- true=swimIdle, false=swim activa
local CAMERA_MODE       = "FRONT"       -- "FRONT" (ver la cara) o "BACK" (por detrás)
local CAM_OFFSET_FRONT  = Vector3.new(0, 2.5, 8)    -- cámara delante del HRP
local CAM_OFFSET_BACK   = Vector3.new(0, 2.5, -12)  -- cámara detrás del HRP
local CAM_STIFFNESS     = 1.0           -- 1: rígida (sin lerp). <1: algo de suavizado (0.2, p.ej.)

-- ================== STATE ==================
local hrp, humanoid, animator
local swimTrack, swimIdleTrack
local stepConn, camConn
local originalCameraType
local startPos
local initialYaw = 0

-- Utils
local function getSwimAnimations(character)
	local animate = character:FindFirstChild("Animate")
	if not animate then return nil, nil end
	local swim = animate:FindFirstChild("swim")
	local swimidle = animate:FindFirstChild("swimidle") or animate:FindFirstChild("swimIdle") or animate:FindFirstChild("swimIdle2")
	local swimAnim = swim and swim:FindFirstChildWhichIsA("Animation")
	local swimIdleAnim = swimidle and swimidle:FindFirstChildWhichIsA("Animation")
	return swimAnim, swimIdleAnim
end

local function stopTrack(t) if t then pcall(function() t:Stop(0.15) end) end end
local function cleanup()
	if stepConn then stepConn:Disconnect() stepConn = nil end
	if camConn  then camConn:Disconnect()  camConn  = nil end

	stopTrack(swimTrack); stopTrack(swimIdleTrack)
	swimTrack, swimIdleTrack = nil, nil

	if humanoid then
		pcall(function() humanoid.AutoRotate = true end)
		pcall(function() humanoid.WalkSpeed = 16 end)
		pcall(function() humanoid.JumpPower = 50 end)
		pcall(function() humanoid.JumpHeight = 7.2 end)
		pcall(function() humanoid.PlatformStand = false end)
	end

	if hrp then
		pcall(function() hrp.Anchored = false end)
	end

	-- restaurar cámara
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = originalCameraType or Enum.CameraType.Custom
	end
end

local function startPose(character)
	cleanup()

	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	-- posición de inicio y orientación base
	startPos = hrp.Position + Vector3.new(0, START_UP_OFFSET, 0)
	local look = hrp.CFrame.LookVector
	initialYaw = math.atan2(look.X, look.Z)

	-- bloquear TODO movimiento del jugador
	humanoid.AutoRotate = false
	humanoid.WalkSpeed  = 0
	humanoid.JumpPower  = 0
	pcall(function() humanoid.JumpHeight = 0 end)
	humanoid.PlatformStand = true      -- inhabilita el control de físico del Humanoid
	hrp.Anchored = true                -- inmóvil (la animación sigue funcionando)

	-- forzar estado y cargar anim
	pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Swimming) end)
	local swimAnim, swimIdleAnim = getSwimAnimations(character)
	if swimAnim then
		swimTrack = animator:LoadAnimation(swimAnim)
		swimTrack.Priority = Enum.AnimationPriority.Movement
		swimTrack.Looped   = true
	end
	if swimIdleAnim then
		swimIdleTrack = animator:LoadAnimation(swimIdleAnim)
		swimIdleTrack.Priority = Enum.AnimationPriority.Movement
		swimIdleTrack.Looped   = true
	end
	if USE_SWIM_IDLE and swimIdleTrack then
		swimIdleTrack:Play(0.1)
	elseif swimTrack then
		swimTrack:Play(0.1)
	elseif swimIdleTrack then
		swimIdleTrack:Play(0.1)
	end

	-- fijar pose: horizontal (pitch -90°) mirando "al frente" (yaw fijo)
	local function desiredCF(pos)
		return CFrame.new(pos) * CFrame.Angles(0, initialYaw, 0) * CFrame.Angles(-math.pi/2, 0, 0)
	end

	-- step para mantener orientación y velocidad nulas
	stepConn = RunService.RenderStepped:Connect(function()
		if not (hrp and hrp.Parent and humanoid and humanoid.Health > 0) then
			cleanup(); return
		end

		-- mantener CFrame exacto y cancelar cualquier drift numérico
		hrp.CFrame = desiredCF(startPos)
		hrp.AssemblyLinearVelocity  = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		-- asegurar estado Swimming (por si algo lo cambia)
		if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
			pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Swimming) end)
		end
	end)

	-- cámara que SIGUE al personaje con offset
	local cam = workspace.CurrentCamera
	if cam then
		originalCameraType = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable

		camConn = RunService.RenderStepped:Connect(function(dt)
			if not (hrp and hrp.Parent) then return end

			local baseCF = CFrame.new(hrp.Position) * CFrame.Angles(0, initialYaw, 0)
			local localOffset = (CAMERA_MODE == "FRONT") and CAM_OFFSET_FRONT or CAM_OFFSET_BACK
			local target = CFrame.new((baseCF * CFrame.new(localOffset)).Position, hrp.Position)

			if CAM_STIFFNESS >= 1 then
				cam.CFrame = target
			else
				-- algo de suavizado opcional
				local alpha = math.clamp(CAM_STIFFNESS, 0, 0.999)
				cam.CFrame = cam.CFrame:Lerp(target, alpha)
			end
		end)
	end
end

-- Arranque y limpieza
LocalPlayer.CharacterAdded:Connect(startPose)
if LocalPlayer.Character then startPose(LocalPlayer.Character) end
LocalPlayer.CharacterRemoving:Connect(cleanup)
script.Destroying:Connect(cleanup)
