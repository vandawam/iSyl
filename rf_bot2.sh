#!/bin/bash

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
NC='\e[0m'

CONFIG_FILE="/sdcard/kaeru_config.txt"

# Memblokir eksekusi jika pengguna belum masuk mode Root
if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}❌ Skrip gagal dijalankan!${NC}"
    echo -e "Skrip ini wajib dijalankan di dalam mode Root."
    echo -e "Ketik perintah: ${YELLOW}su${NC} lalu tekan Enter, kemudian jalankan ulang skrip ini."
    exit 1
fi

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}   RF AUTO FARMING (NATIVE ROOT)          ${NC}"
echo -e "${CYAN}==========================================${NC}"

if [ "$1" == "--reset" ]; then
    rm -f "$CONFIG_FILE"
    echo -e "${GREEN}♻️ Konfigurasi berhasil direset!${NC}"
    exit 0
fi

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}📂 Konfigurasi dimuat dari memori!${NC}"
else
    echo -e "${YELLOW}⚙️ SETUP PERTAMA KALI${NC}"
    echo -e "🔍 Masukkan kata kunci aplikasi (contoh: roblox):"
    read keyword

    echo -e "⏳ Memindai..."
    pkg_list=$(pm list packages | grep -i "$keyword" | sed 's/package://g' | tr '\n' ' ')

    if [ -z "$pkg_list" ]; then
        echo -e "${RED}❌ Tidak ada aplikasi ditemukan.${NC}"
        exit 1
    fi

    pkg_array=($pkg_list)
    echo -e "📦 Pilih aplikasi untuk dijalankan:"
    for i in "${!pkg_array[@]}"; do
        echo "  [$((i+1))] ${pkg_array[$i]}"
    done

    echo -e "👉 Ketik nomor pilihan Anda:"
    read choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#pkg_array[@]}" ]; then
        echo -e "${RED}❌ Pilihan tidak valid.${NC}"
        exit 1
    fi

    PKG="${pkg_array[$((choice-1))]}"
    
    echo -e "\n🔗 Masukkan URL Private Server:"
    read PS_LINK

    echo -e "\n💬 Masukkan URL Webhook Discord:"
    read WEBHOOK_URL

    echo "PKG=\"$PKG\"" > "$CONFIG_FILE"
    echo "PS_LINK=\"$PS_LINK\"" >> "$CONFIG_FILE"
    echo "WEBHOOK_URL=\"$WEBHOOK_URL\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}✅ Konfigurasi tersimpan!${NC}"
    echo "------------------------------------------"
fi

echo -e "\n${CYAN}🚀 Memulai Watchdog & Delta Scanner...${NC}"

while true; do
    is_running=$(pidof "$PKG")

    if [ -z "$is_running" ]; then
        echo -e "${RED}❌ [$(date +%H:%M:%S)] Offline! Melakukan auto-join ke PS...${NC}"
        am start -W -a android.intent.action.VIEW -d "$PS_LINK" "$PKG" > /dev/null 2>&1
        sleep 20
    else
        echo -e "${GREEN}✅ [$(date +%H:%M:%S)] Online. Memindai Delta...${NC}"
        
        rm -f /sdcard/delta_scan.xml
        uiautomator dump /sdcard/delta_scan.xml > /dev/null 2>&1
        
        if grep -iq 'Get Key' /sdcard/delta_scan.xml; then
            echo -e "${YELLOW}⚠️ DELTA MEMBUTUHKAN KEY! Mengirim ke Discord...${NC}"
            curl -s -H "Content-Type: application/json" -X POST -d '{"content": "🚨 **Delta Butuh Key!**\nSilakan isi manual untuk aplikasi `'"$PKG"'`."}' "$WEBHOOK_URL" > /dev/null
            sleep 180
        else
            sleep 15
        fi
    fi
done
