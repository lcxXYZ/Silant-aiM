-- // Project Delta Silent Aim. (This Will Make Your Bullets Faster As I Remove Drag From The Bulltes.)
-- // Services
local runService = game:GetService("RunService");
local userInputService = game:GetService("UserInputService");
local httpService = game:GetService("HttpService");
local replicatedStorage = game:GetService("ReplicatedStorage");
local players = game:GetService("Players");

-- // Variables
local localPlayer = players.LocalPlayer;
local camera = workspace.CurrentCamera;
local aiZones = workspace.AiZones;
local success, bullet = pcall(require, replicatedStorage.Modules.FPS.Bullet);

if not hookfunction then 
	return localPlayer:Kick("Executor Dosen't Have hookfunction.");
end;

if not Drawing then 
	return localPlayer:Kick("Executor Dosen't Have Drawing.");
end;

if not success then 
	return localPlayer:Kick("Could't Require Bullet Module. Make Sure The Game Is Loaded");
end;

-- ====================================================================
-- // GETENV CONFIGURATION
-- All settings are now controlled via getgenv().silentAim
-- ====================================================================
getgenv().silentAim = {
	Enabled = true,        -- Toggles the silent aim logic on/off
	WallCheck = true,      -- If true, only targets visible targets
	HitPart = "Head",      -- Target body part ("Head" or "HumanoidRootPart")
	Prediction = true,     -- Toggles movement prediction
	Fov = {
		Visible = false,   -- Toggles the FOV circle visualization
		Radius = 600,      -- Radius of the FOV circle (pixels)
        Color = Color3.fromRGB(255, 255, 255), -- Color of the FOV circle
        Thickness = 1,     -- Thickness of the FOV circle
	},
	Keybind = "RightShift" -- Key to toggle the FOV circle visibility (if Visible is true)
};

-- // DRAWINGS (Only used for the FOV Circle)
local drawings = { };
local FOVCircle = nil;

-- // Functions
local function draw(drawingType, properties)
	local drawing = Drawing.new(drawingType);
	drawings[#drawings + 1] = drawing;
	for index, value in properties do 
		drawing[index] = value;
	end;
	return drawing;
end;

local function isAlive(player)
	if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then 
		return true;
	end;
	return false;
end;

local function isVisible(origin, target, ...)
	local ignore = { camera, ... };

	if isAlive(localPlayer) then 
		ignore[#ignore + 1] = localPlayer.Character;
	end;

	local hit = workspace:FindPartOnRayWithIgnoreList(Ray.new(origin, target.Position - origin), ignore, false, true);
	if hit and hit:IsDescendantOf(target.Parent) then 
		return true;
	end;
	return false;
end;

local function getAi()
	local ai = { };

	for _,v in aiZones:GetChildren() do
		for _, character in v:GetChildren() do
			ai[#ai + 1] = character;
		end;
	end;

	return ai;
end;

local function getTarget(...)
    -- Read configuration directly from getgenv()
    local SA_CFG = getgenv().silentAim;
	local cloestTarget, closestDistance = nil, SA_CFG.Fov.Radius;

	for _, character in getAi() do 
		if not character:FindFirstChild("HumanoidRootPart") then
			continue;
		end;

		local hitPart = character:FindFirstChild(SA_CFG.HitPart);
		if not hitPart then 
			continue;
		end;
		
		if SA_CFG.WallCheck and not isVisible(camera.CFrame.Position, hitPart, ...) then 
			continue;
		end;
		
		local screenPosition, onScreen = camera:WorldToViewportPoint(hitPart.Position);
		if not onScreen then 
			continue;
		end;

		local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - userInputService:GetMouseLocation()).Magnitude;
		if distance < closestDistance then
			closestDistance = distance;
			cloestTarget = hitPart;
		end;
	end;

	for index, player in players:GetPlayers() do
		if index == 1 then 
			continue;
		end;
		
		if not isAlive(player) then 
			continue;
		end;
		
		local hitPart = player.Character:FindFirstChild(SA_CFG.HitPart);
		if not hitPart then 
			continue;
		end;
		
		if SA_CFG.WallCheck and not isVisible(camera.CFrame.Position, hitPart, ...) then 
			continue;
		end;
		
		local screenPosition, onScreen = camera:WorldToViewportPoint(hitPart.Position);
		if not onScreen then 
			continue;
		end;

		local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - userInputService:GetMouseLocation()).Magnitude;
		if distance < closestDistance then
			closestDistance = distance;
			cloestTarget = hitPart;
		end;
	end;

	return cloestTarget;
end;

local function solveQuadratic(A, B, C)
    local discriminant = B^2 - 4*A*C;
    if discriminant < 0 then
        return nil, nil;
    end;

    local discRoot = math.sqrt(discriminant);
    local root1 = (-B - discRoot) / (2*A);
    local root2 = (-B + discRoot) / (2*A);

    return root1, root2;
end;

local function getBallisticFlightTime(direction, gravity, projectileSpeed)
    local root1, root2 = solveQuadratic(
        gravity:Dot(gravity) / 4,
        gravity:Dot(direction) - projectileSpeed^2,
        direction:Dot(direction)
    );

    if root1 and root2 then
        if root1 > 0 and root1 < root2 then
            return math.sqrt(root1);
        elseif root2 > 0 and root2 < root1 then
            return math.sqrt(root2);
        end;
    end;

    return 0;
end;

local function projectileDrop(origin, target, projectileSpeed, acceleration)
	local gravity = Vector3.new() + Vector3.yAxis * (acceleration * 2);
	local time = getBallisticFlightTime(target - origin, gravity, projectileSpeed);

	return 0.5 * gravity * time^2;
end;

local function predict(target, origin, projectileSpeed, acceleration)
	local gravity = Vector3.new() + Vector3.yAxis * (acceleration * 2);
	local time = getBallisticFlightTime(target.Position - origin, gravity, projectileSpeed);

	return target.Position + (target.Velocity * time);
end;

-- // Hooks
local oldBullet; 
oldBullet = hookfunction(bullet.CreateBullet, function(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern)
    -- Read configuration directly from getgenv()
    local SA_CFG = getgenv().silentAim;
    
    if not SA_CFG.Enabled then
        return oldBullet(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern);
    end

	local target = getTarget(model, model2, model3, aimPart);
	if target then
		local bullet = replicatedStorage.AmmoTypes:FindFirstChild(ammoType);
		local acceleration = bullet:GetAttribute("ProjectileDrop");
		local projectileSpeed = bullet:GetAttribute("MuzzleVelocity");

		bullet:SetAttribute("Drag", 0); -- Remove drag for simpler time calculation

        local targetPosition = (SA_CFG.Prediction and predict(target, aimPart.Position, projectileSpeed, acceleration)) 
                             or (not SA_CFG.Prediction and target.Position);
        
		local vertical = projectileDrop(aimPart.Position, targetPosition, projectileSpeed, acceleration);
		local new = { 
			["CFrame"] = CFrame.new(aimPart.Position, targetPosition + vertical) -- They Only Check The CFrame For This Arg.
		};

		return oldBullet(idk, model, model2, model3, new, idk2, ammoType, tick, recoilPattern); -- Replace the aimPart With A Table Contaning CFrame So We Don't Modify The AimPart.
	end;

	return oldBullet(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern);
end);

-- ====================================================================
-- // FOV CIRCLE VISUALS AND TOGGLE
-- ====================================================================

-- Initialize FOV Circle
FOVCircle = draw("Circle", {
    Visible = false, 
    Filled = false, 
    NumSides = 1000, 
    Color = getgenv().silentAim.Fov.Color, 
    Thickness = getgenv().silentAim.Fov.Thickness, 
    Transparency = 1,
    ZIndex = 100 -- High ZIndex to ensure visibility
});

-- FOV Circle Update Loop
runService.Heartbeat:Connect(function()
    local SA_CFG = getgenv().silentAim;
    local FOV_CFG = SA_CFG.Fov;

    FOVCircle.Visible = SA_CFG.Enabled and FOV_CFG.Visible;
    if FOVCircle.Visible then
        FOVCircle.Position = userInputService:GetMouseLocation();
        FOVCircle.Radius = FOV_CFG.Radius;
        FOVCircle.Color = FOV_CFG.Color;
        FOVCircle.Thickness = FOV_CFG.Thickness;
    end
end);

-- Keybind to toggle FOV Circle visibility
userInputService.InputBegan:Connect(function(Input)
    local SA_CFG = getgenv().silentAim;
    local key = Enum.KeyCode[SA_CFG.Keybind] or Enum.KeyCode.RightShift;

    if Input.KeyCode == key then
        SA_CFG.Fov.Visible = not SA_CFG.Fov.Visible;
    end;
end);

warn("Project Delta Silent Aim Loaded")
