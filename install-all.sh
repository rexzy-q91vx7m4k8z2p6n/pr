#!/bin/bash
set -Eeuo pipefail

BASE_URL="https://raw.githubusercontent.com/rexzy-q91vx7m4k8z2p6n/pr/main"
TMP_DIR="/tmp/pr-install-$$"
LOG_FILE="/var/log/pr-install.log"

mkdir -p "$TMP_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FILES=(
  "pr1.sh"
  "pr23.sh"
  "tele.sh"
  "pr24.sh"
  "pr25.sh"
  "antihackvps.sh"
  "pr2.sh"
  "pr3.sh"
  "pr4.sh"
  "pr16.sh"
  "pr19.sh"
  "pr20.sh"
  "pr21.sh"
  "pr5.sh"
  "pr15.sh"
  "pr6.sh"
  "pr7.sh"
  "pr8.sh"
  "pr9.sh"
  "pr10.sh"
  "pr11.sh"
  "pr12.sh"
  "pr18.sh"
)

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}❌ Jalankan sebagai root${NC}"
  exit 1
fi

echo -e "${CYAN}====================================${NC}"
echo -e "${CYAN}  AUTO INSTALL PROTECT SCRIPTS${NC}"
echo -e "${CYAN}====================================${NC}"
echo ""

SUKSES=0
GAGAL=0

for FILE in "${FILES[@]}"; do
  URL="${BASE_URL}/${FILE}"
  DEST="${TMP_DIR}/${FILE}"

  echo -e "${YELLOW}⬇️  Download: ${FILE}${NC}"

  if ! curl -fsSL --connect-timeout 15 --max-time 60 -o "$DEST" "$URL"; then
    echo -e "${RED}❌ Gagal download: ${FILE}${NC}"
    GAGAL=$((GAGAL + 1))
    continue
  fi

  if [ ! -s "$DEST" ]; then
    echo -e "${RED}❌ File kosong: ${FILE}${NC}"
    GAGAL=$((GAGAL + 1))
    continue
  fi

  chmod +x "$DEST"

  if head -c 100 "$DEST" | grep -qi "404: Not Found"; then
    echo -e "${RED}❌ File tidak ditemukan di repo: ${FILE}${NC}"
    GAGAL=$((GAGAL + 1))
    continue
  fi

  echo -e "${YELLOW}⚙️  Jalankan: ${FILE}${NC}"
  echo "----------------------------------------"

  if bash "$DEST"; then
    echo "----------------------------------------"
    echo -e "${GREEN}✅ Sukses: ${FILE}${NC}\n"
    SUKSES=$((SUKSES + 1))
  else
    RC=$?
    echo "----------------------------------------"
    echo -e "${RED}❌ Gagal jalankan ${FILE} (exit: ${RC})${NC}\n"
    GAGAL=$((GAGAL + 1))
  fi

  sleep 1
done

rm -rf "$TMP_DIR"

echo ""
echo -e "${CYAN}====================================${NC}"
echo -e "${GREEN}✅ Selesai${NC}"
echo -e "${GREEN}   Sukses : ${SUKSES}${NC}"
echo -e "${RED}   Gagal  : ${GAGAL}${NC}"
echo -e "${CYAN}   Log    : ${LOG_FILE}${NC}"
echo -e "${CYAN}====================================${NC}"

if [ "$GAGAL" -gt 0 ]; then
  exit 1
fi

exit 0
