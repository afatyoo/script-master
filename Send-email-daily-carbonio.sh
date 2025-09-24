#!/usr/bin/env bash
# /root/send_daily_emails_from_zmprov.sh
# Ambil daftar akun dari zmprov, filter beberapa kata, dan kirim ~100 email/hari per akun menggunakan swaks.
# Direkomendasikan dijalankan tiap jam via cron: 0 * * * * /root/send_daily_emails_from_zmprov.sh
set -euo pipefail

# ========== CONFIG ==========
ACCOUNTS_CMD='su - zextras -c "zmprov -l gaa"'   # command to list accounts
EXCLUDE_REGEX='virus|ham|spam|galsync'           # case-insensitive substrings to exclude
STATE_DIR="/var/tmp"
LOGFILE="/var/log/carbonio_send_from_zmprov.log"
DOMAIN_FROM="zextras@afatyo.id"                  # From header used with swaks
TARGET_PER_DAY=100
DRY_RUN="${DRY_RUN:-0}"                          # set DRY_RUN=1 to test without sending
SWAKS_CMD="${SWAKS_CMD:-/usr/bin/swaks}"        # path to swaks
SWAKS_SERVER="${SWAKS_SERVER:-localhost}"       # smtp server
MAX_PER_RUN_CAP=50                               # safety cap per run per account
# ===========================

DATE_STR="$(date +%F)"
STATE_FILE="${STATE_DIR}/carbonio_email_counts_${DATE_STR}.db"
TMP_STATE="${STATE_FILE}.tmp.$$"

mkdir -p "$(dirname "$STATE_FILE")"
touch "$LOGFILE"
chmod 640 "$LOGFILE"

log() {
  echo "[$(date +'%F %T')] $*" | tee -a "$LOGFILE"
}

# ensure swaks exists unless dry run
if [[ "$DRY_RUN" != "1" ]] && ! command -v "$SWAKS_CMD" >/dev/null 2>&1; then
  log "ERROR: swaks tidak ditemukan di $SWAKS_CMD. Install swaks atau set SWAKS_CMD."
  exit 1
fi

# === Get account list from zmprov and filter ===
log "Mengambil daftar akun via zmprov..."
# run command and filter lines that look like emails and do not match exclude regex
mapfile -t ACC_LINES < <(eval $ACCOUNTS_CMD 2>/dev/null | \
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | \
  grep -Ei "@" || true)

if [[ ${#ACC_LINES[@]} -eq 0 ]]; then
  log "ERROR: tidak ada akun yang dikembalikan oleh zmprov."
  exit 1
fi

# apply exclusion (case-insensitive)
filtered=()
for a in "${ACC_LINES[@]}"; do
  # skip blank and lines that don't look like email
  if [[ -z "$a" ]]; then
    continue
  fi
  if [[ ! "$a" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+ ]]; then
    # sometimes zmprov output may include extra text; skip non-email tokens
    continue
  fi
  if echo "$a" | grep -Eiq "$EXCLUDE_REGEX"; then
    log "Skip (excluded by pattern) -> $a"
    continue
  fi
  filtered+=("$a")
done

if [[ ${#filtered[@]} -eq 0 ]]; then
  log "ERROR: semua akun di-exclude oleh pattern '${EXCLUDE_REGEX}'. Tidak ada target."
  exit 1
fi

log "Total akun setelah filter: ${#filtered[@]}"

# === Load existing state (counts/day) ===
declare -A sent_counts
if [[ -f "$STATE_FILE" ]]; then
  while IFS=" " read -r e c; do
    [[ -z "$e" ]] && continue
    sent_counts["$e"]="$c"
  done < "$STATE_FILE"
fi

save_state() {
  : > "$TMP_STATE"
  for e in "${!sent_counts[@]}"; do
    echo "$e ${sent_counts[$e]}" >> "$TMP_STATE"
  done
  mv "$TMP_STATE" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

# compute remaining cron runs today including current hour
HOUR_NOW=$(date +%H)
REMAINING_RUNS=$((24 - 10#$HOUR_NOW))
if [[ $REMAINING_RUNS -le 0 ]]; then REMAINING_RUNS=1; fi

log "Cron run start. Hour=$HOUR_NOW, remaining_runs=$REMAINING_RUNS"

# === Main loop: send emails per-account ===
for email in "${filtered[@]}"; do
  sent="${sent_counts[$email]:-0}"
  remaining=$((TARGET_PER_DAY - sent))
  if [[ $remaining -le 0 ]]; then
    log "[$email] sudah mencapai target hari ini ($sent/$TARGET_PER_DAY). Skip."
    continue
  fi

  # compute how many to send in this run
  per_run=$(((remaining + REMAINING_RUNS - 1) / REMAINING_RUNS))
  if [[ $per_run -gt $MAX_PER_RUN_CAP ]]; then per_run=$MAX_PER_RUN_CAP; fi

  log "[$email] sent=$sent remaining=$remaining -> akan mengirim $per_run email kali ini"

  for ((i=0;i<per_run;i++)); do
    seq_num=$((sent + 1))
    subj="Test message ${seq_num} of ${TARGET_PER_DAY} for ${email}"
    body="Halo,\n\nIni adalah email otomatis untuk pengujian.\nAkun: ${email}\nNomor: ${seq_num} dari ${TARGET_PER_DAY}\nTanggal: ${DATE_STR}\n\nSalam,\nAdmin\n"

    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY_RUN: would send to $email (subj='$subj')"
      echo -e "$body"
      # do not change sent counter in dry run
    else
      log "Mengirim -> $email (subj='$subj')"
      # tampilkan swaks verbose output di terminal dan log (tee)
      # kita jalankan swaks and capture both stdout+stderr, tee to logfile and stdout
      # Use --server, --to, --from, --header Subject, --body -, --quit-after DATA
      {
        printf '%b' "$body" | "$SWAKS_CMD" --server "$SWAKS_SERVER" --to "$email" --from "$DOMAIN_FROM" \
          --header "Subject: $subj" --body
      } 2>&1 | tee -a "$LOGFILE"

      # check last swaks exit status via PIPESTATUS (bash array)
      status=${PIPESTATUS[0]:-1}
      if [[ $status -eq 0 ]]; then
        sent=$((sent + 1))
        sent_counts["$email"]="$sent"
        log "SENT -> $email (${sent}/${TARGET_PER_DAY})"
      else
        log "ERROR sending -> $email (swaks exit=$status). Check above swaks output."
        # don't increment on failure
      fi

      # brief sleep to avoid flooding
      sleep 1
    fi

    # break if reached target
    if [[ "$sent" -ge "$TARGET_PER_DAY" ]]; then
      log "[$email] mencapai target hari ini (${sent}/${TARGET_PER_DAY}), stop sending to this account."
      break
    fi
  done
done

# save state if not dry run
if [[ "$DRY_RUN" != "1" ]]; then
  save_state
  log "State saved to $STATE_FILE"
else
  log "DRY_RUN active - state not saved"
fi

log "Cron run finished."
