-- Ultra Low Graphics Script untuk Mobile & Potato PC
-- Didesain untuk mengurangi beban CPU dan GPU secara drastis (Potato Mode)

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:WaitForChild("Terrain")

local function ApplyUltraLowGraphics()
    -- 1. Matikan fitur Lighting yang memakan performa GPU
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    Lighting.ShadowSoftness = 0
    
    -- Memaksa pencahayaan turun ke versi paling ringan (Compatibility) jika executor support
    if sethiddenproperty then
        pcall(function() sethiddenproperty(Lighting, "Technology", 2) end)
    end

    -- Hapus semua efek visual pasca-proses (Post-Processing) di Lighting
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("PostEffect") or effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect") or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect") or effect:IsA("DepthOfFieldEffect") or effect:IsA("Atmosphere") or effect:IsA("Sky") then
            effect:Destroy()
        end
    end

    -- 2. Jadikan Terrain serendah mungkin
    if Terrain then
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 1
        if sethiddenproperty then
            pcall(function() sethiddenproperty(Terrain, "Decoration", false) end)
        end
    end

    -- 3. Fungsi untuk membuat setiap benda (Part) menjadi grafik kentang
    local function OptimizePart(v)
        if v:IsA("BasePart") then
            -- Ubah bahan menjadi plastik mulus (tanpa tekstur material berat)
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
        elseif v:IsA("Decal") or v:IsA("Texture") then
            -- Tembus pandangkan gambar/tekstur tanpa menghapusnya agar script game tidak error
            v.Transparency = 1 
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
            -- Matikan partikel (sangat memakan CPU di Mobile)
            v.Enabled = false
        elseif v:IsA("MeshPart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
            -- Hapus tekstur jaring (mesh) agar hanya dirender sebagai warna solid
            v.TextureID = ""
        end
    end

    -- 4. Optimasi semua benda yang sudah ada di Map
    for _, v in ipairs(Workspace:GetDescendants()) do
        OptimizePart(v)
    end

    -- 5. Optimasi benda yang BARRU muncul (Mencegah drop FPS saat area baru dirender)
    Workspace.DescendantAdded:Connect(function(v)
        -- Diberi delay agar objek sempat di-load secara penuh oleh Roblox sebelum kita ubah
        task.spawn(function()
            task.wait()
            OptimizePart(v)
        end)
    end)
    
    -- 6. Menghilangkan Shadow dari karakter pemain saat spawn
    game:GetService("Players").PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(char)
            for _, v in ipairs(char:GetDescendants()) do
                OptimizePart(v)
            end
        end)
    end)
    
    print("[Optimasi] Ultra Low Graphics Berhasil Diterapkan! Beban CPU/GPU telah diringankan.")
end

-- Eksekusi langsung
ApplyUltraLowGraphics()
