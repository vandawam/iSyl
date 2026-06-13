-- ============================================================
-- AUTO COLLECT & ANTI-AFK (NO UI / BACKGROUND MODE)
-- Script ringan untuk mengumpulkan drop dan mencegah AFK tanpa membebani CPU
-- ============================================================

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local CollectionService = game:GetService("CollectionService")

repeat task.wait() until game:IsLoaded()

local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))

-- 1. Anti-AFK (Sama persis seperti di gag.lua)
pcall(function()
    if getconnections then
        for _, connection in pairs(getconnections(LocalPlayer.Idled)) do
            if type(connection) == "table" and connection.Disable then
                connection:Disable()
            end
        end
    end
end)

LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        print("[Anti-AFK] Mencegah tendangan AFK Roblox (Idled Event).")
    end)
end)

-- Custom Game Anti-AFK Bypass (Membobol AntiAfkController.lua milik Grow a Garden)
task.spawn(function()
    while task.wait(5) do
        pcall(function()
            LocalPlayer:SetAttribute("AntiAfkIdleOverride", 9e9)
        end)
    end
end)

-- 2. Auto Collect Drops (Looping tanpa batas)
local claimActive = false
local function startClaimLoop()
    if claimActive then return end
    claimActive = true
    task.spawn(function()
        while true do
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local itemsToClaim = {}

                -- Scan drop folders
                local dropFolders = {}
                local function addFolder(folder)
                    if folder then table.insert(dropFolders, folder) end
                end

                addFolder(workspace:FindFirstChild("Drops"))
                addFolder(workspace:FindFirstChild("DroppedItems"))
                addFolder(workspace:FindFirstChild("Items"))
                addFolder(workspace:FindFirstChild("Debris"))
                addFolder(workspace:FindFirstChild("Temporary"))
                
                local mapFolder = workspace:FindFirstChild("Map")
                if mapFolder then
                    addFolder(mapFolder:FindFirstChild("SeedPackSpawnServerLocations"))
                    addFolder(mapFolder:FindFirstChild("WildPets"))
                end

                for _, f in ipairs(dropFolders) do
                    if f then
                        for _, item in ipairs(f:GetChildren()) do
                            table.insert(itemsToClaim, item)
                        end
                    end
                end
                
                -- Fallback scan
                for _, v in ipairs(workspace:GetChildren()) do
                    local name = string.lower(v.Name)
                    if string.find(name, "drop") or string.find(name, "seed") or string.find(name, "fruit") or string.find(name, "pet") then
                        if v.Parent == workspace then
                            table.insert(itemsToClaim, v)
                        end
                    end
                end
                
                for _, item in ipairs(itemsToClaim) do
                    local parentName = item.Parent and item.Parent.Name or ""
                    
                    -- Khusus untuk Seed Pack Spawns
                    if parentName == "SeedPackSpawnServerLocations" then
                        local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if not prompt then
                            for _, child in ipairs(item:GetChildren()) do
                                if child:IsA("ProximityPrompt") then
                                    prompt = child
                                    break
                                end
                            end
                        end
                        
                        local targetPart = nil
                        if item:IsA("BasePart") then
                            targetPart = item
                        else
                            targetPart = item:FindFirstChildWhichIsA("BasePart", true)
                        end
                        
                        if targetPart then
                            local oldHrpCf = hrp.CFrame
                            local cam = workspace.CurrentCamera
                            local oldCamType = cam.CameraType
                            local oldCamCf = cam.CFrame
                            
                            cam.CameraType = Enum.CameraType.Scriptable
                            cam.CFrame = oldCamCf
                            hrp.CFrame = targetPart.CFrame
                            task.wait(0.3)
                            
                            if prompt then
                                pcall(function()
                                    if not prompt.Enabled then prompt.Enabled = true end
                                    fireproximityprompt(prompt)
                                end)
                            end
                            
                            pcall(function()
                                Networking.SeedPack.ClickPack:Fire(item.Name)
                            end)
                            
                            for _, desc in ipairs(item:GetDescendants()) do
                                if desc:IsA("BasePart") and desc:FindFirstChildOfClass("TouchTransmitter") then
                                    pcall(function()
                                        firetouchinterest(hrp, desc, 0)
                                        firetouchinterest(hrp, desc, 1)
                                    end)
                                end
                            end
                            
                            task.wait(0.5)
                            hrp.CFrame = oldHrpCf
                            cam.CameraType = oldCamType
                        else
                            pcall(function()
                                Networking.SeedPack.ClickPack:Fire(item.Name)
                            end)
                        end
                        continue
                    end
                    
                    -- Khusus Pet Liar
                    if parentName == "WildPets" or item:GetAttribute("PetId") then
                        pcall(function()
                            Networking.Pets.WildPetTame:Fire(item)
                        end)
                        continue
                    end
                    
                    local partsToTouch = {}
                    local promptsToFire = {}
                    local targetPart = nil
                    
                    if item:IsA("BasePart") then targetPart = item end
                    
                    local collectEvent = item:FindFirstChild("Collect")
                    if collectEvent then
                        if collectEvent:IsA("RemoteEvent") then
                            collectEvent:FireServer()
                        elseif collectEvent:IsA("BindableEvent") then
                            collectEvent:Fire()
                        elseif collectEvent:IsA("ProximityPrompt") then
                            table.insert(promptsToFire, collectEvent)
                            targetPart = collectEvent.Parent
                        end
                    end
                    
                    for _, part in ipairs(item:GetDescendants()) do
                        if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
                            table.insert(partsToTouch, part)
                        elseif part:IsA("ProximityPrompt") then
                            local tags = CollectionService:GetTags(part)
                            if not table.find(tags, "HarvestPrompt") and not table.find(tags, "StealPrompt") then
                                table.insert(promptsToFire, part)
                            end
                        end
                    end
                    
                    if item.Parent and (item.Parent.Name == "DroppedItems" or item.Parent.Name == "Drops") then
                        pcall(function()
                            Networking.DroppedItem.RequestPickup:Fire(item.Name)
                        end)
                    end
                    
                    if #partsToTouch > 0 or #promptsToFire > 0 or (item.Parent and item.Parent.Name == "DroppedItems") then
                        local targetPart2 = partsToTouch[1]
                        if not targetPart2 and #promptsToFire > 0 then
                            local p = promptsToFire[1]
                            if p.Parent and p.Parent:IsA("BasePart") then
                                targetPart2 = p.Parent
                            elseif p.Parent and p.Parent:IsA("Attachment") and p.Parent.Parent and p.Parent.Parent:IsA("BasePart") then
                                targetPart2 = p.Parent.Parent
                            end
                        end
                        if not targetPart2 and item:IsA("Model") and item.PrimaryPart then
                            targetPart2 = item.PrimaryPart
                        end
                        if not targetPart2 then
                            targetPart2 = item:FindFirstChildWhichIsA("BasePart", true)
                        end
                        if targetPart2 and targetPart2:IsA("BasePart") then
                            local dist = (hrp.Position - targetPart2.Position).Magnitude
                            local oldHrpCf = hrp.CFrame
                            local cam = workspace.CurrentCamera
                            local oldCamType = cam.CameraType
                            local oldCamCf = cam.CFrame
                            local didTeleport = false
                            
                            if dist > 12 then
                                didTeleport = true
                                cam.CameraType = Enum.CameraType.Scriptable
                                cam.CFrame = oldCamCf
                                
                                hrp.CFrame = targetPart2.CFrame
                                task.wait(0.2)
                            end
                            
                            for _, p in ipairs(partsToTouch) do
                                pcall(function()
                                    firetouchinterest(hrp, p, 0)
                                    firetouchinterest(hrp, p, 1)
                                end)
                            end
                            for _, p in ipairs(promptsToFire) do
                                pcall(function()
                                    if not p.Enabled then p.Enabled = true end
                                    fireproximityprompt(p)
                                end)
                            end
                            
                            if didTeleport then
                                task.wait(0.2)
                                hrp.CFrame = oldHrpCf
                                cam.CameraType = oldCamType
                            end
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end

print("==============================================")
print("[AutoCollect] Memulai layanan Background (NO UI)...")
startClaimLoop()
print("[AutoCollect] Selesai memuat! Silakan AFK dengan aman.")
print("==============================================")
