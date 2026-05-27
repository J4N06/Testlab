#!/bin/bash
# Einmalig ausführen (oder nach Änderungen an autounattend.xml)
# Benötigt ~10 GB freien Speicher und dauert 2-5 Minuten

set -e

ISO_DIR="/var/lib/vz/template/iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIN_ISO="${ISO_DIR}/SW_DVD9_Win_Server_STD_CORE_2025_24H2_64Bit_English_DC_STD_MLF_X23-81891.ISO"
OUT_ISO="${ISO_DIR}/windows-server-2025-autounattend.iso"
MNT_DIR=$(mktemp -d)
WORK_DIR="${ISO_DIR}/.winiso_tmp_$$"

cleanup() {
  mountpoint -q "$MNT_DIR" 2>/dev/null && umount "$MNT_DIR" || true
  rm -rf "$MNT_DIR" "$WORK_DIR"
}
trap cleanup EXIT

if ! command -v xorriso &>/dev/null; then
  echo "Installiere xorriso..."
  apt-get install -y xorriso
fi

[ -f "$WIN_ISO" ] || { echo "FEHLER: $WIN_ISO nicht gefunden"; exit 1; }

echo "1/4 Lese ISO-Metadaten..."
BOOT_PARAMS=$(xorriso -indev "$WIN_ISO" -report_el_torito as_mkisofs 2>/dev/null \
  | grep -v "^xorriso" | grep -v "^$" | tr '\n' ' ')
VOL_LABEL=$(xorriso -indev "$WIN_ISO" -pvd_info 2>/dev/null \
  | awk -F"'" '/Volume id/{print $2; exit}')
[ -z "$VOL_LABEL" ] && VOL_LABEL="WIN_SERVER_2025"
echo "   Volume: $VOL_LABEL"
echo "   Boot:   $BOOT_PARAMS"

echo "2/4 Extrahiere ISO-Inhalt (~5 GB)..."
mkdir -p "$WORK_DIR"
mount -o loop,ro "$WIN_ISO" "$MNT_DIR"
cp -a "$MNT_DIR/." "$WORK_DIR/"
umount "$MNT_DIR"

echo "3/4 Füge autounattend.xml ein..."
cp "$SCRIPT_DIR/autounattend.xml" "$WORK_DIR/autounattend.xml"

echo "4/4 Erstelle bootbares ISO..."
eval "xorriso -as mkisofs \
  -iso-level 4 \
  -full-iso9660-filenames \
  -J -joliet-long \
  -V \"$VOL_LABEL\" \
  $BOOT_PARAMS \
  -o \"$OUT_ISO\" \
  \"$WORK_DIR\""

echo "Fertig: $OUT_ISO ($(du -h "$OUT_ISO" | cut -f1))"
