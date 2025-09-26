local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local DESIRED_SPEED = 20
local STUCK_DISTANCE = 1
local STUCK_THRESHOLD = 3
local PATH_AGENT = {
    AgentRadius = 2.5,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentCanClimb = true,
    WaypointSpacing = 2,
}

local connectionHeartbeat = nil
local charAddedConn = nil
local notify = function(txt, t)
    if getgenv and getgenv().Library and getgenv().Library.Notify then
        pcall(getgenv().Library.Notify, txt, t or 2)
    else
        print("[AutoKnob] "..txt)
    end
end

local function cleanupHeartbeat()
    if connectionHeartbeat then
        connectionHeartbeat:Disconnect()
        connectionHeartbeat = nil
    end
end

local function makePartsNonCollidable(root)
    if not root then return end
    local Objects = {
        DoorNormal = true, DoorFrame = true, Luggage_Cart_Crouch = true, Carpet = true,
        CarpetLight = true, Luggage_Cart = true, DropCeiling = true, End_DoorFrame = true,
        Start_DoorFrame = true, TriggerEventCollision = true, StairCollision = true,
        DoorLattice = true
    }
    for _, v in pairs(root:GetDescendants()) do
        if Objects[v.Name] then
            if v:IsA("BasePart") then
                v.CanCollide = false
                v.CanQuery = true
            elseif v:IsA("Model") then
                for _, c in pairs(v:GetChildren()) do
                    if c:IsA("BasePart") then
                        c.CanCollide = false
                        c.CanQuery = true
                    end
                end
            end
        end
        if v.Name == "LiveObstructionNew" or v.Name == "LiveObstructionNewIntro" then
            local col = v:FindFirstChild("Collision")
            if col and col:IsA("BasePart") then
                col.CanCollide = false
                col.CanQuery = true
            end
        end
        if v.Name == "SeeThroughGlass" then
            if v:IsA("BasePart") then
                v.CanCollide = false
                v.CanQuery = true
            else
                for _, c in pairs(v:GetChildren()) do
                    if c:IsA("BasePart") then
                        c.CanCollide = false
                        c.CanQuery = true
                    end
                end
            end
        end
        if v.Name == "Collision" and v.Parent and v.Parent.Name == "Parts" and v:IsA("BasePart") then
            v.CanCollide = false
        end
    end
end

local function moveTo(humanoid, hrp, target)
    if not humanoid or not hrp or not target then return end
    local targetPos
    if typeof(target) == "Instance" and target:IsA("BasePart") then
        targetPos = target.Position + target.CFrame.LookVector * -2
    elseif typeof(target) == "CFrame" then
        targetPos = target.Position
    elseif typeof(target) == "Vector3" then
        targetPos = target
    else
        return
    end

    local path = PathfindingService:CreatePath(PATH_AGENT)
    local ok = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        humanoid:MoveTo(targetPos)
        return
    end
    for _, wp in ipairs(path:GetWaypoints()) do
        if humanoid.Health <= 0 then break end
        humanoid:MoveTo(wp.Position)
        humanoid.MoveToFinished:Wait()
        if wp.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
    end
end

local function handlePrompts(model, hrp, promptCooldowns)
    if not model then return end
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local id = tostring(desc)
            local now = tick()
            if promptCooldowns[id] and (now - promptCooldowns[id]) < 1 then
                -- cooldown
            else
                local parent = desc.Parent
                if parent and parent:IsA("BasePart") then
                    local dist = (hrp.Position - parent.Position).Magnitude
                    if dist <= desc.MaxActivationDistance then
                        local oldHold = desc.HoldDuration
                        desc.HoldDuration = 0
                        pcall(function() desc:Trigger() end)
                        promptCooldowns[id] = now
                        task.delay(0.1, function()
                            if desc and desc.Parent then desc.HoldDuration = oldHold end
                        end)
                    end
                end
            end
        end
    end
end

local function attemptUnstuck(player, humanoid, hrp, latestRoomValue)
    notify("Attempting unstuck...", 2)
    task.spawn(function()
        if workspace.CurrentRooms and workspace.CurrentRooms:FindFirstChild(tostring(latestRoomValue)) then
            local room = workspace.CurrentRooms[tostring(latestRoomValue)]
            local door = room:FindFirstChild("Door") and room.Door:FindFirstChild("Door")
            if door then
                moveTo(humanoid, hrp, door)
                task.wait(0.5)
                pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 2, 0) end)
            end
        else
            pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0) end)
        end
    end)
end

local function attachToCharacter(character)
    if not character then return end
    local humanoid = character:WaitForChild("Humanoid", 5)
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoid or not hrp then return end

    local GameData = ReplicatedStorage:FindFirstChild("GameData")
    if not GameData then
        notify("GameData missing - AutoKnob disabled", 2)
        return
    end
    local floor = GameData:FindFirstChild("Floor")
    local latestRoom = GameData:FindFirstChild("LatestRoom")
    if not floor or floor.Value ~= "Hotel" then
        notify("Not on Hotel floor - AutoKnob inactive", 2)
        return
    end

    if workspace:FindFirstChild("CurrentRooms") then
        makePartsNonCollidable(workspace.CurrentRooms)
    end

    humanoid.WalkSpeed = DESIRED_SPEED
    local promptCooldowns = {}
    local lastPosition = hrp.Position
    local stuckTime = 0

    cleanupHeartbeat()
    connectionHeartbeat = RunService.Heartbeat:Connect(function(deltaTime)
        if humanoid.Health <= 0 then return end
        if humanoid.WalkSpeed ~= DESIRED_SPEED then humanoid.WalkSpeed = DESIRED_SPEED end

        -- stuck detection
        if latestRoom and typeof(latestRoom.Value) == "number" and latestRoom.Value >= 5 then
            if (hrp.Position - lastPosition).Magnitude < STUCK_DISTANCE then
                stuckTime = stuckTime + deltaTime
                if stuckTime >= STUCK_THRESHOLD then
                    attemptUnstuck(player, humanoid, hrp, latestRoom.Value)
                    stuckTime = 0
                end
            else
                stuckTime = 0
                lastPosition = hrp.Position
            end
        end

        -- main room handling
        if workspace.CurrentRooms and workspace.CurrentRooms:FindFirstChild(tostring(latestRoom.Value)) then
            local room = workspace.CurrentRooms[tostring(latestRoom.Value)]
            if room then
                local key = room:FindFirstChild("KeyObtain", true)
                local lever = room:FindFirstChild("LeverForGate", true)
                local liveHint = room:FindFirstChild("LiveHintBook", true)
                local libHint = room:FindFirstChild("LibraryHintPaper", true)
                local doorPart = room:FindFirstChild("Door") and room.Door:FindFirstChild("Door")

                if doorPart and doorPart:IsA("BasePart") and doorPart.CanCollide then
                    doorPart.CanCollide = false
                end

                if room:FindFirstChild("Door") then handlePrompts(room.Door, hrp, promptCooldowns) end

                if key and not character:FindFirstChild("Key") then
                    if key.PrimaryPart then moveTo(humanoid, hrp, key.PrimaryPart) end
                elseif doorPart then
                    moveTo(humanoid, hrp, doorPart)
                end

                if lever then
                    local pc = lever:FindFirstChildOfClass("PrismaticConstraint")
                    if pc and pc.TargetPosition == 1 and lever.PrimaryPart then
                        moveTo(humanoid, hrp, lever.PrimaryPart)
                    end
                end

                if latestRoom.Value == 50 then
                    if liveHint and liveHint.PrimaryPart then
                        moveTo(humanoid, hrp, liveHint.PrimaryPart)
                    else
                        if not character:FindFirstChild("LibraryHintPaper") and not character:FindFirstChild("LibraryHintPaperHard") then
                            if libHint and libHint.PrimaryPart then moveTo(humanoid, hrp, libHint.PrimaryPart) end
                        end
                    end
                end
            end
        end
    end)

    humanoid.Died:Connect(function()
        cleanupHeartbeat()
    end)
end

local function startListening()
    if charAddedConn then charAddedConn:Disconnect() charAddedConn = nil end

    charAddedConn = player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        attachToCharacter(char)
    end)

    if player.Character then
        task.spawn(function()
            task.wait(0.5)
            attachToCharacter(player.Character)
        end)
    end
end

startListening()
notify("AutoKnob enabled", 3)
