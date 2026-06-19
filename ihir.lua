local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DropGiftStandalone"
ScreenGui.Parent = game.CoreGui

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 220, 0, 160)
Frame.Position = UDim2.new(0.5, -110, 0.5, -80)
Frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "Drop & Gift (Slot 2)"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.Parent = Frame

local UserInput = Instance.new("TextBox")
UserInput.Size = UDim2.new(0.9, 0, 0, 35)
UserInput.Position = UDim2.new(0.05, 0, 0.3, 0)
UserInput.PlaceholderText = "Target Username..."
UserInput.Text = ""
UserInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
UserInput.TextColor3 = Color3.new(1, 1, 1)
UserInput.Font = Enum.Font.GothamSemibold
UserInput.TextSize = 14
UserInput.Parent = Frame
local InputCorner = Instance.new("UICorner")
InputCorner.Parent = UserInput

local StartBtn = Instance.new("TextButton")
StartBtn.Size = UDim2.new(0.9, 0, 0, 40)
StartBtn.Position = UDim2.new(0.05, 0, 0.65, 0)
StartBtn.Text = "START"
StartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
StartBtn.TextColor3 = Color3.new(1, 1, 1)
StartBtn.Font = Enum.Font.GothamBold
StartBtn.TextSize = 16
StartBtn.Parent = Frame
local BtnCorner = Instance.new("UICorner")
BtnCorner.Parent = StartBtn

-- LOGIC
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net
pcall(function()
    Net = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
end)

local function getCategoryAndId(itemObj)
    if not itemObj or not itemObj:IsA("Tool") then return nil, nil end
    
    local category = nil
    local uuid = nil
    
    if itemObj:GetAttribute("HarvestedFruit") == true then
        category = "HarvestedFruits"
        uuid = itemObj:GetAttribute("Id")
    elseif itemObj:GetAttribute("PetId") and type(itemObj:GetAttribute("PetId")) == "string" and itemObj:GetAttribute("PetId") ~= "" then
        category = "Pets"
        uuid = itemObj:GetAttribute("PetId")
    else
        local u5 = {
            SeedTool = "Seeds", SeedPack = "SeedPacks", Crate = "Crates",
            Sprinkler = "Sprinklers", WateringCan = "WateringCans", Mushroom = "Mushrooms",
            Gnome = "Gnomes", Raccoon = "Raccoons", Teleporter = "Teleporters",
            Magnet = "Magnets", Wheelbarrow = "Wheelbarrows", Trowel = "Trowels",
            Crowbar = "Crowbars", Ladder = "Ladders", FreezeRay = "FreezeRays",
            PowerHose = "PowerHoses", Rake = "Rakes", Lantern = "Lanterns",
            Sign = "Signs", EmptyPot = "EmptyPots", Flashbang = "Flashbangs",
            Bird = "Birds"
        }
        for attr, cat in pairs(u5) do
            if itemObj:GetAttribute(attr) ~= nil then
                category = cat
                uuid = itemObj:GetAttribute(attr)
                break
            end
        end
    end
    return category, uuid
end

StartBtn.MouseButton1Click:Connect(function()
    if not Net then
        StartBtn.Text = "Network Module Error"
        return
    end

    local targetName = UserInput.Text
    if targetName == "" then return end
    
    local targetPlayer = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.Name) == string.lower(targetName) or string.lower(p.DisplayName) == string.lower(targetName) then
            targetPlayer = p
            break
        end
    end
    
    if not targetPlayer then
        StartBtn.Text = "Player Not Found!"
        task.wait(1.5)
        StartBtn.Text = "START"
        return
    end
    
    local targetId = targetPlayer.UserId
    
    -- Temukan Hotbar
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local hotbar = pg and pg:FindFirstChild("BackpackGui") and pg.BackpackGui:FindFirstChild("Backpack") and pg.BackpackGui.Backpack:FindFirstChild("Hotbar")
    
    if not hotbar then
        StartBtn.Text = "Hotbar Not Found!"
        task.wait(1.5)
        StartBtn.Text = "START"
        return
    end
    
    -- Cari Slot 2
    local slotBtn = hotbar:FindFirstChild("2")
    if not slotBtn then
        StartBtn.Text = "Slot 2 Empty"
        task.wait(1.5)
        StartBtn.Text = "START"
        return
    end
    
    local toolNameLbl = slotBtn:FindFirstChild("ToolName")
    if not toolNameLbl or not toolNameLbl:IsA("TextLabel") then return end
    
    local toolName = toolNameLbl.Text
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    
    local foundTool = nil
    if backpack then foundTool = backpack:FindFirstChild(toolName) end
    if not foundTool and char then foundTool = char:FindFirstChild(toolName) end
    
    if not foundTool then
        StartBtn.Text = "Tool Not Found"
        task.wait(1.5)
        StartBtn.Text = "START"
        return
    end
    
    local category, uuid = getCategoryAndId(foundTool)
    if not category or not uuid then
        StartBtn.Text = "Invalid Item Data"
        task.wait(1.5)
        StartBtn.Text = "START"
        return
    end
    
    -- Equip the tool first, because the server requires the item to be held to drop it!
    if foundTool.Parent ~= char then
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:EquipTool(foundTool)
            task.wait(0.2) -- Wait for equip to register on server
        end
    end
    
    -- Eksekusi: Drop First, Then Gift
    StartBtn.Text = "Processing..."
    
    pcall(function()
        Net.DroppedItem.RequestDrop:Fire(category, uuid)
    end)
    
    task.wait(0.2) -- Jeda kecil untuk keamanan
    
    pcall(function()
        Net.Gifting.Send:Fire(targetId, category, uuid)
    end)
    
    StartBtn.Text = "Done! Closing..."
    task.wait(1.5)
    ScreenGui:Destroy()
end)
