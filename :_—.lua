-- AutoShoot GUI with small transparent drag bar (mouse + touch)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Destroy existing GUI (PlayerGui & CoreGui) to avoid duplicates
local function safeDestroyGui(name)
    if playerGui:FindFirstChild(name) then
        pcall(function() playerGui:FindFirstChild(name):Destroy() end)
    end
    if game.CoreGui:FindFirstChild(name) then
        pcall(function() game.CoreGui:FindFirstChild(name):Destroy() end)
    end
end
safeDestroyGui("AutoShootGUI")

-- Config / state
local autoShootEnabled = false
local conn = nil
local shootInterval = 0.01
local acc = 0
local lastShot = 0
local dragging = false -- shared flag while dragging

-- Simple helper functions (kept minimal; sesuaikan dengan environmentmu)
local function getGun()
    local ch = player.Character
    if ch then
        local g = ch:FindFirstChild("DefaultGun") or ch:FindFirstChildWhichIsA("Tool")
        if g then return g end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        local g = bp:FindFirstChild("DefaultGun") or bp:FindFirstChildWhichIsA("Tool")
        if g then return g end
    end
    return nil
end

local function getNearestTarget()
    local myChar = player.Character
    if not myChar then return nil end
    local myPart = myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Head")
    if not myPart then return nil end
    local myPos = myPart.Position
    local nearest, nd = nil, math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local tp = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChild("Head")
            if tp then
                local d = (tp.Position - myPos).Magnitude
                if d < nd then nd = d; nearest = plr end
            end
        end
    end
    return nearest
end

local function fireGun()
    local gun = getGun()
    if not gun then return false end
    local rem = gun:FindFirstChild("fire")
    if rem and rem:IsA("RemoteEvent") then
        pcall(function() rem:FireServer() end)
        return true
    end
    return false
end

local function showBeam(startPos, endPos)
    local gun = getGun()
    if not gun then return false end
    local rem = gun:FindFirstChild("showBeam")
    if rem and rem:IsA("RemoteEvent") then
        local handle = gun:FindFirstChild("Handle")
        if not handle then
            handle = Instance.new("Part")
            handle.Name = "Handle"
            handle.Transparency = 1
            handle.Size = Vector3.new(1,1,1)
            handle.Parent = gun
        end
        pcall(function() rem:FireServer(startPos, endPos, handle) end)
        return true
    end
    return false
end

local function damageTarget(target)
    local gun = getGun()
    if not gun or not target or not target.Character then return false end
    local rem = gun:FindFirstChild("kill")
    if rem and rem:IsA("RemoteEvent") then
        local myRoot = player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head"))
        local tRoot = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Head")
        if myRoot and tRoot then
            local dir = (tRoot.Position - myRoot.Position).Unit
            pcall(function() rem:FireServer(target, dir) end)
            return true
        end
    end
    return false
end

local function shootTarget(target)
    if not target or not target.Character then return false end
    local myChar = player.Character
    if not myChar then return false end
    local origin = myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Head")
    local tgt = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Head")
    if not origin or not tgt then return false end
    fireGun()
    showBeam(origin.Position, tgt.Position)
    damageTarget(target)
    return true
end

-- =========== UI ===========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoShootGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 100, 0, 36) -- sedikit lebih tinggi utk strip
mainFrame.Position = UDim2.new(0.5, -50, 0.1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(35,35,35)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

-- small transparent drag strip (top)
local dragBar = Instance.new("Frame", mainFrame)
dragBar.Name = "DragBar"
dragBar.Size = UDim2.new(1, 0, 0, 8) -- 8px tinggi
dragBar.Position = UDim2.new(0, 0, 0, 0)
dragBar.BackgroundColor3 = Color3.new(0,0,0)
dragBar.BackgroundTransparency = 1 -- transparan tapi still captures input
dragBar.BorderSizePixel = 0
dragBar.ZIndex = 5
dragBar.Active = true

-- Toggle button below strip
local toggleButton = Instance.new("TextButton", mainFrame)
toggleButton.Name = "Toggle"
toggleButton.Size = UDim2.new(1, 0, 1, -8) -- mengisi sisa frame
toggleButton.Position = UDim2.new(0, 0, 0, 8)
toggleButton.BackgroundColor3 = Color3.fromRGB(80,80,80)
toggleButton.AutoButtonColor = true
toggleButton.Text = "OFF"
toggleButton.TextColor3 = Color3.fromRGB(255,100,100)
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.TextSize = 16
toggleButton.ZIndex = 1

local infoLabel = Instance.new("TextLabel", mainFrame)
infoLabel.Size = UDim2.new(1, 0, 0, 10)
infoLabel.Position = UDim2.new(0, 0, 1, -10)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = ""
infoLabel.TextSize = 10
infoLabel.TextColor3 = Color3.fromRGB(200,200,200)
infoLabel.Font = Enum.Font.SourceSans

-- =========== Drag logic on dragBar (mouse + touch) ===========
do
    local isDragging = false
    local dragStartPos = nil
    local frameStart = nil
    local dragInput = nil

    dragBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            dragging = true
            dragStartPos = input.Position
            frameStart = mainFrame.Position
            dragInput = input

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    isDragging = false
                    dragging = false
                    dragInput = nil
                end
            end)
        end
    end)

    dragBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isDragging and input == dragInput then
            local delta = input.Position - dragStartPos
            mainFrame.Position = UDim2.new(
                frameStart.X.Scale, frameStart.X.Offset + delta.X,
                frameStart.Y.Scale, frameStart.Y.Offset + delta.Y
            )
        end
    end)
end

-- =========== Toggle logic ===========
toggleButton.MouseButton1Click:Connect(function()
    -- jika sedang drag via strip, jangan toggle
    if dragging then return end

    autoShootEnabled = not autoShootEnabled
    if autoShootEnabled then
        toggleButton.Text = "ON"
        toggleButton.TextColor3 = Color3.fromRGB(100,255,100)
        toggleButton.BackgroundColor3 = Color3.fromRGB(45,45,45)

        if conn then conn:Disconnect() end
        acc = 0
        conn = RunService.Heartbeat:Connect(function(dt)
            if not autoShootEnabled then return end
            acc = acc + dt
            if acc >= shootInterval then
                acc = 0
                local t = getNearestTarget()
                if t then
                    shootTarget(t)
                    -- print("Shot", t.Name)
                end
            end
        end)
    else
        toggleButton.Text = "OFF"
        toggleButton.TextColor3 = Color3.fromRGB(255,100,100)
        toggleButton.BackgroundColor3 = Color3.fromRGB(80,80,80)
        if conn then conn:Disconnect() conn = nil end
    end
end)

-- show small debug info on gun name and interval
spawn(function()
    while screenGui.Parent do
        local g = getGun()
        infoLabel.Text = ("Gun: %s | Int: %.3f"):format((g and g.Name) or "NoGun", shootInterval)
        task.wait(0)
    end
end)

print("✅ AutoShoot GUI (with small drag bar) loaded —:)")
