#!/bin/bash

PANEL="${PANEL_DIR:-/var/www/pterodactyl}"
DIR="$PANEL/app/Http/Controllers/Admin/Nests"
MAIN="$DIR/EggController.php"
FILES=(EggController EggShareController EggScriptController EggVariableController)
TS=$(date +%s)
MSG="Akses ditolak! Menu Egg hanya dapat digunakan oleh Admin utama (ID 1)."

echo "🔧 Memperbaiki & mengunci Egg (hanya Admin ID 1)..."

[ -d "$DIR" ] || { echo "❌ Folder tidak ditemukan: $DIR"; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "❌ perl tidak tersedia"; exit 1; }
command -v php >/dev/null 2>&1 || { echo "❌ php tidak tersedia"; exit 1; }

is_broken() {
    [ -f "$1" ] || return 0
    grep -q "KUNCI TOTAL SEMUA REQUEST EGG" "$1" && return 0
    grep -q "StoreEggFormRequest" "$1" && return 0
    grep -q "public function create" "$1" || return 0
    php -l "$1" >/dev/null 2>&1 || return 0
    return 1
}

if is_broken "$MAIN"; then
    echo "⚠️  EggController saat ini rusak, mencari backup asli..."
    FOUND=""
    for B in $(ls -tr "$MAIN".bak_* 2>/dev/null); do
        if ! is_broken "$B"; then FOUND="$B"; break; fi
    done
    if [ -z "$FOUND" ]; then
        echo "❌ Tidak ada backup EggController yang sehat."
        echo "   Ambil file aslinya dari paket panel (Pterodactyl release) lalu taruh di:"
        echo "   $MAIN"
        exit 1
    fi
    [ -f "$MAIN" ] && cp "$MAIN" "$MAIN.broken_$TS"
    cp "$FOUND" "$MAIN"
    echo "♻️  EggController dipulihkan dari: $FOUND"
fi

for N in "${FILES[@]}"; do
    F="$DIR/$N.php"
    [ -f "$F" ] || continue
    cp "$F" "$F.bak_lock_$TS"
done

rollback() {
    for N in "${FILES[@]}"; do
        F="$DIR/$N.php"
        [ -f "$F.bak_lock_$TS" ] && cp "$F.bak_lock_$TS" "$F"
    done
    echo "↩️  Dikembalikan ke kondisi sebelum penguncian."
    exit 1
}

GUARD=$(mktemp)
cat > "$GUARD" <<'PHP'

        // EGG-LOCK
        if (!auth()->check() || (int) auth()->id() !== 1) {
            abort(403, '__MSG__');
        }
PHP
MSG="$MSG" perl -0777 -i -pe 'BEGIN{ $m=$ENV{MSG}; } s/__MSG__/$m/g' "$GUARD"

for N in "${FILES[@]}"; do
    F="$DIR/$N.php"
    [ -f "$F" ] || continue
    if grep -q "EGG-LOCK" "$F"; then
        echo "ℹ️  $N sudah terkunci."
        continue
    fi
    GUARD="$GUARD" perl -0777 -i -pe '
    BEGIN { open(G, "<", $ENV{GUARD}) or die; local $/; $g = <G>; close G; $g =~ s/^\s+//; $g =~ s/\s+\z//; $g = "        " . $g; }
    s/(public\s+function\s+(?!__construct\b)\w+\s*\([^)]*\)(?:\s*:\s*[\\\w|?]+)?\s*\{)/$1\n$g\n/g
    ' "$F"
    if ! grep -q "EGG-LOCK" "$F"; then
        echo "⚠️  $N: tidak ada method yang bisa dikunci."
        continue
    fi
    php -l "$F" >/dev/null 2>&1 || { echo "❌ Syntax PHP error di $N."; php -l "$F"; rm -f "$GUARD"; rollback; }
    echo "🔒 $N terkunci"
done
rm -f "$GUARD"

if [ -f "$PANEL/artisan" ]; then
    cd "$PANEL" || exit 1
    php artisan optimize:clear >/dev/null 2>&1
fi

for s in $(systemctl list-units --type=service --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}'); do
    systemctl reload "$s" >/dev/null 2>&1
done

echo ""
echo "✅ Selesai. Menu Egg (lihat / edit / upload) hanya bisa dipakai Admin ID 1."
echo "🚫 Selain ID 1: ditolak dengan pesan \"$MSG\""
echo ""
echo "Rollback: cp $MAIN.bak_lock_$TS $MAIN"
