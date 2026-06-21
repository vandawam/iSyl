-- ==========================================
-- 1. DEFINISI FUNGSI HARUS DI PALING ATAS
-- ==========================================

-- Eksekusi command dan strip semua whitespace (untuk single-value results)
local function execute_command(cmd)
    local f = io.popen(cmd)
    local result = f:read("*a")
    f:close()
    return result:gsub("%s+", "")
end

-- Eksekusi command dan kembalikan output mentah (untuk multi-line/parsing)
local function execute_raw(cmd)
    local f = io.popen(cmd)
    local result = f:read("*a")
    f:close()
    return result
end

-- Cek apakah proses aplikasi sedang berjalan (lebih robust dari pidof)
local function is_app_running(package_name)
    -- Metode 1: pidof
    local pid = execute_command("pidof " .. package_name)
    if pid ~= "" then
        return pid
    end
    -- Metode 2: pgrep (lebih toleran terhadap nama proses)
    pid = execute_command("pgrep -f " .. package_name)
    if pid ~= "" then
        return pid
    end
    -- Metode 3: cek via am stack (apakah task aktif)
    local stack_info = execute_raw("dumpsys activity activities 2>/dev/null | grep -i '" .. package_name .. "' | head -1")
    if stack_info ~= "" and stack_info:find(package_name) then
        -- Coba ambil PID dari proses list
        pid = execute_command("ps -A 2>/dev/null | grep '" .. package_name .. "' | awk '{print $2}' | head -1")
        if pid ~= "" then
            return pid
        end
        return "active" -- task ada tapi PID tidak ditemukan langsung
    end
    return ""
end

-- Resolve main activity dari sebuah package
local function get_launch_activity(package_name)
    local raw = execute_raw("cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER " .. package_name .. " 2>/dev/null")
    -- Output format biasanya: priority=0 preferredOrder=0 match=0x108000 ...\n package/activity
    for line in raw:gmatch("[^\r\n]+") do
        if line:find("/") and line:find(package_name) then
            return line:gsub("%s+", "")
        end
    end
    -- Fallback: coba dumpsys
    raw = execute_raw("dumpsys package " .. package_name .. " 2>/dev/null | grep -A1 'android.intent.action.MAIN' | grep -i 'activity' | head -1")
    local activity = raw:match(package_name .. "/([%w%.]+)")
    if activity then
        return package_name .. "/" .. activity
    end
    return nil
end

-- Cari elemen UI berdasarkan teks di dump uiautomator
-- Return: center_x, center_y atau nil jika tidak ditemukan
local function find_ui_by_text(search_text, dump_path)
    dump_path = dump_path or "/sdcard/ui_scan.xml"
    local f = io.open(dump_path, "r")
    if not f then return nil, nil end
    local content = f:read("*a")
    f:close()
    
    for node in content:gmatch('<node[^>]+') do
        local text = node:match('text="([^"]*)"%s')
        if text and text:lower():find(search_text:lower(), 1, true) then
            local l, t, r, b = node:match('bounds="%[(%d+),(%d+)%]%[(%d+),(%d+)%]"')
            if l then
                return math.floor((tonumber(l) + tonumber(r)) / 2),
                       math.floor((tonumber(t) + tonumber(b)) / 2)
            end
        end
    end
    return nil, nil
end

-- Cari elemen UI berdasarkan content-desc
local function find_ui_by_desc(search_desc, dump_path)
    dump_path = dump_path or "/sdcard/ui_scan.xml"
    local f = io.open(dump_path, "r")
    if not f then return nil, nil end
    local content = f:read("*a")
    f:close()
    
    for node in content:gmatch('<node[^>]+') do
        local desc = node:match('content%-desc="([^"]*)"')
        if desc and desc:lower():find(search_desc:lower(), 1, true) then
            local l, t, r, b = node:match('bounds="%[(%d+),(%d+)%]%[(%d+),(%d+)%]"')
            if l then
                return math.floor((tonumber(l) + tonumber(r)) / 2),
                       math.floor((tonumber(t) + tonumber(b)) / 2)
            end
        end
    end
    return nil, nil
end

-- Dump UI dan simpan ke file
local function dump_ui(path)
    path = path or "/sdcard/ui_scan.xml"
    os.execute("rm -f " .. path)
    os.execute("uiautomator dump " .. path .. " 2>/dev/null")
    os.execute("sleep 1")
    -- Verifikasi dump berhasil
    local size = execute_command("stat -c%s " .. path .. " 2>/dev/null")
    return size ~= "" and tonumber(size) > 50
end

-- Simulasi long-press (tahan 1 detik)
local function long_press(x, y)
    os.execute(string.format("input swipe %d %d %d %d 1000", x, y, x, y))
end

-- Konversi app ke freeform via Recent Apps UI
-- Langkah: Recent Apps → long-press icon app → tap "Freeform"
local function convert_to_freeform(package_name)
    print("🪟 [Freeform] Membuka Recent Apps...")
    os.execute("input keyevent 187") -- KEYCODE_APP_SWITCH
    os.execute("sleep 2")
    
    -- Dump UI recent apps
    if not dump_ui("/sdcard/ui_scan.xml") then
        print("❌ [Freeform] Gagal dump UI recent apps")
        return false
    end
    
    -- Cari app di recents: coba content-desc atau text yang mengandung nama app
    local icon_x, icon_y = nil, nil
    
    -- Metode 1: Cari berdasarkan content-desc (biasanya nama app)
    local search_names = {"Roblox", "roblox", "ROBLOX"}
    for _, name in ipairs(search_names) do
        icon_x, icon_y = find_ui_by_desc(name, "/sdcard/ui_scan.xml")
        if icon_x then
            print("🪟 [Freeform] Ditemukan app via content-desc: " .. name)
            break
        end
        icon_x, icon_y = find_ui_by_text(name, "/sdcard/ui_scan.xml")
        if icon_x then
            print("🪟 [Freeform] Ditemukan app via text: " .. name)
            break
        end
    end
    
    -- Metode 2: Cari node dengan package yang cocok (icon kecil)
    if not icon_x then
        local f = io.open("/sdcard/ui_scan.xml", "r")
        if f then
            local content = f:read("*a")
            f:close()
            for node in content:gmatch('<node[^>]+') do
                local pkg = node:match('package="([^"]*)"')
                if pkg == package_name then
                    local cls = node:match('class="([^"]*)"') or ""
                    local l, t, r, b = node:match('bounds="%[(%d+),(%d+)%]%[(%d+),(%d+)%]"')
                    if l then
                        local w = tonumber(r) - tonumber(l)
                        local h = tonumber(b) - tonumber(t)
                        -- Icon biasanya kecil (< 200px)
                        if w < 200 and h < 200 then
                            icon_x = math.floor((tonumber(l) + tonumber(r)) / 2)
                            icon_y = math.floor((tonumber(t) + tonumber(b)) / 2)
                            print("🪟 [Freeform] Ditemukan icon via package match")
                            break
                        end
                    end
                end
            end
        end
    end
    
    if not icon_x then
        print("❌ [Freeform] Tidak dapat menemukan app di recents")
        -- Kembali ke app
        os.execute("input keyevent 4") -- BACK
        return false
    end
    
    -- Long-press pada icon app
    print(string.format("🪟 [Freeform] Long-press pada (%d, %d)...", icon_x, icon_y))
    long_press(icon_x, icon_y)
    os.execute("sleep 2")
    
    -- Dump UI lagi untuk cari menu konteks
    if not dump_ui("/sdcard/ui_scan.xml") then
        print("❌ [Freeform] Gagal dump UI menu konteks")
        os.execute("input keyevent 4") -- BACK
        return false
    end
    
    -- Cari tombol "Freeform" di menu konteks
    local ff_x, ff_y = find_ui_by_text("Freeform", "/sdcard/ui_scan.xml")
    if not ff_x then
        ff_x, ff_y = find_ui_by_text("freeform", "/sdcard/ui_scan.xml")
    end
    if not ff_x then
        ff_x, ff_y = find_ui_by_text("Free form", "/sdcard/ui_scan.xml")
    end
    
    if not ff_x then
        print("❌ [Freeform] Tombol 'Freeform' tidak ditemukan di menu")
        os.execute("input keyevent 4") -- BACK
        return false
    end
    
    -- Tap "Freeform"
    print(string.format("🪟 [Freeform] Tap Freeform pada (%d, %d)!", ff_x, ff_y))
    os.execute(string.format("input tap %d %d", ff_x, ff_y))
    os.execute("sleep 2")
    
    print("✅ [Freeform] Berhasil mengaktifkan mode Freeform!")
    return true
end

-- ==========================================
-- 2. KONFIGURASI DAN CEK ROOT
-- ==========================================
local config_file = "/sdcard/rf_config_lua.txt"

print("==========================================")
print("   RF AUTO FARMING (LUA NATIVE ENGINE)    ")
print("==========================================")

-- Logika Auto-Root (Bypass tsu untuk Redfinger)
if execute_command("id -u") ~= "0" then
    print("🚀 Meminta akses Root via su native...")
    
    local script_path = execute_command("realpath " .. arg[0])
    local termux_bin = "/data/data/com.termux/files/usr/bin"
    
    local cmd = "su -c 'export PATH=$PATH:" .. termux_bin .. " && lua " .. script_path .. "' < /dev/tty"
    
    os.execute(cmd)
    os.exit()
end

if execute_command("whoami") ~= "root" then
    print("❌ Skrip gagal! Wajib dijalankan dalam mode Root.")
    os.exit()
end

local pkg, ps_link, webhook

if arg[1] == "--reset" then
    os.execute("rm -f " .. config_file)
    print("♻️ Konfigurasi berhasil direset!")
    os.exit()
end

local f = io.open(config_file, "r")
if f then
    pkg = f:read("*l")
    ps_link = f:read("*l")
    webhook = f:read("*l")
    f:close()
    print("📂 Konfigurasi dimuat untuk: " .. pkg)
else
    -- ==========================================
    -- 3. SETUP INTERAKTIF
    -- ==========================================
    print("⚙️ SETUP PERTAMA KALI")
    io.write("🔍 Masukkan kata kunci aplikasi (contoh: roblox): ")
    local keyword = io.read()

    print("⏳ Memindai...")
    local pkgs_raw = io.popen("pm list packages | grep -i '" .. keyword .. "' | sed 's/package://g'")
    local pkgs_str = pkgs_raw:read("*a")
    pkgs_raw:close()

    if pkgs_str == nil or pkgs_str == "" then
        print("❌ Tidak ada aplikasi ditemukan.")
        os.exit()
    end

    local pkg_list = {}
    for p in pkgs_str:gmatch("%S+") do
        table.insert(pkg_list, p)
    end

    print("📦 Pilih aplikasi:")
    for i, p in ipairs(pkg_list) do
        print("  [" .. i .. "] " .. p)
    end

    io.write("👉 Ketik nomor pilihan Anda: ")
    local choice = tonumber(io.read())

    if not choice or not pkg_list[choice] then
        print("❌ Pilihan tidak valid.")
        os.exit()
    end
    pkg = pkg_list[choice]

    io.write("\n🔗 Masukkan URL Private Server: ")
    ps_link = io.read()

    io.write("\n💬 Masukkan URL Webhook Discord: ")
    webhook = io.read()

    local out = io.open(config_file, "w")
    out:write(pkg .. "\n" .. ps_link .. "\n" .. webhook .. "\n")
    out:close()
    print("✅ Konfigurasi tersimpan!")
    print("------------------------------------------")
end

print("\n🚀 Memulai Watchdog & Delta Scanner...")


-- Resolve activity sekali di awal
local launch_component = get_launch_activity(pkg)
if launch_component then
    print("📱 Launch component: " .. launch_component)
else
    print("⚠️ Tidak dapat resolve activity, akan gunakan deep link tanpa component.")
end

-- ==========================================
-- 4. MAIN LOOP (WATCHDOG & DEBUG SCANNER)
-- ==========================================
local launch_attempt = 0

while true do
    local pid_result = is_app_running(pkg)

    if pid_result == "" then
        launch_attempt = launch_attempt + 1
        print(string.format("❌ Offline! (Percobaan #%d) Melakukan auto-join ke PS...", launch_attempt))
        
        -- ============================================================
        -- STRATEGI LAUNCH: FULLSCREEN + AUTO-FREEFORM VIA UI
        --
        -- --windowingMode 5 TIDAK BEKERJA di Redfinger.
        -- Freeform hanya bisa diaktifkan via UI manual:
        --   Recent Apps → long-press icon → tap "Freeform"
        --
        -- Solusi: Launch fullscreen + deep link, lalu otomatisasi
        -- proses manual freeform via input + uiautomator
        -- ============================================================
        
        -- Bersihkan state lama
        os.execute("am force-stop " .. pkg .. " 2>/dev/null")
        os.execute("sleep 1")

        local app_started = false

        -- ===== TAHAP 1: Launch fullscreen + deep link (PROVEN) =====
        print("📱 [Tahap 1] Launch fullscreen + deep link ke PS...")
        local start_cmd = string.format(
            "am start -a android.intent.action.VIEW -d '%s' -f 0x10000000 %s 2>&1",
            ps_link, pkg
        )
        print("🔧 [DEBUG] Command: " .. start_cmd)
        local start_result = execute_raw(start_cmd)
        print("🔧 [DEBUG] Result: " .. start_result:gsub("\n", " "))

        -- Tunggu app aktif
        print("⏳ Menunggu app aktif...")
        for i = 1, 15 do
            os.execute("sleep 2")
            local check = is_app_running(pkg)
            if check ~= "" then
                print("✅ App terdeteksi aktif! (PID: " .. check .. ") setelah " .. (i * 2) .. " detik")
                app_started = true
                break
            end
            if i % 5 == 0 then
                print("⏳ Masih menunggu... (" .. (i * 2) .. " detik)")
            end
        end

        -- ===== TAHAP 2: Konversi ke freeform via Recent Apps UI =====
        if app_started then
            print("⏳ Menunggu 5 detik agar app fully loaded...")
            os.execute("sleep 5")
            
            local freeform_ok = convert_to_freeform(pkg)
            if freeform_ok then
                print("🪟 App sekarang berjalan dalam mode Freeform!")
            else
                print("⚠️ Freeform gagal diaktifkan, app tetap berjalan fullscreen.")
            end
        end
        
        -- Jeda sebelum loop berikutnya (beri waktu app untuk loading game)
        print("⏳ Menunggu 15 detik untuk loading game...")
        os.execute("sleep 15")
        
        -- Reset counter jika berhasil
        local final_check = is_app_running(pkg)
        if final_check ~= "" then
            launch_attempt = 0
            print("✅ App berhasil diluncurkan!")
        else
            print("❌ App masih belum terdeteksi. Akan retry di iterasi berikutnya.")
            if launch_attempt >= 5 then
                print("🚨 GAGAL 5x berturut-turut! Mengirim notifikasi Discord...")
                local curl_cmd = string.format(
                    [[curl -s -H "Content-Type: application/json" -X POST -d '{"content": "🚨 **App Gagal Launch!**\nApp `%s` gagal diluncurkan setelah 5 percobaan. Cek manual diperlukan."}' '%s' > /dev/null]],
                    pkg, webhook
                )
                os.execute(curl_cmd)
                launch_attempt = 0
                print("⏳ Cooldown 60 detik sebelum retry...")
                os.execute("sleep 60")
            end
        end
    else
        -- App sedang berjalan
        if launch_attempt > 0 then launch_attempt = 0 end
        
        print("✅ Online (PID: " .. pid_result .. "). Memindai Delta...")
        
        os.execute("rm -f /sdcard/delta_scan.xml")
        print("⏳ [DEBUG] Mengambil dump UI layar...")
        
        os.execute("uiautomator dump /sdcard/delta_scan.xml > /dev/null 2>&1")
        
        local file_size = execute_command("stat -c%s /sdcard/delta_scan.xml 2>/dev/null")
        
        if file_size == "" or tonumber(file_size) < 100 then
            print("❌ [DEBUG] GAGAL! uiautomator tidak dapat membaca layar.")
            os.execute("sleep 15")
        else
            local has_key = execute_command("grep -i 'ENTER KEY' /sdcard/delta_scan.xml")
            
            if has_key ~= "" then
                print("⚠️ DELTA MEMBUTUHKAN KEY! Mengirim ke Discord...")
                
                local curl_cmd = string.format(
                    [[curl -s -H "Content-Type: application/json" -X POST -d '{"content": "🚨 **Delta Butuh Key!**\nSilakan isi manual untuk aplikasi `%s`."}' '%s' > /dev/null]],
                    pkg, webhook
                )
                os.execute(curl_cmd)
                
                print("📨 Notifikasi terkirim. Jeda pemindaian 3 menit...")
                os.execute("sleep 180")
            else
                print("🔍 [DEBUG] Dump berhasil, tapi teks 'ENTER KEY' tidak ditemukan.")
                os.execute("sleep 15")
            end
        end
    end
end
