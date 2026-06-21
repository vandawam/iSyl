#!/system/bin/sh

echo "========================================="
echo "   AUTO SPLIT ROBLOX (GITHUB LOADER)     "
echo "========================================="

# Meminta kata kunci package (membaca langsung dari input terminal)
printf "🔍 Masukkan awalan/kata kunci package (contoh: com.roblox): "
read keyword </dev/tty

if [ -z "$keyword" ]; then
    echo "❌ Kata kunci kosong. Dibatalkan."
    exit 1
fi

echo "⏳ Memindai package yang cocok..."
# Mengambil daftar package yang terinstal
pkg_list=$(pm list packages | grep -i "$keyword" | sed 's/package://g')

if [ -z "$pkg_list" ]; then
    echo "❌ Tidak ditemukan aplikasi dengan kata '$keyword'."
    exit 1
fi

# Mengubah daftar teks menjadi parameter urut (Array sederhana)
set -- $pkg_list
total=$#

echo "📦 Ditemukan $total aplikasi:"
i=1
for pkg in "$@"; do
    echo "  [$i] $pkg"
    i=$((i+1))
done

echo ""
# Meminta pengguna memilih nomor (bisa pilih banyak sekaligus, pisahkan dengan spasi)
printf "👉 Pilih maksimal 4 nomor aplikasi (pisahkan spasi, contoh: 1 2 3 4): "
read choices </dev/tty

if [ -z "$choices" ]; then
    echo "❌ Pilihan kosong. Dibatalkan."
    exit 1
fi

counter=1
for choice in $choices; do
    # Mencegah membuka lebih dari 4 layar agar sistem tidak crash
    if [ "$counter" -gt 4 ]; then
        echo "⚠️ Batas maksimal 4 aplikasi tercapai. Pilihan sisanya diabaikan."
        break
    fi

    # Mengambil nama package berdasarkan nomor urut yang dipilih
    eval selected_pkg=\${$choice}

    if [ -n "$selected_pkg" ]; then
        echo "🚀 Menyiapkan layar $counter: $selected_pkg"
        
        # Mencari Activity utama secara otomatis
        activity=$(cmd package resolve-activity --brief "$selected_pkg" | tail -n 1)

        if [ -z "$activity" ] || echo "$activity" | grep -q "No activity found"; then
            echo "   ❌ Gagal: Aplikasi ini tidak memiliki antarmuka (UI)."
        else
            # Menentukan posisi layar berdasarkan urutan (Resolusi 720x1280)
            if [ "$counter" -eq 1 ]; then
                bounds="0,0,360,640"      # Kiri Atas
            elif [ "$counter" -eq 2 ]; then
                bounds="360,0,720,640"    # Kanan Atas
            elif [ "$counter" -eq 3 ]; then
                bounds="0,640,360,1280"   # Kiri Bawah
            elif [ "$counter" -eq 4 ]; then
                bounds="360,640,720,1280" # Kanan Bawah
            fi

            echo "   ✅ Membuka $activity..."
            am start --windowingMode 5 --bounds $bounds $activity> /dev/null 2>&1
            
            counter=$((counter+1))
        fi
    else
        echo "❌ Pilihan nomor '$choice' tidak valid."
    fi
done

echo ""
echo "✨ Proses selesai! Semua aplikasi telah diatur posisinya."
