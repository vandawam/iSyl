local WebhookURL = "https://discord.com/api/webhooks/1515337841532604486/sm4DRS4lZsaFCtyb_Su8lQH9Enxdeebk3zVGDwfAoVDEfziQAYhbIDrTQBaeSvt2lgaK"

local function SendWebhook(weatherName)
    -- Mendukung berbagai executor (Synapse, Krnl, Fluxus, dll)
    local req = http_request or request or HttpPost or (syn and syn.request)
    if not req then
        warn("Executor kamu tidak mendukung HTTP requests!")
        return
    end

    local data = {
        ["content"] = "Next Wheater: " .. tostring(weatherName)
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

-- Deteksi saat fase waktu berubah
workspace:GetAttributeChangedSignal("ActivePhase"):Connect(function()
    local currentPhase = workspace:GetAttribute("ActivePhase")
    
    -- Hanya kirim jika baru saja berubah menjadi "Night" (Malam)
    if currentPhase == "Night" then
        -- Beri jeda sedikit memastikan atribut ActiveWeather sudah diubah oleh server juga
        task.wait(1) 
        local currentWeather = workspace:GetAttribute("ActiveWeather") or "Unknown"
        
        SendWebhook(currentWeather)
        print("[Webhook] Pesan cuaca terkirim ke Discord: " .. currentWeather)
    end
end)

print("[Webhook] Monitoring Cuaca Dimulai! Menunggu malam tiba...")
