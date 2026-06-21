#!/bin/bash

# ==========================================
# WARNA KOSMETIK TERMINAL
# ==========================================
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
NC='\e[0m'

CONFIG_FILE="$HOME/kaeru_config.txt"

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}   RF AUTO FARMING (KAERU-LIKE SYSTEM)    ${NC}"
echo -e "${CYAN}==========================================${NC}"

# Mengecek apakah Termux memiliki akses Root di RF
if ! su -c "echo root_ok" > /dev/null 2>&1; then
    echo -e "${RED}❌ Akses Root ditolak. Pastikan Termux diberi izin Root di pengaturan RF.${NC}"
    exit 1
fi

# ==========================================
# FITUR RESET KONFIGURASI (--reset)
# ==========================================
if [ "$1" == "--reset" ]; then
    rm -f "$CONFIG_FILE"
    echo -e "${GREEN}♻️ Konfigurasi berhasil direset! Jalankan ulang skrip untuk setup baru.${NC}"
    exit 0
fi

# ==========================================
# SETUP INTERAKTIF & AUTO-DETECT
# ==========================================
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}📂 Konfigurasi dimuat dari memori!${NC}"
    echo -e "📦 Target: ${YELLOW}$PKG${NC}"
    echo -e "🔗 PS Link: ${YELLOW}$PS_LINK${NC}"
else
    echo -e "${YELLOW}⚙️ SETUP PERTAMA KALI${NC}"
    echo -n -e "🔍 Masukkan kata kunci aplikasi (contoh: roblox): "
    read keyword </dev/tty

    echo -e "⏳ Memindai..."
    # Mengeksekusi pencarian package menggunakan akses root
    pkg_list=$(su -c "pm list packages | grep -i '$keyword' | sed 's/package://g' | tr '\n' ' '")

    if [ -z "$pkg_list" ]; then
        echo -e "${RED}❌ Tidak ada aplikasi yang ditemukan. Dibatalkan.${NC}"
        exit 1
    fi

    # Menjadikan hasil pencarian sebagai Array
    pkg_array=($pkg_list)
    echo -e "📦 Pilih aplikasi untuk dijalankan:"
    for i in "${!pkg_array[@]}"; do
        echo "  [$((i+1))] ${pkg_array[$i]}"
    done

    echo -n -e "👉 Ketik nomor pilihan Anda: "
    read choice </dev/tty

    # Validasi input angka
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#pkg_array[@]}" ]; then
        echo -e "${RED}❌ Pilihan tidak valid.${NC}"
        exit 1
    fi

    PKG="${pkg_array[$((choice-1))]}"
    echo -e "${GREEN}✅ Terpilih: $PKG${NC}"
    
    echo -n -e "\n🔗 Masukkan URL Private Server:\n> "
    read PS_LINK </dev/tty

    echo -n -e "\n💬 Masukkan URL Webhook Discord:\n> "
    read WEBHOOK_URL </dev/tty

    # Menyimpan variabel ke dalam file config di memori Termux
    echo "PKG=\"$PKG\"" > "$CONFIG_FILE"
    echo "PS_LINK=\"$PS_LINK\"" >> "$CONFIG_FILE"
    echo "WEBHOOK_URL=\"$WEBHOOK_URL\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}✅ Konfigurasi tersimpan!${NC}"
    echo "------------------------------------------"
fi

# ==========================================
# MAIN LOOP: WATCHDOG & DELTA SCAN
# ==========================================
echo -e "\n${CYAN}🚀 Memulai Watchdog & Delta Scanner...${NC}"

while true; do
    is_running=$(su -c "pidof $PKG")

    if [ -z "$is_running" ]; then
        echo -e "${RED}❌ [$(date +%H:%M:%S)] Offline! Melakukan auto-join ke PS...${NC}"
        # Injeksi Deep Link PS
        su -c "am start -W -a android.intent.action.VIEW -d '$PS_LINK' $PKG > /dev/null 2>&1"
        echo -e "⏳ Menunggu 20 detik agar game termuat penuh..."
        sleep 20
    else
        echo -e "${GREEN}✅ [$(date +%H:%M:%S)] Online (PID: $is_running). Memindai Delta...${NC}"
        
        # Mengambil layout layar menggunakan UIAutomator (Root)
        su -c "rm -f /sdcard/delta_scan.xml"
        su -c "uiautomator dump /sdcard/delta_scan.xml > /dev/null 2>&1"
        
        # Mengecek keberadaan teks "Get Key"
        has_key=$(su -c "grep -i 'Get Key' /sdcard/delta_scan.xml")
        
        if [ -n "$has_key" ]; then
            echo -e "${YELLOW}⚠️ DELTA MEMBUTUHKAN KEY! Mengirim ke Discord...${NC}"
            
            # Payload Webhook Discord
            curl -s -H "Content-Type: application/json" -X POST \
                 -d '{"content": "🚨 **Delta Butuh Key!**\nAplikasi `'"$PKG"'` di Redfinger sedang menunggu input Key manual."}' \
                 "$WEBHOOK_URL" > /dev/null
                 
            echo -e "${CYAN}📨 Notifikasi terkirim. Menjeda scanner selama 3 menit...${NC}"
            sleep 180
        else
            sleep 15
        fi
    fi
done
