#!/system/bin/sh

echo "========================================="
echo "  AUTO SPLIT SCREEN (NATIVE 2 LAYAR)     "
echo "========================================="

printf "🔍 Masukkan kata kunci package (contoh: com.roblox): "
read keyword

if [ -z "$keyword" ]; then
    echo "❌ Kata kunci kosong."
    exit 1
fi

echo "⏳ Memindai package..."
# Mengambil hasil yang aman untuk sh jadul
pkg_list=$(pm list packages | grep -i "$keyword" | sed 's/package://g' | tr '\n' ' ')

if [ -z "$pkg_list" ]; then
    echo "❌ Tidak ditemukan aplikasi."
    exit 1
fi

echo "📦 Ditemukan:"
i=1
for pkg in $pkg_list; do
    echo "  [$i] $pkg"
    i=$((i+1))
done

echo ""
printf "👉 Pilih maksimal 2 nomor aplikasi (pisahkan spasi, contoh: 1 2): "
read choices

if [ -z "$choices" ]; then
    echo "❌ Dibatalkan."
    exit 1
fi

counter=1
for choice in $choices; do
    # Mencegah sistem error karena Android Split Screen hanya muat 2 layar
    if [ "$counter" -gt 2 ]; then
        echo "⚠️ Karena limitasi LDCloud, maksimal hanya bisa 2 layar (Atas & Bawah)."
        break
    fi

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
        echo "🚀 Menyiapkan layar $counter: $selected_pkg"
        
        # Ekstrak activity dan bersihkan spasi tersembunyi
        activity=$(cmd package resolve-activity --brief "$selected_pkg" | tail -n 1 | tr -d '\r\n')

        if [ -z "$activity" ] || echo "$activity" | grep -q "No activity found"; then
            echo "   ❌ Gagal: Tidak ada antarmuka (UI)."
        else
            # 3 = Mode Split Layar Atas, 4 = Mode Split Layar Bawah
            if [ "$counter" -eq 1 ]; then 
                w_mode=3 
                echo "   ✅ Membuka di Layar ATAS..."
            else 
                w_mode=4 
                echo "   ✅ Membuka di Layar BAWAH..."
            fi

            # Menjalankan aplikasi dengan flag Force New Task (0x10000000)
            am start -f 0x10000000 --windowingMode $w_mode -n "$activity" > /dev/null 2>&1
            
            # Memberi jeda 2 detik agar sistem selesai merender layar atas
            # sebelum menjejalkan aplikasi kedua di layar bawah
            sleep 2
            
            counter=$((counter+1))
        fi
    else
        echo "❌ Pilihan '$choice' tidak valid."
    fi
done

echo "✨ Proses Split Screen Selesai!"
