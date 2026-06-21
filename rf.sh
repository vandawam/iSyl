#!/system/bin/sh

echo "========================================="
echo "   AUTO SPLIT ROBLOX (GITHUB LOADER)     "
echo "========================================="

printf "🔍 Masukkan kata kunci package: "
read keyword

if [ -z "$keyword" ]; then
    echo "❌ Kata kunci kosong."
    exit 1
fi

echo "⏳ Memindai package..."
# Menyimpan hasil ke dalam variabel dengan memisahkan baris menjadi spasi
pkg_list=$(pm list packages | grep -i "$keyword" | sed 's/package://g' | tr '\n' ' ')

if [ -z "$pkg_list" ]; then
    echo "❌ Tidak ditemukan aplikasi."
    exit 1
fi

echo "📦 Ditemukan:"
i=1
# Looping standar yang aman untuk sh
for pkg in $pkg_list; do
    echo "  [$i] $pkg"
    i=$((i+1))
done

echo ""
printf "👉 Pilih nomor aplikasi (maksimal 4, pisahkan dengan spasi): "
read choices

if [ -z "$choices" ]; then
    echo "❌ Dibatalkan."
    exit 1
fi

counter=1
for choice in $choices; do
    if [ "$counter" -gt 4 ]; then
        echo "⚠️ Maksimal 4 layar."
        break
    fi

    # Teknik pencarian array manual yang 100% aman untuk sh jadul
    current_idx=1
    selected_pkg=""
    for pkg in $pkg_list; do
        if [ "$current_idx" -eq "$choice" ]; then
            selected_pkg="$pkg"
            break
        fi
        current_idx=$((current_idx+1))
    done

    if [ -n "$selected_pkg" ]; then
        echo "🚀 Layar $counter: $selected_pkg"
        
        activity=$(cmd package resolve-activity --brief "$selected_pkg" | tail -n 1)

        if [ -z "$activity" ] || echo "$activity" | grep -q "No activity found"; then
            echo "   ❌ Gagal: Tidak ada UI."
        else
            if [ "$counter" -eq 1 ]; then bounds="0,0,360,640"
            elif [ "$counter" -eq 2 ]; then bounds="360,0,720,640"
            elif [ "$counter" -eq 3 ]; then bounds="0,640,360,1280"
            elif [ "$counter" -eq 4 ]; then bounds="360,640,720,1280"
            fi

            echo "   ✅ Membuka $activity..."
            am start --windowingMode 5 --bounds $bounds $activity > /dev/null 2>&1
            counter=$((counter+1))
        fi
    else
        echo "❌ Pilihan '$choice' tidak valid."
    fi
done

echo "✨ Selesai!"
