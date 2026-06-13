-- ULTRA EXTREME Low Graphics & CPU Saver untuk Mobile
-- Mengubah game menjadi "Console Mode" (Layar blank/hitam, tapi bot tetap jalan dengan kencang)

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local function ApplyUltraExtreme()
    -- 1. MATIKAN RENDER 3D (Meringankan GPU hingga 95%!)
    pcall(function()
        RunService:Set3dRenderingEnabled(false)
    end)

    -- (FPS Cap Dihapus agar script seperti task.wait() di gag.lua tetap berjalan dengan kecepatan kilat)

    -- 2. MATIKAN AUDIO (Audio processing memakan lumayan banyak CPU di Mobile)
    pcall(function()
        UserSettings():GetService("UserGameSettings").MasterVolume = 0
    end)

    -- 3. HAPUS LIGHTING & TERRAIN
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    Lighting.ShadowSoftness = 0
    if sethiddenproperty then
        pcall(function() sethiddenproperty(Lighting, "Technology", 2) end)
    end
    Lighting:ClearAllChildren()
    
    local Terrain = Workspace:FindFirstChildOfClass("Terrain")
    if Terrain then
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        if sethiddenproperty then pcall(function() sethiddenproperty(Terrain, "Decoration", false) end) end
    end

    -- 4. MATIKAN ANIMASI & FISIKA (Penyebab utama CPU 200ms+)
    local function KillCPUHogs(v)
        if v:IsA("SurfaceGui") or v:IsA("BillboardGui") then
            v.Enabled = false
        elseif v:IsA("Animator") or v:IsA("AnimationController") then
            -- Bunuh semua sistem animasi KECUALI milik kita sendiri
            local isLocal = false
            local current = v
            while current.Parent do
                if current.Parent.Name == Players.LocalPlayer.Name then
                    isLocal = true
                    break
                end
                current = current.Parent
            end
            if not isLocal then
                v:Destroy()
            end
        elseif v:IsA("Humanoid") then
            -- Melumpuhkan mesin Humanoid pada NPC agar tidak membebani CPU (Pathfinding/Physics)
            local isLocal = false
            local current = v
            while current.Parent do
                if current.Parent.Name == Players.LocalPlayer.Name then
                    isLocal = true
                    break
                end
                current = current.Parent
            end
            if not isLocal then
                pcall(function()
                    v:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Hover, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
                    v:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                end)
            end
        elseif v:IsA("BasePart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
            -- Mematikan kalkulasi Raycast & Physics Query
            pcall(function()
                v.CanQuery = false
            end)
        elseif v:IsA("Decal") or v:IsA("Texture") or v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
            v:Destroy()
        elseif v:IsA("MeshPart") then
            v.TextureID = ""
        end
    end

    for _, v in ipairs(Workspace:GetDescendants()) do
        KillCPUHogs(v)
    end

    Workspace.DescendantAdded:Connect(function(v)
        task.spawn(function()
            task.wait()
            KillCPUHogs(v)
        end)
    end)
    
    print("[CPU SAVER] Extreme Mode Aktif! 3D Render OFF, Kalkulasi Fisika/Animasi dilumpuhkan.")
end

ApplyUltraExtreme()
