-- ==========================================
-- 1. DEFINISI FUNGSI HARUS DI PALING ATAS
-- ==========================================
local function execute_command(cmd)
    local f = io.popen(cmd)
    local result = f:read("*a")
    f:close()
    return result:gsub("%s+", "")
end

-- ==========================================
-- 2. KONFIGURASI DAN CEK ROOT
-- ==========================================
local config_file = "/sdcard/rf_config_lua.txt"

print("==========================================")
print("   RF AUTO FARMING (LUA NATIVE ENGINE)    ")
print("==========================================")

-- Logika Auto-Root dengan tsu (Single File Approach)
-- Logika Auto-Root (Bypass tsu untuk Redfinger)
if execute_command("id -u") ~= "0" then
    print("🚀 Meminta akses Root via su native...")
    
    local script_path = execute_command("realpath " .. arg[0])
    
    -- Direktori bin Termux tempat 'lua' terinstal
    local termux_bin = "/data/data/com.termux/files/usr/bin"
    
    -- Menggunakan su -c dan mengekspor PATH Termux sebelum memanggil lua
    -- Tetap menggunakan < /dev/tty agar io.read() tidak freeze
    local cmd = "su -c 'export PATH=$PATH:" .. termux_bin .. " && lua " .. script_path .. "' < /dev/tty"
    
    os.execute(cmd)
    os.exit()
end

-- Memblokir jika fallback gagal dan masih belum Root
if execute_command("whoami") ~= "root" then
    print("❌ Skrip gagal! Wajib dijalankan dalam mode Root.")
    print("Pastikan emulator/Redfinger sudah di-root.")
    os.exit()
end

local pkg, ps_link, webhook

-- Fitur Reset (--reset)
if arg[1] == "--reset" then
    os.execute("rm -f " .. config_file)
    print("♻️ Konfigurasi berhasil direset!")
    os.exit()
end

-- Membaca file konfigurasi
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

    -- Menyimpan pengaturan
    local out = io.open(config_file, "w")
    out:write(pkg .. "\n" .. ps_link .. "\n" .. webhook .. "\n")
    out:close()
    print("✅ Konfigurasi tersimpan!")
    print("------------------------------------------")
end

print("\n🚀 Memulai Watchdog & Delta Scanner...")

-- ==========================================
-- 4. MAIN LOOP (WATCHDOG)
-- ==========================================
while true do
    local is_running = execute_command("pidof " .. pkg)

    if is_running == "" then
        print("❌ Offline! Melakukan auto-join ke PS...")
        os.execute("am start -W -a android.intent.action.VIEW -d '" .. ps_link .. "' " .. pkg .. " > /dev/null 2>&1")
        
        -- Memberikan waktu lebih agar proses join selesai sebelum memindai
        os.execute("sleep 20")
    else
        print("✅ Online (PID: " .. is_running .. "). Memindai Delta...")
        
        os.execute("rm -f /sdcard/delta_scan.xml")
        os.execute("uiautomator dump /sdcard/delta_scan.xml > /dev/null 2>&1")
        
        local has_key = execute_command("grep -i 'Get Key' /sdcard/delta_scan.xml")
        
        if has_key ~= "" then
            print("⚠️ DELTA MEMBUTUHKAN KEY! Mengirim ke Discord...")
            
            -- Menyusun perintah curl dengan string format yang aman
            local curl_cmd = string.format(
                [[curl -s -H "Content-Type: application/json" -X POST -d '{"content": "🚨 **Delta Butuh Key!**\nSilakan isi manual untuk aplikasi `%s`."}' '%s' > /dev/null]],
                pkg, webhook
            )
            os.execute(curl_cmd)
            
            print("📨 Notifikasi terkirim. Jeda pemindaian 3 menit...")
            os.execute("sleep 180")
        else
            -- Interval reguler jika aman
            os.execute("sleep 15")
        end
    end
end
