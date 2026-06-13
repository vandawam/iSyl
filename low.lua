-- ULTRA EXTREME Low Graphics & CPU Saver untuk Mobile
-- Mengubah game menjadi "Console Mode" (Layar blank/hitam, tapi bot tetap jalan)

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local function ApplyUltraExtreme()
    -- 1. MATIKAN RENDER 3D (Meringankan GPU hingga 95%!)
    -- Layar akan membeku/hitam di map, tapi UI executor tetap bisa disentuh.
    pcall(function()
        RunService:Set3dRenderingEnabled(false)
    end)

    -- 2. BATASI FPS (Meringankan CPU secara masif)
    -- Karena kita hanya AFK, game tidak perlu berjalan di 60 FPS. 15 FPS sudah cukup untuk bot.
    if setfpscap then
        setfpscap(15)
    end

    -- 3. MATIKAN AUDIO (Audio processing memakan lumayan banyak CPU di Mobile)
    pcall(function()
        UserSettings():GetService("UserGameSettings").MasterVolume = 0
    end)

    -- 4. HAPUS LIGHTING & TERRAIN
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    Lighting.ShadowSoftness = 0
    if sethiddenproperty then
        pcall(function() sethiddenproperty(Lighting, "Technology", 2) end)
    end
    Lighting:ClearAllChildren() -- Hapus semua efek secara instan
    
    local Terrain = Workspace:FindFirstChildOfClass("Terrain")
    if Terrain then
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        if sethiddenproperty then pcall(function() sethiddenproperty(Terrain, "Decoration", false) end) end
    end

    -- 5. MATIKAN ANIMASI & GUI DALAM MAP (Penyebab utama CPU 200ms+)
    -- Roblox CPU sering penuh karena menghitung pergerakan NPC, Pet, dan Player lain.
    local function KillCPUHogs(v)
        if v:IsA("SurfaceGui") or v:IsA("BillboardGui") then
            -- GUI yang menempel di tembok/player memakan memori besar
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
        elseif v:IsA("BasePart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
        elseif v:IsA("Decal") or v:IsA("Texture") or v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
            v:Destroy() -- Langsung destroy, jangan cuma disabled!
        elseif v:IsA("MeshPart") then
            v.TextureID = ""
        end
    end

    for _, v in ipairs(Workspace:GetDescendants()) do
        KillCPUHogs(v)
    end

    -- Pastikan objek baru yang muncul juga dibunuh animasinya
    Workspace.DescendantAdded:Connect(function(v)
        task.spawn(function()
            task.wait()
            KillCPUHogs(v)
        end)
    end)
    
    print("[CPU SAVER] Extreme Mode Aktif! 3D Render Dimatikan, FPS dibatasi ke 15, Animasi dibunuh.")
end

ApplyUltraExtreme()
