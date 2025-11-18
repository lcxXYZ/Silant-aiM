-- // Project Delta Silent Aim
-- // Services
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- // Variables
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local AiZones = workspace:FindFirstChild("AiZones")
local success, Bullet = pcall(require, ReplicatedStorage.Modules.FPS.Bullet)

if not hookfunction then
    return LocalPlayer:Kick("Executor doesn't have hookfunction.")
end

if not Drawing then
    return LocalPlayer:Kick("Executor doesn't have Drawing.")
end

if not success then
    return LocalPlayer:Kick("Couldn't require Bullet module. Make sure the game is loaded.")
end

-- ====================================================================
-- // GETENV CONFIGURATION
-- ====================================================================
getgenv().silentAim = {
    Enabled = true,
    WallCheck = true,
    HitPart = 'Head',
    Prediction = true,
    Fov = {
        Visible = false,
        Radius = 600,
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 1,
    },
    Keybind = 'RightShift',
    TargetInfo = {
        Enabled = true,
        Position = Vector2.new(20, 100),
        TextSize = 14,
        Font = 2,
        Color = Color3.fromRGB(255, 255, 255),
    },
}

-- // DRAWINGS
local DrawingsList = {}
local FOVCircle = nil
local TargetInfoDrawings = {}

local function draw(Type, Properties)
    local D = Drawing.new(Type)
    table.insert(DrawingsList, D)
    for i, v in pairs(Properties) do
        D[i] = v
    end
    return D
end

local function isAlive(Player)
    return Player and Player.Character and Player.Character:FindFirstChild('HumanoidRootPart') and Player.Character:FindFirstChild('Humanoid') and Player.Character.Humanoid.Health > 0
end

local function isVisible(Origin, Target, ...)
    local ignore = {Camera, ...}
    if isAlive(LocalPlayer) then
        table.insert(ignore, LocalPlayer.Character)
    end

    local hit = workspace:FindPartOnRayWithIgnoreList(
        Ray.new(Origin, Target.Position - Origin),
        ignore,
        false,
        true
    )
    if hit and hit:IsDescendantOf(Target.Parent) then
        return true
    end
    return false
end

local function getAi()
    local ai = {}
    if not AiZones then return ai end
    for _, zone in pairs(AiZones:GetChildren()) do
        for _, character in pairs(zone:GetChildren()) do
            table.insert(ai, character)
        end
    end
    return ai
end

local function getTarget(...)
    local SA_CFG = getgenv().silentAim
    local closestTarget, closestDistance = nil, SA_CFG.Fov.Radius
    local ignoreArgs = {...} -- capture varargs to avoid upvalue issues

    local function checkTarget(Character, IsPlayer)
        if not Character:FindFirstChild('HumanoidRootPart') then return end
        local HitPart = Character:FindFirstChild(SA_CFG.HitPart)
        if not HitPart then return end

        if SA_CFG.WallCheck and not isVisible(Camera.CFrame.Position, HitPart, table.unpack(ignoreArgs)) then
            return
        end

        local screenPos, onScreen = Camera:WorldToViewportPoint(HitPart.Position)
        if not onScreen then return end

        local distance = (Vector2.new(screenPos.X, screenPos.Y) - UserInputService:GetMouseLocation()).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestTarget = {
                HitPart = HitPart,
                Character = Character,
                IsPlayer = IsPlayer,
                Distance = math.floor(distance)
            }
        end
    end

    for _, character in pairs(getAi()) do
        checkTarget(character, false)
    end

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not isAlive(player) then continue end
        checkTarget(player.Character, true)
    end

    return closestTarget
end

local function solveQuadratic(A, B, C)
    local disc = B^2 - 4*A*C
    if disc < 0 then return nil, nil end
    local sqrtDisc = math.sqrt(disc)
    local r1 = (-B - sqrtDisc) / (2*A)
    local r2 = (-B + sqrtDisc) / (2*A)
    return r1, r2
end

local function getBallisticFlightTime(Direction, Gravity, Speed)
    local r1, r2 = solveQuadratic(Gravity:Dot(Gravity)/4, Gravity:Dot(Direction) - Speed^2, Direction:Dot(Direction))
    if r1 and r2 then
        if r1 > 0 and r1 < r2 then return math.sqrt(r1) end
        if r2 > 0 and r2 < r1 then return math.sqrt(r2) end
    end
    return 0
end

local function projectileDrop(Origin, Target, Speed, Acceleration)
    local Gravity = Vector3.new(0, Acceleration * 2, 0)
    local time = getBallisticFlightTime(Target - Origin, Gravity, Speed)
    return 0.5 * Gravity * time^2
end

local function predict(Target, Origin, Speed, Acceleration)
    local Gravity = Vector3.new(0, Acceleration * 2, 0)
    local time = getBallisticFlightTime(Target.Position - Origin, Gravity, Speed)
    return Target.Position + (Target.Velocity * time)
end

-- // HOOK
local oldBullet
oldBullet = hookfunction(Bullet.CreateBullet, function(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern)
    local SA_CFG = getgenv().silentAim
    if not SA_CFG.Enabled then return oldBullet(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern) end

    local targetStruct = getTarget(model, model2, model3, aimPart)
    if targetStruct then
        local target = targetStruct.HitPart
        local bulletObj = ReplicatedStorage.AmmoTypes:FindFirstChild(ammoType)
        local acceleration = bulletObj:GetAttribute('ProjectileDrop')
        local projectileSpeed = bulletObj:GetAttribute('MuzzleVelocity')
        bulletObj:SetAttribute('Drag', 0)

        local targetPosition = SA_CFG.Prediction and predict(target, aimPart.Position, projectileSpeed, acceleration) or target.Position
        local vertical = projectileDrop(aimPart.Position, targetPosition, projectileSpeed, acceleration)
        local newAim = {['CFrame'] = CFrame.new(aimPart.Position, targetPosition + vertical)}

        return oldBullet(idk, model, model2, model3, newAim, idk2, ammoType, tick, recoilPattern)
    end

    return oldBullet(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern)
end)

-- // TARGET INFO DRAWINGS
local function createInfoLine(yOffset)
    local TI_CFG = getgenv().silentAim.TargetInfo
    local line = draw('Text', {
        Visible = false,
        Text = '',
        Color = TI_CFG.Color,
        Font = TI_CFG.Font,
        Size = TI_CFG.TextSize,
        Outline = true,
        Position = TI_CFG.Position + Vector2.new(0, yOffset),
        ZIndex = 101,
    })
    return line
end

TargetInfoDrawings.Title = createInfoLine(0)
TargetInfoDrawings.Name = createInfoLine(15)
TargetInfoDrawings.Health = createInfoLine(30)
TargetInfoDrawings.Visible = createInfoLine(45)
TargetInfoDrawings.Distance = createInfoLine(60)
TargetInfoDrawings.Title.Text = "Target Info"

local function setTargetInfoVisibility(Visible)
    for _, D in pairs(TargetInfoDrawings) do
        D.Visible = Visible
    end
end

-- // FOV Circle
FOVCircle = draw('Circle', {
    Visible = false,
    Filled = false,
    NumSides = 1000,
    Color = getgenv().silentAim.Fov.Color,
    Thickness = getgenv().silentAim.Fov.Thickness,
    Transparency = 1,
    ZIndex = 100,
})

-- // UPDATE LOOP
RunService.Heartbeat:Connect(function()
    local SA_CFG = getgenv().silentAim
    local FOV_CFG = SA_CFG.Fov
    local TI_CFG = SA_CFG.TargetInfo

    FOVCircle.Visible = SA_CFG.Enabled and FOV_CFG.Visible
    if FOV_CFG.Visible then
        FOVCircle.Position = UserInputService:GetMouseLocation()
        FOVCircle.Radius = FOV_CFG.Radius
        FOVCircle.Color = FOV_CFG.Color
        FOVCircle.Thickness = FOV_CFG.Thickness
    end

    local targetStruct = getTarget()
    local targetFound = SA_CFG.Enabled and TI_CFG.Enabled and (targetStruct ~= nil)
    setTargetInfoVisibility(targetFound)

    if targetFound then
        local targetChar = targetStruct.Character
        local targetHum = targetChar:FindFirstChildOfClass('Humanoid')
        local name = targetChar.Name
        if targetStruct.IsPlayer then
            local playerObj = Players:FindFirstChild(targetChar.Name)
            if playerObj then name = playerObj.DisplayName or playerObj.Name end
        end
        local visible = isVisible(Camera.CFrame.Position, targetStruct.HitPart)

        TargetInfoDrawings.Name.Text = 'Name: ' .. name
        TargetInfoDrawings.Health.Text = 'Health: ' .. (targetHum and math.floor(targetHum.Health) or 'N/A') .. ' HP'
        TargetInfoDrawings.Visible.Text = 'Visible: ' .. tostring(visible)
        TargetInfoDrawings.Distance.Text = 'Distance: ' .. targetStruct.Distance .. ' M'
    end
end)

-- // FOV TOGGLE
UserInputService.InputBegan:Connect(function(Input)
    local SA_CFG = getgenv().silentAim
    local key = Enum.KeyCode[SA_CFG.Keybind] or Enum.KeyCode.RightShift
    if Input.KeyCode == key then
        SA_CFG.Fov.Visible = not SA_CFG.Fov.Visible
    end
end)

warn("Project Delta Silent Aim Loaded")
