#!/bin/bash
# Erstellt autounattend.iso (~4 KB) und legt es ins Proxmox ISO-Verzeichnis
# Benötigt: genisoimage (apt-get install genisoimage)

set -e

ISO_DIR="/var/lib/vz/template/iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ISO="${ISO_DIR}/autounattend.iso"

if ! command -v genisoimage &>/dev/null; then
  echo "Installiere genisoimage..."
  apt-get install -y genisoimage
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp "$SCRIPT_DIR/autounattend.xml" "$TMPDIR/"

genisoimage -J -V "AUTOUNATTEND" \
  -o "$OUT_ISO" \
  "$TMPDIR"

echo "Fertig: $OUT_ISO ($(du -h "$OUT_ISO" | cut -f1))"
