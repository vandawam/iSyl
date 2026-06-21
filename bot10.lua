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

-- Aktifkan freeform support sekali di awal (butuh reboot pada beberapa ROM)
os.execute("settings put global enable_freeform_support 1 2>/dev/null")
os.execute("settings put global force_resizable_activities 1 2>/dev/null")

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
        -- STRATEGI LAUNCH: FREEFORM LANGSUNG SAAT AM START
        -- Metode paling reliable: --windowingMode 5 + component name
        -- Fallback: launch biasa jika freeform gagal
        -- ============================================================
        
        -- Bersihkan state lama
        os.execute("am force-stop " .. pkg .. " 2>/dev/null")
        os.execute("sleep 1")

        -- Ambil resolusi layar untuk log
        local wm_raw = execute_raw("wm size 2>/dev/null")
        local w_str, h_str = wm_raw:match("(%d+)x(%d+)")
        if w_str and h_str then
            print(string.format("📐 Resolusi layar: %sx%s", w_str, h_str))
        end

        local app_started = false

        -- ===== METODE 1: Launch freeform via component name =====
        -- --windowingMode 5 HARUS digunakan bersama component (-n pkg/activity)
        -- Ini satu-satunya cara yang reliable dari shell
        if launch_component then
            print("🪟 [Metode 1] Launch freeform via component name...")
            local start_cmd = string.format(
                "am start --windowingMode 5 -n %s -a android.intent.action.VIEW -d '%s' 2>&1",
                launch_component, ps_link
            )
            print("🔧 [DEBUG] Command: " .. start_cmd)
            local start_result = execute_raw(start_cmd)
            print("🔧 [DEBUG] Result: " .. start_result:gsub("\n", " "))

            -- Cek apakah launch berhasil (bukan error)
            if not start_result:find("Error") then
                -- Polling tunggu app aktif (max 30 detik)
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
            else
                print("⚠️ Metode 1 gagal, mencoba metode berikutnya...")
            end
        end

        -- ===== METODE 2: Launch freeform via package name =====
        if not app_started then
            print("🪟 [Metode 2] Launch freeform via package name...")
            local start_cmd = string.format(
                "am start --windowingMode 5 -a android.intent.action.VIEW -d '%s' -f 0x10000000 %s 2>&1",
                ps_link, pkg
            )
            print("🔧 [DEBUG] Command: " .. start_cmd)
            local start_result = execute_raw(start_cmd)
            print("🔧 [DEBUG] Result: " .. start_result:gsub("\n", " "))

            print("⏳ Menunggu app aktif...")
            for i = 1, 10 do
                os.execute("sleep 2")
                local check = is_app_running(pkg)
                if check ~= "" then
                    print("✅ App terdeteksi aktif! (PID: " .. check .. ") setelah " .. (i * 2) .. " detik")
                    app_started = true
                    break
                end
            end
        end

        -- ===== METODE 3: Fallback launch biasa (tanpa freeform) =====
        if not app_started then
            print("📱 [Metode 3] Fallback: launch biasa tanpa freeform...")
            local start_cmd = string.format(
                "am start -a android.intent.action.VIEW -d '%s' -f 0x10000000 %s 2>&1",
                ps_link, pkg
            )
            print("🔧 [DEBUG] Command: " .. start_cmd)
            local start_result = execute_raw(start_cmd)
            print("🔧 [DEBUG] Result: " .. start_result:gsub("\n", " "))

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
        end

        -- ===== POST-LAUNCH: Coba pindahkan ke freeform jika masih fullscreen =====
        if app_started then
            -- Cek apakah app sudah dalam freeform atau masih fullscreen
            local stack_raw = execute_raw("am stack list 2>/dev/null")
            local task_id = nil
            -- Cari task yang mengandung package name
            for line in stack_raw:gmatch("[^\n]+") do
                if line:find(pkg) then
                    task_id = line:match("taskId=(%d+)")
                    if task_id then break end
                end
            end
            
            if task_id then
                -- Cek windowing mode saat ini
                local mode_info = execute_raw("am stack info " .. task_id .. " 2>&1")
                local current_mode = mode_info:match("mWindowingMode=(%d+)")
                
                if current_mode == "5" then
                    print("🪟 ✅ App sudah berjalan dalam mode Freeform!")
                elseif current_mode then
                    print("🪟 App dalam mode " .. current_mode .. ", mencoba pindah ke freeform...")
                    -- Coba pindahkan ke freeform stack
                    os.execute("am stack set-windowing-mode " .. task_id .. " 5 2>/dev/null")
                    os.execute("sleep 1")
                    -- Verifikasi
                    mode_info = execute_raw("am stack info " .. task_id .. " 2>&1")
                    current_mode = mode_info:match("mWindowingMode=(%d+)")
                    if current_mode == "5" then
                        print("🪟 ✅ Berhasil pindah ke Freeform!")
                    else
                        print("⚠️ Freeform tidak didukung di perangkat ini, app berjalan fullscreen.")
                    end
                else
                    print("ℹ️ Tidak dapat membaca windowing mode, app berjalan dengan mode default.")
                end
            else
                print("ℹ️ Task ID tidak ditemukan, app berjalan dengan mode default.")
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
