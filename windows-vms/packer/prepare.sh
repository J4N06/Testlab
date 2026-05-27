#!/bin/bash
# Einmalig ausführen bevor packer build
# Erstellt autounattend.iso und legt es direkt ins Proxmox ISO-Verzeichnis

set -e

ISO_DIR="/var/lib/vz/template/iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v genisoimage &>/dev/null && ! command -v mkisofs &>/dev/null; then
  echo "Installiere genisoimage..."
  apt-get install -y genisoimage
fi

CMD="genisoimage"
command -v genisoimage &>/dev/null || CMD="mkisofs"

echo "Erstelle autounattend.iso..."
$CMD -o "$ISO_DIR/autounattend.iso" -J -V "Autounattend" "$SCRIPT_DIR/autounattend.xml"

echo "Fertig: $ISO_DIR/autounattend.iso"
