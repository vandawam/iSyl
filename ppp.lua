local WebhookURL = "https://discord.com/api/webhooks/1515337841532604486/sm4DRS4lZsaFCtyb_Su8lQH9Enxdeebk3zVGDwfAoVDEfziQAYhbIDrTQBaeSvt2lgaK"

local function SendWebhook(contentString)
    -- Mendukung berbagai executor (Synapse, Krnl, Fluxus, dll)
    local req = http_request or request or HttpPost or (syn and syn.request)
    if not req then
        warn("Executor kamu tidak mendukung HTTP requests!")
        return
    end

    local data = {
        ["content"] = contentString
    }

    local jsonData = game:GetService("HttpService"):JSONEncode(data)

    req({
        Url = WebhookURL,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json"
        },
        Body = jsonData
    })
end

local TimeCycleData = require(game:GetService("ReplicatedStorage").SharedModules.TimeCycleData)

-- Fungsi untuk meramal cuaca malam ini (karena game menggunakan os.time() Global)
local function PredictNightWeather()
    local totalDuration = 450 + 30 + 120 -- Day + Sunset + Night = 600 detik
    local currentDayID = math.floor(os.time() / totalDuration)
    
    -- Fase malam adalah fase ke-3. Algoritma gamenya menggunakan (DayID * 1000) + PhaseIndex
    local rng = Random.new((currentDayID * 1000) + 3)
    
    local nightWeathers = TimeCycleData.Data.Night.Weathers
    local totalChance = 0
    for _, wData in pairs(nightWeathers) do
        totalChance = totalChance + wData.Chance
    end
    
    local roll = rng:NextNumber() * totalChance
    local currentChance = 0
    for wName, wData in pairs(nightWeathers) do
        currentChance = currentChance + wData.Chance
        if roll <= currentChance then
            return wName
        end
    end
    return "Unknown"
end

-- Fungsi Radar untuk mencari kapan cuaca tertentu berikutnya muncul
local function FindNextMoonSchedule(targetWeather, isDiscord)
    local totalDuration = 600
    local currentDayID = math.floor(os.time() / totalDuration)
    local nightWeathers = TimeCycleData.Data.Night.Weathers
    local totalChance = 0
    for _, wData in pairs(nightWeathers) do
        totalChance = totalChance + wData.Chance
    end
    
    -- Scan hingga 100 siklus (sekitar 16 jam ke depan)
    for offset = 0, 100 do
        local checkDayID = currentDayID + offset
        local rng = Random.new((checkDayID * 1000) + 3)
        
        local roll = rng:NextNumber() * totalChance
        local currentChance = 0
        local predictedWeather = "Unknown"
        for wName, wData in pairs(nightWeathers) do
            currentChance = currentChance + wData.Chance
            if roll <= currentChance then
                predictedWeather = wName
                break
            end
        end
        
        if predictedWeather == targetWeather then
            -- Hitung sisa waktu mundur secara real-time
            local timeUntil = (offset * totalDuration) - (os.time() % totalDuration) 
            -- Karena malam dimulai setelah 450 (Day) + 30 (Sunset) = 480 detik
            timeUntil = timeUntil + 480 
            
            local targetUnixTime = math.floor(os.time() + timeUntil)
            
            if isDiscord then
                if timeUntil < 0 then
                    return "SEDANG BERLANGSUNG! (Dimulai <t:" .. targetUnixTime .. ":R>)"
                elseif offset == 0 then
                    return "Siklus ini! (<t:" .. targetUnixTime .. ":R>)"
                else
                    return "Dalam " .. offset .. " Siklus (<t:" .. targetUnixTime .. ":R>)"
                end
            else
                if timeUntil < 0 then
                    return "Malam ini SEDANG BERLANGSUNG sekarang!"
                end
                local minutes = math.floor(timeUntil / 60)
                local seconds = timeUntil % 60
                if offset == 0 then
                    return "Siklus saat ini! (" .. minutes .. " Menit " .. seconds .. " Detik lagi)"
                else
                    return  offset .. " Siklus (" .. minutes .. " Menit " .. seconds .. " Detik lagi)"
                end
            end
        end
    end
    return "Tidak ditemukan dalam 16 jam ke depan"
end

-- Deteksi saat fase waktu berubah
workspace:GetAttributeChangedSignal("ActivePhase"):Connect(function()
    local currentPhase = workspace:GetAttribute("ActivePhase")
    
    -- Kirim Prediksi Webhook SAAT PETANG (Sunset), sebelum malam tiba!
    if currentPhase == "Sunset" then
        local predictedWeather = PredictNightWeather()
        -- Kita gunakan isDiscord = true untuk menggunakan <t:UnixTime:R>
        local rainbowSchedule = FindNextMoonSchedule("Rainbow Moon", true)
        local goldSchedule = FindNextMoonSchedule("Goldmoon", true)
        
        local messageText = "🌙 **Next Night:** " .. predictedWeather .. "\n" ..
                            "🌈 **Next Rainbow Moon:** " .. rainbowSchedule .. "\n" ..
                            "🪙 **Next Gold Moon:** " .. goldSchedule
                            
        SendWebhook(messageText)
        print("[Webhook] Prediksi Malam Ini terkirim ke Discord!")
    end
end)

-- Ramal cuaca malam ini saat script baru pertama kali dijalankan
print("==============================================")
print("[Webhook] Monitoring Cuaca Dimulai!")
print("[Webhook] RAMALAN MALAM INI: " .. PredictNightWeather())
print("[Webhook] JADWAL RAINBOW MOON: " .. FindNextMoonSchedule("Rainbow Moon", false))
print("[Webhook] JADWAL GOLD MOON: " .. FindNextMoonSchedule("Goldmoon", false))
print("==============================================")
