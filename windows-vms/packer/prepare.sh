#!/bin/bash
# Einmalig ausführen (oder nach Änderungen an autounattend.xml)
# Injiziert autounattend.xml in eine Kopie des Windows-ISO

set -e

ISO_DIR="/var/lib/vz/template/iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WIN_ISO="${ISO_DIR}/SW_DVD9_Win_Server_STD_CORE_2025_24H2_64Bit_English_DC_STD_MLF_X23-81891.ISO"
OUT_ISO="${ISO_DIR}/windows-server-2025-autounattend.iso"

if [ ! -f "$WIN_ISO" ]; then
  echo "FEHLER: Windows ISO nicht gefunden: $WIN_ISO"
  exit 1
fi

if ! command -v xorriso &>/dev/null; then
  echo "Installiere xorriso..."
  apt-get install -y xorriso
fi

echo "Kopiere Windows ISO nach $OUT_ISO (~5 GB, dauert 1-2 Min.)..."
cp "$WIN_ISO" "$OUT_ISO"

echo "Injiziere autounattend.xml..."
xorriso \
  -dev "$OUT_ISO" \
  -map "$SCRIPT_DIR/autounattend.xml" /autounattend.xml \
  --

echo "Fertig: $OUT_ISO"
