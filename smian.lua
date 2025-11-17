-- // Project Delta Silent Aim. (This Will Make Your Bullets Faster As I Remove Drag From The Bulltes.)
-- // Services
local runService = game:GetService('RunService')
local userInputService = game:GetService('UserInputService')
local httpService = game:GetService('HttpService')
local replicatedStorage = game:GetService('ReplicatedStorage')
local players = game:GetService('Players')

-- // Variables
local localPlayer = players.LocalPlayer
local camera = workspace.CurrentCamera
local aiZones = workspace.AiZones
local success, bullet = pcall(require, replicatedStorage.Modules.FPS.Bullet)

if not hookfunction then
    return localPlayer:Kick("Executor Dosen't Have hookfunction.")
end

if not Drawing then
    return localPlayer:Kick("Executor Dosen't Have Drawing.")
end

if not success then
    return localPlayer:Kick(
        "Could't Require Bullet Module. Make Sure The Game Is Loaded"
    )
end

-- ====================================================================
-- // GETENV CONFIGURATION
-- All settings are now controlled via getgenv().silentAim
-- ====================================================================
getgenv().silentAim = {
    Enabled = true, -- Toggles the silent aim logic on/off
    WallCheck = true, -- If true, only targets visible targets
    HitPart = 'Head', -- Target body part ("Head" or "HumanoidRootPart")
    Prediction = true, -- Toggles movement prediction
    Fov = {
        Visible = false, -- Toggles the FOV circle visualization
        Radius = 600, -- Radius of the FOV circle (pixels)
        Color = Color3.fromRGB(255, 255, 255), -- Color of the FOV circle
        Thickness = 1, -- Thickness of the FOV circle
    },
    Keybind = 'RightShift', -- Key to toggle the FOV circle visibility (if Visible is true)
    TargetInfo = {
        Enabled = true, -- Toggles the visibility of the target info panel
        Position = Vector2.new(20, 100), -- Screen position of the panel (X, Y)
        TextSize = 14, -- Font size for the text
        Font = 2, -- Font style (2 is Monospace)
        Color = Color3.fromRGB(255, 255, 255), -- White text
    },
}

-- // DRAWINGS (Only used for the FOV Circle)
local drawings = {}
local FOVCircle = nil

-- // Target Info Drawing Table
local TargetInfoDrawings = {}

-- // Functions
local function draw(drawingType, properties)
    local drawing = Drawing.new(drawingType)
    drawings[#drawings + 1] = drawing
    for index, value in properties do
        drawing[index] = value
    end
    return drawing
end

local function isAlive(player)
    if
        player
        and player.Character
        and player.Character:FindFirstChild('HumanoidRootPart')
        and player.Character:FindFirstChild('Humanoid')
        and player.Character.Humanoid.Health > 0
    then
        return true
    end
    return false
end

-- This function is a vararg function and correctly uses '...'
local function isVisible(origin, target, ...)
    local ignore = { camera, ... }

    if isAlive(localPlayer) then
        ignore[#ignore + 1] = localPlayer.Character
    end

    local hit = workspace:FindPartOnRayWithIgnoreList(
        Ray.new(origin, target.Position - origin),
        ignore,
        false,
        true
    )
    if hit and hit:IsDescendantOf(target.Parent) then
        return true
    end
    return false
end

local function getAi()
    local ai = {}

    if not aiZones then
        return ai
    end -- Added check for aiZones

    for _, v in aiZones:GetChildren() do
        for _, character in v:GetChildren() do
            ai[#ai + 1] = character
        end
    end

    return ai
end

local function getTarget(...)
    -- Read configuration directly from getgenv()
    local SA_CFG = getgenv().silentAim
    local cloestTarget, closestDistance = nil, SA_CFG.Fov.Radius

    -- FIX: Capture varargs into a table to bypass strict interpreter rules on nested function scope
    local ignoreArgs = { ... }

    local function checkTarget(character, isPlayer)
        if not character:FindFirstChild('HumanoidRootPart') then
            return
        end

        local hitPart = character:FindFirstChild(SA_CFG.HitPart)
        if not hitPart then
            return
        end

        -- Use table.unpack() to pass the captured arguments instead of relying on '...' scope
        if
            SA_CFG.WallCheck
            and not isVisible(
                camera.CFrame.Position,
                hitPart,
                table.unpack(ignoreArgs)
            )
        then
            return
        end

        local screenPosition, onScreen =
            camera:WorldToViewportPoint(hitPart.Position)
        if not onScreen then
            return
        end

        local distance = (
            Vector2.new(screenPosition.X, screenPosition.Y)
            - userInputService:GetMouseLocation()
        ).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            -- Store the HitPart and the full Character model/instance
            cloestTarget = {
                HitPart = hitPart,
                Character = character,
                IsPlayer = isPlayer,
                Distance = math.floor(distance),
            }
        end
    end

    for _, character in getAi() do
        checkTarget(character, false)
    end

    for index, player in players:GetPlayers() do
        if player == localPlayer then -- Check explicitly against localPlayer object
            continue
        end

        if not isAlive(player) then
            continue
        end

        checkTarget(player.Character, true)
    end

    return cloestTarget
end

local function solveQuadratic(A, B, C)
    local discriminant = B ^ 2 - 4 * A * C
    if discriminant < 0 then
        return nil, nil
    end

    local discRoot = math.sqrt(discriminant)
    local root1 = (-B - discRoot) / (2 * A)
    local root2 = (-B + discRoot) / (2 * A)

    return root1, root2
end

local function getBallisticFlightTime(direction, gravity, projectileSpeed)
    local root1, root2 = solveQuadratic(
        gravity:Dot(gravity) / 4,
        gravity:Dot(direction) - projectileSpeed ^ 2,
        direction:Dot(direction)
    )

    if root1 and root2 then
        if root1 > 0 and root1 < root2 then
            return math.sqrt(root1)
        elseif root2 > 0 and root2 < root1 then
            return math.sqrt(root2)
        end
    end

    return 0
end

local function projectileDrop(origin, target, projectileSpeed, acceleration)
    local gravity = Vector3.new() + Vector3.yAxis * (acceleration * 2)
    local time =
        getBallisticFlightTime(target - origin, gravity, projectileSpeed)

    return 0.5 * gravity * time ^ 2
end

local function predict(target, origin, projectileSpeed, acceleration)
    local gravity = Vector3.new() + Vector3.yAxis * (acceleration * 2)
    local time = getBallisticFlightTime(
        target.Position - origin,
        gravity,
        projectileSpeed
    )

    return target.Position + (target.Velocity * time)
end

-- // Hooks
local oldBullet
oldBullet = hookfunction(
    bullet.CreateBullet,
    function(
        idk,
        model,
        model2,
        model3,
        aimPart,
        idk2,
        ammoType,
        tick,
        recoilPattern
    )
        -- Read configuration directly from getgenv()
        local SA_CFG = getgenv().silentAim

        if not SA_CFG.Enabled then
            return oldBullet(
                idk,
                model,
                model2,
                model3,
                aimPart,
                idk2,
                ammoType,
                tick,
                recoilPattern
            )
        end

        local targetStruct = getTarget(model, model2, model3, aimPart)
        if targetStruct then
            local target = targetStruct.HitPart -- Use the HitPart for aiming
            local bullet = replicatedStorage.AmmoTypes:FindFirstChild(ammoType)
            local acceleration = bullet:GetAttribute('ProjectileDrop')
            local projectileSpeed = bullet:GetAttribute('MuzzleVelocity')

            bullet:SetAttribute('Drag', 0) -- Remove drag for simpler time calculation

            local targetPosition = (
                SA_CFG.Prediction
                and predict(
                    target,
                    aimPart.Position,
                    projectileSpeed,
                    acceleration
                )
            )
                or (not SA_CFG.Prediction and target.Position)

            local vertical = projectileDrop(
                aimPart.Position,
                targetPosition,
                projectileSpeed,
                acceleration
            )
            local new = {
                ['CFrame'] = CFrame.new(
                    aimPart.Position,
                    targetPosition + vertical
                ), -- They Only Check The CFrame For This Arg.
            }

            return oldBullet(
                idk,
                model,
                model2,
                model3,
                new,
                idk2,
                ammoType,
                tick,
                recoilPattern
            ) -- Replace the aimPart With A Table Contaning CFrame So We Don't Modify The AimPart.
        end

        return oldBullet(
            idk,
            model,
            model2,
            model3,
            aimPart,
            idk2,
            ammoType,
            tick,
            recoilPattern
        )
    end
)

-- ====================================================================
-- // TARGET INFO DISPLAY INITIALIZATION
-- ====================================================================

-- Helper function to create a text line with offset
local function createInfoLine(yOffset)
    local SA_CFG = getgenv().silentAim
    local TI_CFG = SA_CFG.TargetInfo
    local line = draw('Text', {
        Visible = false,
        Text = '',
        Color = TI_CFG.Color,
        Font = TI_CFG.Font,
        Size = TI_CFG.TextSize,
        Outline = true,
        Position = TI_CFG.Position + Vector2.new(0, yOffset),
        ZIndex = 101, -- Higher than FOV circle
    })
    return line
end

-- Initialize the Drawing objects for target info
TargetInfoDrawings.Title = createInfoLine(0)
TargetInfoDrawings.Name = createInfoLine(15)
TargetInfoDrawings.Health = createInfoLine(30)
TargetInfoDrawings.Visible = createInfoLine(45)
TargetInfoDrawings.Distance = createInfoLine(60)

TargetInfoDrawings.Title.Text = 'Target Info'

-- Function to set visibility of all info lines
local function setTargetInfoVisibility(visible)
    for _, drawing in pairs(TargetInfoDrawings) do
        drawing.Visible = visible
    end
end

-- ====================================================================
-- // FOV CIRCLE AND TARGET INFO UPDATE LOOP
-- ====================================================================

-- Initialize FOV Circle
FOVCircle = draw('Circle', {
    Visible = false,
    Filled = false,
    NumSides = 1000,
    Color = getgenv().silentAim.Fov.Color,
    Thickness = getgenv().silentAim.Fov.Thickness,
    Transparency = 1,
    ZIndex = 100, -- High ZIndex to ensure visibility
})

-- Update Loop
runService.Heartbeat:Connect(function()
    local SA_CFG = getgenv().silentAim
    local FOV_CFG = SA_CFG.Fov
    local TI_CFG = SA_CFG.TargetInfo

    FOVCircle.Visible = SA_CFG.Enabled and FOV_CFG.Visible
    if FOV_CFG.Visible then
        FOVCircle.Position = userInputService:GetMouseLocation()
        FOVCircle.Radius = FOV_CFG.Radius
        FOVCircle.Color = FOV_CFG.Color
        FOVCircle.Thickness = FOV_CFG.Thickness
    end

    -- TARGET INFO LOGIC
    local targetStruct = getTarget() -- Find the target without passing hook arguments
    -- FIX: Ensure targetFound is a strict boolean (true/false) by checking if targetStruct is non-nil.
    -- This prevents passing a table or nil to the drawing visibility setter.
    local targetFound = SA_CFG.Enabled
        and TI_CFG.Enabled
        and (targetStruct ~= nil)

    setTargetInfoVisibility(targetFound)

    if targetFound then
        local targetCharacter = targetStruct.Character
        local targetHumanoid = targetCharacter:FindFirstChildOfClass('Humanoid')
        -- Use the target's name property directly; GetNameFromUserIdAsync is slow and prone to errors
        local name = targetCharacter.Name
        if targetStruct.IsPlayer then
            local playerObject = players:FindFirstChild(targetCharacter.Name)
            if playerObject then
                name = playerObject.DisplayName or playerObject.Name
            end
        end

        -- Check visibility separately to display it accurately
        local isCurrentlyVisible =
            isVisible(camera.CFrame.Position, targetStruct.HitPart)

        -- Update Text Drawing properties
        TargetInfoDrawings.Name.Text = string.format('Name: %s', name)
        TargetInfoDrawings.Health.Text = string.format(
            'Health: %s HP',
            targetHumanoid and math.floor(targetHumanoid.Health) or 'N/A'
        )
        TargetInfoDrawings.Visible.Text =
            string.format('Visible: %s', tostring(isCurrentlyVisible))
        TargetInfoDrawings.Distance.Text =
            string.format('Distance: %s M', targetStruct.Distance)
    end
end)

-- ====================================================================
-- // FOV CIRCLE TOGGLE
-- ====================================================================

-- Keybind to toggle FOV Circle visibility
userInputService.InputBegan:Connect(function(Input)
    local SA_CFG = getgenv().silentAim
    local key = Enum.KeyCode[SA_CFG.Keybind] or Enum.KeyCode.RightShift

    if Input.KeyCode == key then
        SA_CFG.Fov.Visible = not SA_CFG.Fov.Visible
    end
end)

warn('Project Delta Silent Aim Loaded')
