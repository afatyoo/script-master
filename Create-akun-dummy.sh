#!/usr/bin/env bash
# /root/create-carbonio-accounts.sh
# Jalankan sebagai root. Membuat 10 akun Carbonio dan menyimpan kredensial ke /root/carbonio-new-accounts.txt
set -euo pipefail

OUTFILE="/root/carbonio-new-accounts.txt"
DOMAIN="afatyo.id"

# Daftar "nama orang" (ubah jika mau)
usernames=(
  "ahmad.pratama"
  "siti.latifah"
  "muhammad.afatyo"
  "lina.ayu"
  "agus.supriadi"
  "dwi.kurnia"
  "budi.santoso"
  "rina.sari"
  "tino.arzaq"
  "lili.nur"
)

# Fungsi buat password random (12 karakter alfanumerik)
generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 12
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12
  fi
}

# Inisialisasi file output (backup jika ada)
if [[ -f "$OUTFILE" ]]; then
  cp -p "$OUTFILE" "${OUTFILE}.bak.$(date +%Y%m%d%H%M%S)"
fi
: > "$OUTFILE"
chmod 600 "$OUTFILE"

echo "--------------------------------------------------" >> "$OUTFILE"
echo "Created accounts - $(date -u +"%Y-%m-%d %H:%M:%SZ")" >> "$OUTFILE"
echo "--------------------------------------------------" >> "$OUTFILE"

echo "Mulai membuat ${#usernames[@]} akun Carbonio..."
for u in "${usernames[@]}"; do
  email="${u}@${DOMAIN}"
  pw="$(generate_password)"
  echo -n "Membuat $email ... "

  # Jalankan perintah provisioning sebagai user zextras
  if su - zextras -c "carbonio prov ca ${email} ${pw}"; then
    echo "OK"
    echo "${email} ${pw}" >> "$OUTFILE"
  else
    echo "GAGAL"
    echo "${email} FAILED" >> "$OUTFILE"
  fi
done

echo "--------------------------------------------------" >> "$OUTFILE"
echo "Selesai pada: $(date -u +"%Y-%m-%d %H:%M:%SZ")" >> "$OUTFILE"
echo "File kredensial: $OUTFILE (mode 600)"
echo "Selesai bro!"
