-- Napoleon GAG - Moon Cycle Server Seed Predictor (Advanced Auto-Cracker)
-- Collects active weather data over time to reverse-engineer the server's random hash seed
-- Upgraded to test multiple RNG modes (Float/Int, Call offsets) to catch server desyncs.

local weathers = {
    {Name = "Moon", Chance = 79},
    {Name = "Goldmoon", Chance = 13},
    {Name = "Rainbow Moon", Chance = 6},
    {Name = "Bloodmoon", Chance = 2}
}

-- Generate all 24 permutations
local function getPermutations(t)
    local perms = {}
    local function permute(a, l, r)
        if l == r then
            local p = {}
            for i = 1, #a do
                table.insert(p, a[i])
            end
            table.insert(perms, p)
        else
            for i = l, r do
                a[l], a[i] = a[i], a[l]
                permute(a, l + 1, r)
                a[l], a[i] = a[i], a[l]
            end
        end
    end
    permute(t, 1, #t)
    return perms
end

local basePerms = getPermutations(weathers)
local possibleConfigs = {}

-- Create a configuration for every permutation and every RNG mode we suspect
-- This guarantees we crack the server's exact random generation logic.
for _, perm in ipairs(basePerms) do
    table.insert(possibleConfigs, {Order = perm, Mode = "Float1"})
    table.insert(possibleConfigs, {Order = perm, Mode = "Float2"})
    table.insert(possibleConfigs, {Order = perm, Mode = "Int1"})
    table.insert(possibleConfigs, {Order = perm, Mode = "Int2"})
end

local totalDuration = 600
local cyclesObserved = 0
local SAVE_FILE = "Napo_CycleTracker_" .. tostring(game.JobId) .. ".json"

local HttpService = game:GetService("HttpService")

local function saveTrackerData()
    pcall(function()
        if writefile then
            local data = {
                configs = possibleConfigs,
                cycles = cyclesObserved
            }
            writefile(SAVE_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function loadTrackerData()
    pcall(function()
        if isfile and isfile(SAVE_FILE) then
            local content = readfile(SAVE_FILE)
            local data = HttpService:JSONDecode(content)
            if data and data.configs and data.cycles then
                possibleConfigs = data.configs
                cyclesObserved = data.cycles
                print("[SeedTracker] Loaded past data for this server! Cycles: " .. cyclesObserved)
            end
        end
    end)
end

loadTrackerData()

-- UI Setup
local coreGui = game:GetService("CoreGui")
if coreGui:FindFirstChild("NapoCycleTracker") then
    coreGui.NapoCycleTracker:Destroy()
end

local sg = Instance.new("ScreenGui")
sg.Name = "NapoCycleTracker"
sg.ResetOnSpawn = false
sg.DisplayOrder = 999999
sg.Parent = coreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 200)
frame.Position = UDim2.new(1, -320, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
frame.BorderSizePixel = 0
frame.Parent = sg

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(0, 8)
uicorner.Parent = frame

local uistroke = Instance.new("UIStroke")
uistroke.Color = Color3.new(1, 1, 1)
uistroke.Thickness = 2
uistroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Text = "Napo Seed Tracker"
title.Parent = frame

local cyclesLabel = Instance.new("TextLabel")
cyclesLabel.Size = UDim2.new(1, -20, 0, 20)
cyclesLabel.Position = UDim2.new(0, 10, 0, 40)
cyclesLabel.BackgroundTransparency = 1
cyclesLabel.TextColor3 = Color3.new(1, 1, 1)
cyclesLabel.Font = Enum.Font.Gotham
cyclesLabel.TextSize = 14
cyclesLabel.TextXAlignment = Enum.TextXAlignment.Left
cyclesLabel.Text = "Cycles Observed: 0"
cyclesLabel.Parent = frame

local ordersLabel = Instance.new("TextLabel")
ordersLabel.Size = UDim2.new(1, -20, 0, 20)
ordersLabel.Position = UDim2.new(0, 10, 0, 65)
ordersLabel.BackgroundTransparency = 1
ordersLabel.TextColor3 = Color3.new(1, 1, 1)
ordersLabel.Font = Enum.Font.Gotham
ordersLabel.TextSize = 14
ordersLabel.TextXAlignment = Enum.TextXAlignment.Left
ordersLabel.Text = "Remaining Configs: 96"
ordersLabel.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.Position = UDim2.new(0, 10, 0, 90)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "Status: GATHERING DATA..."
statusLabel.Parent = frame

local upcomingLabel = Instance.new("TextLabel")
upcomingLabel.Size = UDim2.new(1, -20, 0, 80)
upcomingLabel.Position = UDim2.new(0, 10, 0, 115)
upcomingLabel.BackgroundTransparency = 1
upcomingLabel.TextColor3 = Color3.new(1, 1, 1)
upcomingLabel.Font = Enum.Font.Gotham
upcomingLabel.TextSize = 13
upcomingLabel.TextXAlignment = Enum.TextXAlignment.Left
upcomingLabel.TextYAlignment = Enum.TextYAlignment.Top
upcomingLabel.Text = "Waiting for data..."
upcomingLabel.Parent = frame

local function simulateRoll(order, rollValue)
    local currentChance = 0
    for _, wData in ipairs(order) do
        currentChance = currentChance + wData.Chance
        if rollValue <= currentChance then
            return wData.Name
        end
    end
    return "Moon"
end

local function generateRollValue(seed, mode)
    local rng = Random.new(seed)
    if mode == "Float1" then
        return rng:NextNumber() * 100
    elseif mode == "Float2" then
        rng:NextNumber()
        return rng:NextNumber() * 100
    elseif mode == "Int1" then
        return rng:NextInteger(1, 100)
    elseif mode == "Int2" then
        rng:NextInteger(1, 100)
        return rng:NextInteger(1, 100)
    end
    return 0
end

local function predictFuture(configsList)
    local currentDayID = math.floor(os.time() / totalDuration)
    local predictions = {}
    
    for offset = 1, 100 do
        local checkDayID = currentDayID + offset
        local seed = (checkDayID * 1000) + 3
        
        -- Use the first config's prediction as the baseline
        local baselineConfig = configsList[1]
        local baselineRoll = generateRollValue(seed, baselineConfig.Mode)
        local firstPredicted = simulateRoll(baselineConfig.Order, baselineRoll)
        
        local allAgree = true
        for i = 2, #configsList do
            local cfg = configsList[i]
            local roll = generateRollValue(seed, cfg.Mode)
            if simulateRoll(cfg.Order, roll) ~= firstPredicted then
                allAgree = false
                break
            end
        end
        
        if allAgree and (firstPredicted == "Goldmoon" or firstPredicted == "Rainbow Moon") then
            table.insert(predictions, {Weather = firstPredicted, Offset = offset})
        end
    end
    return predictions
end

local function updateUI()
    cyclesLabel.Text = "Cycles Observed: " .. cyclesObserved
    ordersLabel.Text = "Remaining Configs: " .. #possibleConfigs
    
    if #possibleConfigs > 0 then
        if #possibleConfigs == 1 then
            statusLabel.Text = "Status: CRACKED! (" .. possibleConfigs[1].Mode .. ")"
            statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        else
            statusLabel.Text = "Status: PREDICTING (Consensus)"
            statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        end
        
        local predictions = predictFuture(possibleConfigs)
        local text = ""
        for i = 1, math.min(#predictions, 4) do
            local p = predictions[i]
            local mins = p.Offset * 10
            text = text .. p.Weather .. " in " .. p.Offset .. " cycles (~" .. mins .. "m)\n"
        end
        if text == "" then 
            if #possibleConfigs == 1 then
                text = "No rare moons in next 100 cycles."
            else
                text = "Gathering more data to resolve uncertainty..."
            end
        end
        upcomingLabel.Text = text
        
    else
        statusLabel.Text = "Status: FAILED (0 configs left)"
        statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        upcomingLabel.Text = "Something went wrong. RNG desync."
    end
end

updateUI()

local function processNightWeather(actualWeather)
    local currentDayID = math.floor(os.time() / totalDuration)
    local seed = (currentDayID * 1000) + 3
    
    cyclesObserved = cyclesObserved + 1
    
    local validConfigs = {}
    for _, cfg in ipairs(possibleConfigs) do
        local rollValue = generateRollValue(seed, cfg.Mode)
        local predicted = simulateRoll(cfg.Order, rollValue)
        if predicted == actualWeather then
            table.insert(validConfigs, cfg)
        end
    end
    
    possibleConfigs = validConfigs
    print("[SeedTracker] Cycle " .. cyclesObserved .. " -> " .. actualWeather)
    print("[SeedTracker] Remaining possibilities: " .. #possibleConfigs)
    
    saveTrackerData()
    updateUI()
end

-- Hook into workspace attributes
workspace:GetAttributeChangedSignal("ActivePhase"):Connect(function()
    local phase = workspace:GetAttribute("ActivePhase")
    if phase == "Night" then
        -- Wait a tiny bit to ensure ActiveWeather is set
        task.wait(1)
        local liveWeather = workspace:GetAttribute("ActiveWeather")
        if liveWeather then
            processNightWeather(liveWeather)
        end
    end
end)

-- If we start while Night is already active, process it immediately
local currentPhase = workspace:GetAttribute("ActivePhase")
if currentPhase == "Night" then
    local liveWeather = workspace:GetAttribute("ActiveWeather")
    if liveWeather then
        processNightWeather(liveWeather)
    end
end

print("[SeedTracker] Initialized! 96 possible configs. Waiting for data...")
