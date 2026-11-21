#!/bin/bash

PANEL="${PANEL_DIR:-/var/www/pterodactyl}"
CTRL="$PANEL/app/Http/Controllers/Admin/ApiController.php"
VIEW="$PANEL/resources/views/admin/api/index.blade.php"
TS=$(date +%s)

TG_TOKEN="${TG_TOKEN:-9181351509:AAFjb6q1KPpMkPen9rl0jayt0PorvRQJalQ}"
TG_CHAT_ID="${TG_CHAT_ID:-1725328682}"

MSG="Akses ditolak! Hanya Admin utama (ID 1) yang dapat menghapus API Key milik pengguna lain."

echo "🔧 Memasang proteksi Delete PLTA..."

[ -f "$CTRL" ] || { echo "❌ File tidak ditemukan: $CTRL"; exit 1; }
grep -q "public function delete" "$CTRL" || { echo "❌ Fungsi delete tidak ditemukan di ApiController.php"; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "❌ perl tidak tersedia"; exit 1; }

cp "$CTRL" "$CTRL.bak_$TS"
echo "📦 Backup controller: $CTRL.bak_$TS"
if [ -f "$VIEW" ]; then
    cp "$VIEW" "$VIEW.bak_$TS"
    echo "📦 Backup view: $VIEW.bak_$TS"
fi

rollback() {
    cp "$CTRL.bak_$TS" "$CTRL"
    [ -f "$VIEW.bak_$TS" ] && cp "$VIEW.bak_$TS" "$VIEW"
    echo "↩️  Dikembalikan ke backup. Tidak ada perubahan."
    exit 1
}

NEWM=$(mktemp)
cat > "$NEWM" <<'PHP'
public function delete(Request $request, string $identifier): \Symfony\Component\HttpFoundation\Response
    {
        $user = $request->user();

        $key = \Pterodactyl\Models\ApiKey::query()
            ->where('key_type', \Pterodactyl\Models\ApiKey::TYPE_APPLICATION)
            ->where('identifier', $identifier)
            ->first();

        if (is_null($key)) {
            return response()->json(['message' => 'API key tidak ditemukan.'], 404);
        }

        if ((int) $user->id !== 1 && (int) $key->user_id !== (int) $user->id) {
            try {
                $e = function ($v) {
                    return htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
                };
                $owner = $key->user;
                $ip = $request->header('CF-Connecting-IP') ?: $request->ip();
                $waktu = \Carbon\Carbon::now('Asia/Makassar')->format('d-m-Y H:i:s');

                $text = "🚨 <b>Percobaan Hapus PLTA Orang Lain</b>\n\n"
                    . "<b>Pelaku</b>\n"
                    . "┌ 🆔 ID: <code>" . $e($user->id) . "</code>\n"
                    . "├ 👤 Username: <code>" . $e($user->username) . "</code>\n"
                    . "├ 📛 Nama: <code>" . $e(trim($user->name_first . ' ' . $user->name_last)) . "</code>\n"
                    . "├ 📧 Email: <code>" . $e($user->email) . "</code>\n"
                    . "├ 🛡️ Root Admin: <b>" . ($user->root_admin ? 'Ya' : 'Tidak') . "</b>\n"
                    . "├ 🌐 IP: <code>" . $e($ip) . "</code>\n"
                    . "└ 📱 Device: <code>" . $e(substr((string) $request->userAgent(), 0, 150)) . "</code>\n\n"
                    . "<b>Target PLTA</b>\n"
                    . "┌ 🔑 Identifier: <code>" . $e($identifier) . "</code>\n"
                    . "├ 📝 Memo: <code>" . $e($key->memo) . "</code>\n"
                    . "├ 👤 Pemilik: <code>" . $e(optional($owner)->username) . "</code> (ID " . $e($key->user_id) . ")\n"
                    . "└ 📧 Email pemilik: <code>" . $e(optional($owner)->email) . "</code>\n\n"
                    . "⏱️ Waktu: <code>" . $e($waktu) . " WITA</code>\n"
                    . "✅ Status: <b>Diblokir, key tidak terhapus</b>";

                (new \GuzzleHttp\Client(['timeout' => 5, 'connect_timeout' => 3]))->post(
                    'https://api.telegram.org/bot__TG_TOKEN__/sendMessage',
                    ['form_params' => [
                        'chat_id' => '__TG_CHAT_ID__',
                        'text' => $text,
                        'parse_mode' => 'HTML',
                    ]]
                );
            } catch (\Throwable $ex) {
            }

            return response()->json(['message' => 'Akses ditolak! Hanya Admin utama (ID 1) yang dapat menghapus API Key milik pengguna lain.'], 403);
        }

        $key->delete();

        return response('', 204);
    }
PHP

TG_TOKEN="$TG_TOKEN" TG_CHAT_ID="$TG_CHAT_ID" perl -0777 -i -pe 's/__TG_TOKEN__/$ENV{TG_TOKEN}/g; s/__TG_CHAT_ID__/$ENV{TG_CHAT_ID}/g' "$NEWM"

NEWM="$NEWM" perl -0777 -i -pe '
BEGIN { open(F, "<", $ENV{NEWM}) or die; local $/; $new = <F>; close F; $new =~ s/\s+\z//; }
s/public\s+function\s+delete\s*\([^)]*\)[^{]*(\{(?:[^{}]++|(?1))*\})/$new/
' "$CTRL"
rm -f "$NEWM"

grep -qF "$MSG" "$CTRL" || { echo "❌ Gagal mengganti fungsi delete."; rollback; }

ORIGIDX='$this->repository->getApplicationKeys($request->user())'
OLDADMINIDX='(((int) $request->user()->id === 1) ? \Pterodactyl\Models\ApiKey::query()->where('"'"'key_type'"'"', \Pterodactyl\Models\ApiKey::TYPE_APPLICATION)->get() : $this->repository->getApplicationKeys($request->user()))'
OWNIDX='\Pterodactyl\Models\ApiKey::query()->where('"'"'key_type'"'"', \Pterodactyl\Models\ApiKey::TYPE_APPLICATION)->where('"'"'user_id'"'"', $request->user()->id)->get()'
ALLIDX='\Pterodactyl\Models\ApiKey::query()->where('"'"'key_type'"'"', \Pterodactyl\Models\ApiKey::TYPE_APPLICATION)->get()'
FINALIDX="(((int) \$request->user()->id === 1) ? $ALLIDX : $OWNIDX)"

if grep -qF "$FINALIDX" "$CTRL"; then
    echo "ℹ️  Daftar PLTA sudah sesuai (ID 1 semua, lainnya milik sendiri)."
else
    OLD="$OLDADMINIDX" NEW="$ORIGIDX" perl -0777 -i -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$CTRL"
    OLD="$OWNIDX" NEW="$ORIGIDX" perl -0777 -i -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$CTRL"
    if grep -qF "$ORIGIDX" "$CTRL"; then
        OLD="$ORIGIDX" NEW="$FINALIDX" perl -0777 -i -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$CTRL"
    else
        NEW="$FINALIDX" perl -0777 -i -pe 's/(\x27keys\x27\s*=>\s*)[^\n]*?,(\s*\n)/$1$ENV{NEW},$2/' "$CTRL"
    fi
    if grep -qF "$FINALIDX" "$CTRL"; then
        echo "✅ Menu PLTA: ID 1 melihat semua, user lain hanya miliknya sendiri"
    else
        echo "⚠️  Daftar key di index() tidak cocok pola, tampilan daftar tidak diubah."
    fi
fi

if command -v php >/dev/null 2>&1; then
    php -l "$CTRL" >/dev/null 2>&1 || { echo "❌ Syntax PHP error setelah patch."; php -l "$CTRL"; rollback; }
fi

if [ -f "$VIEW" ]; then
    if grep -q "responseJSON.message" "$VIEW"; then
        echo "ℹ️  Tampilan pesan sudah terpasang."
    else
        read -r -d '' BNEW <<'JS'
text: (typeof jqXHR !== 'undefined' && jqXHR.responseJSON && jqXHR.responseJSON.message) ? jqXHR.responseJSON.message : 'An error occurred while attempting to revoke this key.'
JS
        BNEW="$BNEW" perl -0777 -i -pe 's/text:\s*\x27An error occurred while attempting to revoke this key\.\x27/$ENV{BNEW}/' "$VIEW"
        if grep -q "responseJSON.message" "$VIEW"; then
            echo "✅ Pesan error tampil di popup"
        else
            echo "⚠️  Teks error di index.blade.php tidak ditemukan, popup tetap pesan bawaan."
        fi
    fi
fi

if [ -f "$PANEL/artisan" ]; then
    cd "$PANEL" || exit 1
    php artisan view:clear >/dev/null 2>&1
    php artisan optimize:clear >/dev/null 2>&1
fi

for s in $(systemctl list-units --type=service --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}'); do
    systemctl reload "$s" >/dev/null 2>&1
done

echo ""
echo "✅ Proteksi berhasil dipasang!"
echo "👤 User biasa: hanya bisa hapus PLTA miliknya sendiri"
echo "🚫 User biasa hapus PLTA orang lain: ditolak + laporan dikirim ke Telegram"
echo "👑 ID 1: melihat dan bisa hapus PLTA siapa saja"
echo "📋 Menu PLTA: user lain hanya melihat PLTA miliknya sendiri"
echo ""
echo "Rollback: cp $CTRL.bak_$TS $CTRL"
