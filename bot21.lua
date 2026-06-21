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
    -- Ambil resolusi layar
    local wm_raw = execute_raw("wm size 2>/dev/null")
    local sw, sh = wm_raw:match("(%d+)x(%d+)")
    local screen_w = tonumber(sw) or 720
    local screen_h = tonumber(sh) or 1280
    
    print("🪟 [Freeform] Membuka Recent Apps...")
    os.execute("input keyevent 187") -- KEYCODE_APP_SWITCH
    
    -- Tunggu animasi recents selesai (3 detik)
    os.execute("sleep 3")
    
    -- Dump UI recent apps (dengan retry)
    local dump_ok = false
    for attempt = 1, 3 do
        print(string.format("🪟 [Freeform] Dump UI attempt %d/3...", attempt))
        os.execute("rm -f /sdcard/ui_scan.xml")
        os.execute("uiautomator dump /sdcard/ui_scan.xml 2>/dev/null")
        os.execute("sleep 2")
        
        local size = execute_command("stat -c%s /sdcard/ui_scan.xml 2>/dev/null")
        if size ~= "" and tonumber(size) > 50 then
            dump_ok = true
            print("🪟 [Freeform] Dump berhasil! (size: " .. size .. " bytes)")
            break
        else
            print("🪟 [Freeform] Dump gagal/kosong (size: " .. (size ~= "" and size or "0") .. ")")
            if attempt < 3 then
                os.execute("sleep 2")
            end
        end
    end
    
    local icon_x, icon_y = nil, nil
    
    -- ===== CARI ICON APP VIA UIAUTOMATOR =====
    if dump_ok then
        -- Debug: print isi dump untuk analisis
        local dump_preview = execute_raw("head -c 500 /sdcard/ui_scan.xml 2>/dev/null")
        print("🪟 [DEBUG] Dump preview: " .. dump_preview:gsub("\n", ""):sub(1, 200))
        
        -- Coba cari app via text/desc
        local search_names = {"Roblox", "roblox", "ROBLOX"}
        for _, name in ipairs(search_names) do
            icon_x, icon_y = find_ui_by_desc(name, "/sdcard/ui_scan.xml")
            if icon_x then
                print("🪟 [Freeform] Ditemukan via content-desc: " .. name)
                break
            end
            icon_x, icon_y = find_ui_by_text(name, "/sdcard/ui_scan.xml")
            if icon_x then
                print("🪟 [Freeform] Ditemukan via text: " .. name)
                break
            end
        end
        
        -- Coba cari via package name (icon kecil)
        if not icon_x then
            local f = io.open("/sdcard/ui_scan.xml", "r")
            if f then
                local content = f:read("*a")
                f:close()
                for node in content:gmatch('<node[^>]+') do
                    local pkg = node:match('package="([^"]*)"')
                    if pkg == package_name then
                        local l, t, r, b = node:match('bounds="%[(%d+),(%d+)%]%[(%d+),(%d+)%]"')
                        if l then
                            local w = tonumber(r) - tonumber(l)
                            local h = tonumber(b) - tonumber(t)
                            if w < 200 and h < 200 then
                                icon_x = math.floor((tonumber(l) + tonumber(r)) / 2)
                                icon_y = math.floor((tonumber(t) + tonumber(b)) / 2)
                                print("🪟 [Freeform] Ditemukan icon via package")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- ===== FALLBACK: KOORDINAT PERKIRAAN =====
    -- Jika uiautomator gagal (sering terjadi di recents karena SurfaceView),
    -- gunakan posisi perkiraan berdasarkan resolusi layar.
    -- Di recents, app terakhir ada di tengah. Icon biasanya di kiri atas card.
    if not icon_x then
        print("🪟 [Freeform] Dump tidak menemukan icon, menggunakan posisi perkiraan...")
        -- Pada layar 720x1280, recents card biasanya:
        -- - Lebar: ~90% layar, centered
        -- - Icon app: kiri atas card, ~60px dari kiri, ~200px dari atas
        -- Skala proporsional untuk resolusi lain
        icon_x = math.floor(screen_w * 0.12)  -- ~86px pada 720
        icon_y = math.floor(screen_h * 0.17)  -- ~218px pada 1280
        print(string.format("🪟 [Freeform] Posisi perkiraan icon: (%d, %d)", icon_x, icon_y))
    end
    
    -- Long-press pada icon app
    print(string.format("🪟 [Freeform] Long-press pada (%d, %d)...", icon_x, icon_y))
    long_press(icon_x, icon_y)
    os.execute("sleep 2")
    
    -- Cari tombol "Freeform" di menu konteks
    local ff_x, ff_y = nil, nil
    
    -- Coba dump UI menu konteks
    os.execute("rm -f /sdcard/ui_scan.xml")
    os.execute("uiautomator dump /sdcard/ui_scan.xml 2>/dev/null")
    os.execute("sleep 1")
    
    local menu_size = execute_command("stat -c%s /sdcard/ui_scan.xml 2>/dev/null")
    if menu_size ~= "" and tonumber(menu_size) > 50 then
        print("🪟 [Freeform] Menu konteks dump berhasil!")
        
        -- Debug: print isi menu
        local menu_preview = execute_raw("head -c 500 /sdcard/ui_scan.xml 2>/dev/null")
        print("🪟 [DEBUG] Menu preview: " .. menu_preview:gsub("\n", ""):sub(1, 200))
        
        ff_x, ff_y = find_ui_by_text("Freeform", "/sdcard/ui_scan.xml")
        if not ff_x then
            ff_x, ff_y = find_ui_by_text("freeform", "/sdcard/ui_scan.xml")
        end
        if not ff_x then
            ff_x, ff_y = find_ui_by_text("Free form", "/sdcard/ui_scan.xml")
        end
    end
    
    -- Fallback: posisi perkiraan "Freeform" di menu konteks
    -- Berdasarkan screenshot user: menu muncul centered,
    -- "App info" di atas, "Split screen" di tengah, "Freeform" di bawah
    -- Setiap item ~70px tinggi, menu mulai ~50px di bawah titik long-press
    if not ff_x then
        print("🪟 [Freeform] Menggunakan posisi perkiraan untuk 'Freeform'...")
        -- Menu konteks centered horizontal, Freeform = item ke-3
        ff_x = math.floor(screen_w / 2)  -- centered: 360 pada 720
        -- Dari screenshot: Freeform berada ~190px di bawah posisi icon
        -- (title ~40px + App info ~70px + Split screen ~70px + offset ~10px)
        ff_y = icon_y + math.floor(screen_h * 0.20)  -- ~256px offset pada 1280
        print(string.format("🪟 [Freeform] Posisi perkiraan Freeform: (%d, %d)", ff_x, ff_y))
    end
    
    -- Tap "Freeform"
    print(string.format("🪟 [Freeform] Tap Freeform pada (%d, %d)!", ff_x, ff_y))
    os.execute(string.format("input tap %d %d", ff_x, ff_y))
    os.execute("sleep 2")
    
    print("✅ [Freeform] Perintah freeform dikirim!")
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
        -- STRATEGI LAUNCH: 2-STEP FREEFORM LAUNCH (Sesuai alur asli)
        -- 
        -- Terinspirasi dari metode script kaeru.lua, kita gunakan 2 tahap:
        -- ============================================================
        -- STRATEGI LAUNCH: JAVA REFLECTION HELPER (Ultimate Method)
        -- 
        -- Menggunakan file DEX terkompilasi dari FreeformLauncher.java
        -- untuk memicu ActivityOptions.setLaunchWindowingMode(5)
        -- Ini adalah metode yang sama persis digunakan oleh kaeru.lua dan Taskbar!
        -- ============================================================
        
        -- Bersihkan state lama
        os.execute("am force-stop " .. pkg .. " 2>/dev/null")
        os.execute("sleep 1")

        -- ===== PERBAIKAN FATAL: MENGAKTIFKAN FREEFORM DI LEVEL SISTEM =====
        -- Terkadang emulator me-reset flag ini, jadi kita harus paksa aktif setiap saat
        os.execute("settings put global enable_freeform_support 1")
        os.execute("settings put global force_resizable_activities 1")
        os.execute("settings put global enable_non_resizable_multi_window 1")
        
        -- Pindahkan Termux ke Freeform Mode (Opsional namun sangat disarankan)
        -- Jika Termux Fullscreen, ia akan terus menekan Roblox ke background!
        print("🪟 Memastikan Workspace Desktop aktif...")
        os.execute("am start --windowingMode 5 -n com.termux/com.termux.app.TermuxActivity 2>/dev/null")
        os.execute("sleep 2")

        local app_started = false
        local freeform_jar_path = "/data/local/tmp/freeform.jar"
        local b64_path = "/data/local/tmp/freeform_b64.txt"
        
        -- Hapus helper lama (Wajib dilakukan agar base64 yang baru selalu tertulis!)
        os.execute("rm -f " .. freeform_jar_path)
        
        print("📦 Mengekstrak Java Helper untuk Freeform...")
        local b64 = [[
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AAwAbiAOAAwAKCENDGIAAQAiAQ8AcBAZAAEAGgIEAG4gGwAhAAwBbhASAAwADAJuIBsAIQAMAW4QHAABAAwBbiAOABAAbhATAAwADgAYAAAAMAABAEkAAAAeAAUAaQAAABoACACHAAAAAQABAI8AAAAUAAwApgAAAJAAAQAEAQu3AgELaAELhAEBC6QBCQAOAAsBAA6HPjyKh3h4THhaPVtN0rR+AnodH8M8wy8eiIdpeC7DhwEwETxph2qHiHgBHhMaHgEcDz0AAQAAAA4AAAABAAAABQAAAAEAAAAAAAAAAQAAAAYAAAACAAAADQAVAAIAAAAOABQABAAAAAAAAAAAAAAAAgAAAAQABwABAAAAEwAAAAEAAAAWABogbGF1bmNoZWQgaW4gZnJlZWZvcm0gbW9kZQABLAAGPGluaXQ+AAZET05FOiAAB0VSUk9SOiAAFUZyZWVmb3JtTGF1bmNoZXIuamF2YQABSQACSUwAAUwAEkxGcmVlZm9ybUxhdW5jaGVyOwACTEkAAkxMAANMTEwAHUxhbmRyb2lkL2FwcC9BY3Rpdml0eU9wdGlvbnM7ABlMYW5kcm9pZC9jb250ZW50L0NvbnRleHQ7ABhMYW5kcm9pZC9jb250ZW50L0ludGVudDsAF0xhbmRyb2lkL2dyYXBoaWNzL1JlY3Q7ABFMYW5kcm9pZC9uZXQvVXJpOwATTGFuZHJvaWQvb3MvQnVuZGxlOwATTGFuZHJvaWQvb3MvTG9vcGVyOwAVTGphdmEvaW8vUHJpbnRTdHJlYW07ABFMamF2YS9sYW5nL0NsYXNzOwAVTGphdmEvbGFuZy9FeGNlcHRpb247ABNMamF2YS9sYW5nL0ludGVnZXI7ABJMamF2YS9sYW5nL09iamVjdDsAEkxqYXZhL2xhbmcvU3RyaW5nOwAZTGphdmEvbGFuZy9TdHJpbmdCdWlsZGVyOwASTGphdmEvbGFuZy9TeXN0ZW07ABpMamF2YS9sYW5nL3JlZmxlY3QvTWV0aG9kOwALT0s6IGJvdW5kcz0AIU9LOiBzZXRMYXVuY2hXaW5kb3dpbmdNb2RlKDUpIHNldAAEVFlQRQABVgACVkkABVZJSUlJAAJWTAADVkxMAAJWWgABWgASW0xqYXZhL2xhbmcvQ2xhc3M7ABNbTGphdmEvbGFuZy9PYmplY3Q7ABNbTGphdmEvbGFuZy9TdHJpbmc7AAthZGRDYXRlZ29yeQAIYWRkRmxhZ3MAGmFuZHJvaWQuYXBwLkFjdGl2aXR5VGhyZWFkABphbmRyb2lkLmludGVudC5hY3Rpb24uTUFJTgAaYW5kcm9pZC5pbnRlbnQuYWN0aW9uLlZJRVcAIGFuZHJvaWQuaW50ZW50LmNhdGVnb3J5LkxBVU5DSEVSAAZhcHBlbmQABGV4aXQAB2Zvck5hbWUAEWdldERlY2xhcmVkTWV0aG9kAApnZXRNZXNzYWdlAAlnZXRNZXRob2QAEGdldFN5c3RlbUNvbnRleHQABmludm9rZQAHaXNFbXB0eQAEbWFpbgAJbWFrZUJhc2ljAANvdXQABXBhcnNlAAhwYXJzZUludAARcHJlcGFyZU1haW5Mb29wZXIAD3ByaW50U3RhY2tUcmFjZQAHcHJpbnRsbgANc2V0QWNjZXNzaWJsZQAHc2V0RGF0YQAPc2V0TGF1bmNoQm91bmRzABZzZXRMYXVuY2hXaW5kb3dpbmdNb2RlAApzZXRQYWNrYWdlAAVzcGxpdAANc3RhcnRBY3Rpdml0eQAKc3lzdGVtTWFpbgAIdG9CdW5kbGUACHRvU3RyaW5nAAd2YWx1ZU9mAAF4AGZ+fkQ4eyJiYWNrZW5kIjoiZGV4IiwiY29tcGlsYXRpb24tbW9kZSI6ImRlYnVnIiwiaGFzLWNoZWNrc3VtcyI6ZmFsc2UsIm1pbi1hcGkiOjI2LCJ2ZXJzaW9uIjoiOC44LjE5In0AAAACAACBgATUCAEJ7AgADQAAAAAAAAABAAAAAAAAAAEAAABOAAAAcAAAAAIAAAAXAAAAqAEAAAMAAAAYAAAABAIAAAQAAAACAAAAJAMAAAUAAAAgAAAANAMAAAYAAAABAAAANAQAAAEgAAACAAAAVAQAAAMgAAACAAAAbAcAAAEQAAAKAAAAqAcAAAIgAABOAAAA+gcAAAAgAAABAAAAtQwAAAAQAAABAAAAxAwAAFBLAQIUABQAAAAAAMRx1VzVSw6zZA0AAGQNAAALAAAAAAAAAAAAAAC2gQAAAABjbGFzc2VzLmRleFBLBQYAAAAAAQABADkAAACNDQAAAAA=]]
            local f = io.open(b64_path, "w")
            if f then
                f:write(b64)
                f:close()
                os.execute("base64 -d " .. b64_path .. " > " .. freeform_jar_path)
                os.execute("rm " .. b64_path)
                os.execute("chmod 777 " .. freeform_jar_path)
                print("✅ Java Helper berhasil diekstrak ke " .. freeform_jar_path)
            else
                print("❌ Gagal menulis helper ke storage.")
            end

        -- ===== TAHAP 1: Launch Freeform Window via Java =====
        print("📱 [Launch] Membuka window Freeform via Java Helper...")
        local cmd1 = string.format(
            "CLASSPATH=%s app_process / FreeformLauncher %s '%s' 720x1280 2>&1",
            freeform_jar_path, pkg, ps_link
        )
        print("🔧 [DEBUG] Command 1: " .. cmd1)
        local result1 = execute_raw(cmd1)
        print("🔧 [DEBUG] Result 1: " .. result1:gsub("\n", " "))

        -- Tunggu app aktif sebentar
        print("⏳ Menunggu app aktif...")
        for i = 1, 5 do
            os.execute("sleep 2")
            if is_app_running(pkg) ~= "" then
                app_started = true
                break
            end
        end

        if app_started then
            print("🪟 Window Freeform terdeteksi (PID: " .. is_app_running(pkg) .. ")")
            
            -- ===== TAHAP 2: Inject Deep Link (Private Server) =====
            print("📱 [Tahap 2] Mengirim deep link ke window aktif...")
            local cmd2 = string.format(
                "am start -a android.intent.action.VIEW -d '%s' -f 0x10000000 %s 2>&1",
                ps_link, pkg
            )
            print("🔧 [DEBUG] Command 2: " .. cmd2)
            execute_raw(cmd2)
            
            print("✅ Inject selesai! App seharusnya sekarang masuk ke Private Server.")
        else
            print("❌ Gagal memunculkan window di Tahap 1.")
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
            local has_key = execute_command("grep -i 'Enter_Key' /sdcard/delta_scan.xml")
            
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
