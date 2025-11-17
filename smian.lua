-- ====================================================================
-- // 3. SILENT AIM INTEGRATION (REPLACEMENT FOR AIMBOT)
-- ====================================================================

-- Silent Aim Configuration Setup
getgenv().silentAim = {
	Enabled = false,        -- Toggles the silent aim logic on/off
	WallCheck = true,      -- If true, only targets visible targets
	HitPart = "Head",      -- Target body part ("Head" or "HumanoidRootPart")
	Prediction = true,     -- Toggles movement prediction
	Fov = {
		Visible = false,   -- Toggles the FOV circle visualization
		Radius = 300,      -- Radius of the FOV circle (pixels)
        Color = Color3.fromRGB(255, 255, 255), -- Color of the FOV circle
        Thickness = 1,     -- Thickness of the FOV circle
	},
    -- Keybind = "RightShift" has been removed.
};

-- Silent Aim Core Logic (FIXED VARARG ISSUE)
do
    local localPlayer = Players.LocalPlayer;
    local replicatedStorage = game:GetService("ReplicatedStorage");
    local aiZones = workspace:WaitForChild("AiZones", 5);
    local success, bullet = pcall(require, replicatedStorage.Modules.FPS.Bullet);

    if not hookfunction or not Drawing then
        warn("Silent Aim: Missing hookfunction or Drawing. Silent Aim disabled.")
    elseif not success then
        warn("Silent Aim: Could not require Bullet Module. Silent Aim disabled.")
    else
        
        local drawings = { };
        local FOVCircle = nil;

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

        -- Changed isVisible to take an explicit ignoreList table
        local function isVisible(origin, target, ignoreList)
            local ignore = { Camera };
            if isAlive(localPlayer) then 
                ignore[#ignore + 1] = localPlayer.Character;
            end;
            
            -- Add contents of ignoreList to the main ignore table
            if ignoreList then
                for _, obj in ipairs(ignoreList) do
                    ignore[#ignore + 1] = obj;
                end
            end

            local hit = workspace:FindPartOnRayWithIgnoreList(Ray.new(origin, target.Position - origin), ignore, false, true);
            if hit and hit:IsDescendantOf(target.Parent) then 
                return true;
            end;
            return false;
        end;

        local function getAi()
            local ai = { };
            if not aiZones then return ai end
            for _,v in aiZones:GetChildren() do
                for _, character in v:GetChildren() do
                    ai[#ai + 1] = character;
                end;
            end;
            return ai;
        end;

        -- Changed getTarget to take an explicit ignoreList table
        local function getTarget(ignoreList)
            local SA_CFG = getgenv().silentAim;
            local cloestTarget, closestDistance = nil, SA_CFG.Fov.Radius;
            local mouseLoc = UserInputService:GetMouseLocation()

            local function checkTarget(character)
                local hitPart = character:FindFirstChild(SA_CFG.HitPart);
                if not hitPart then return end
                
                -- Pass ignoreList to isVisible
                if SA_CFG.WallCheck and not isVisible(Camera.CFrame.Position, hitPart, ignoreList) then return end
                
                local screenPosition, onScreen = Camera:WorldToViewportPoint(hitPart.Position);
                if not onScreen then return end

                local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mouseLoc).Magnitude;
                if distance < closestDistance then
                    closestDistance = distance;
                    cloestTarget = hitPart;
                end
            end

            for _, character in getAi() do 
                checkTarget(character)
            end

            for _, player in Players:GetPlayers() do
                if player ~= localPlayer and isAlive(player) then
                    checkTarget(player.Character)
                end
            end

            return cloestTarget;
        end;

        -- ... (Quadratic/Prediction functions remain the same) ...
        local function solveQuadratic(A, B, C)
            local discriminant = B^2 - 4*A*C;
            if discriminant < 0 then return nil, nil end;
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
                if root1 > 0 and root1 < root2 then return math.sqrt(root1)
                elseif root2 > 0 and root2 < root1 then return math.sqrt(root2)
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
        
        -- Hooks
        local oldBullet; 
        oldBullet = hookfunction(bullet.CreateBullet, function(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern)
            local SA_CFG = getgenv().silentAim;
            
            if not SA_CFG.Enabled then
                return oldBullet(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern);
            end
            
            -- Create the ignore list from the arguments that were passed as varargs previously
            local ignoreList = {model, model2, model3, aimPart}

            local target = getTarget(ignoreList); -- Pass the explicit ignore list
            if target then
                local bulletCfg = replicatedStorage.AmmoTypes:FindFirstChild(ammoType);
                local acceleration = bulletCfg:GetAttribute("ProjectileDrop");
                local projectileSpeed = bulletCfg:GetAttribute("MuzzleVelocity");

                bulletCfg:SetAttribute("Drag", 0); -- Remove drag

                local targetPosition = (SA_CFG.Prediction and predict(target, aimPart.Position, projectileSpeed, acceleration)) 
                                    or (not SA_CFG.Prediction and target.Position);
                
                local vertical = projectileDrop(aimPart.Position, targetPosition, projectileSpeed, acceleration);
                local new = { 
                    ["CFrame"] = CFrame.new(aimPart.Position, targetPosition + vertical)
                };

                return oldBullet(idk, model, model2, model3, new, idk2, ammoType, tick, recoilPattern);
            end;

            return oldBullet(idk, model, model2, model3, aimPart, idk2, ammoType, tick, recoilPattern);
        end);
        
        -- FOV Circle Initialization and Loop
        FOVCircle = draw("Circle", {
            Visible = false, 
            Filled = false, 
            NumSides = 1000, 
            Color = getgenv().silentAim.Fov.Color, 
            Thickness = getgenv().silentAim.Fov.Thickness, 
            Transparency = 1,
            ZIndex = 100
        });

        RunService.Heartbeat:Connect(function()
            local SA_CFG = getgenv().silentAim;
            local FOV_CFG = SA_CFG.Fov;

            FOVCircle.Visible = SA_CFG.Enabled and FOV_CFG.Visible;
            if FOVCircle.Visible then
                FOVCircle.Position = UserInputService:GetMouseLocation();
                FOVCircle.Radius = FOV_CFG.Radius;
                FOVCircle.Color = FOV_CFG.Color;
                FOVCircle.Thickness = FOV_CFG.Thickness;
            end
        end);

        -- The following UserInputService.InputBegan block was removed:
        --[[
        UserInputService.InputBegan:Connect(function(Input)
            local SA_CFG = getgenv().silentAim;
            local key = Enum.KeyCode[SA_CFG.Keybind] or Enum.KeyCode.RightShift;

            if Input.KeyCode == key then
                SA_CFG.Fov.Visible = not SA_CFG.Fov.Visible;
            end;
        end);
        --]]
    end
end
