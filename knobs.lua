local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local DESIRED_SPEED = 20
local PATH_AGENT = {
    AgentRadius = 2.5,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentCanClimb = true,
    WaypointSpacing = 2,
}

local connectionHeartbeat

local function cleanup()
    if connectionHeartbeat then
        connectionHeartbeat:Disconnect()
        connectionHeartbeat = nil
    end
end

local function attachToCharacter(character)
    if not character then return end
    local humanoid = character:WaitForChild("Humanoid", 5)
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoid or not hrp then return end

    humanoid.WalkSpeed = DESIRED_SPEED

    local promptCooldowns = {}
    local lastPosition = hrp.Position
    local stuckTime = 0
    local STUCK_DISTANCE = 1
    local STUCK_THRESHOLD = 3

    cleanup()

    connectionHeartbeat = RunService.Heartbeat:Connect(function(deltaTime)
        if humanoid.Health <= 0 or player:GetAttribute("IsAlive") == false then
            cleanup()
            -- Fire PlayAgain if the player died
            pcall(function()
                ReplicatedStorage.RemotesFolder.PlayAgain:FireServer()
            end)
            return
        end

        -- Example movement logic
        if humanoid.WalkSpeed ~= DESIRED_SPEED then humanoid.WalkSpeed = DESIRED_SPEED end
        if (hrp.Position - lastPosition).Magnitude < STUCK_DISTANCE then
            stuckTime = stuckTime + deltaTime
            if stuckTime >= STUCK_THRESHOLD then
                hrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)
                stuckTime = 0
            end
        else
            lastPosition = hrp.Position
            stuckTime = 0
        end
    end)

    humanoid.Died:Connect(function()
        player:SetAttribute("IsAlive", false)
        cleanup()
        -- Fire PlayAgain when humanoid dies
        pcall(function()
            ReplicatedStorage.RemotesFolder.PlayAgain:FireServer()
        end)
    end)
end

player.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    player:SetAttribute("IsAlive", true)
    attachToCharacter(char)
end)

if player.Character then
    attachToCharacter(player.Character)
end
