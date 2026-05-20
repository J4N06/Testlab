#!/bin/bash
set -e

# ─── Konfiguration ────────────────────────────────────────────────────────────
STORAGE="local-lvm"         # Storage für VM-Disks
IMAGE_STORAGE="local"       # Storage für Cloud-Image (muss iso-Typ unterstützen)
BRIDGE="vmbr0"              # Netzwerk-Bridge
GATEWAY="192.168.2.1"       # Standard-Gateway
DISK_SIZE="30G"

MASTER_ID=200
MASTER_IP="192.168.2.21"
MASTER_NAME="k3s-master"
MASTER_CORES=2
MASTER_MEMORY=4096

WORKER_IDS=(201 202)
WORKER_IPS=("192.168.2.22" "192.168.2.23")
WORKER_NAMES=("k3s-worker1" "k3s-worker2")
WORKER_CORES=2
WORKER_MEMORY=4096

IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_PATH="/var/lib/vz/template/iso/ubuntu-24.04-cloudimg.img"
SSH_KEY_FILE="/root/.ssh/id_ed25519.pub"
CI_USER="ubuntu"

# ─── Cloud-Image herunterladen ────────────────────────────────────────────────
if [ ! -f "$IMAGE_PATH" ]; then
    echo ">>> Cloud-Image wird heruntergeladen..."
    wget -q --show-progress -O "$IMAGE_PATH" "$IMAGE_URL"
else
    echo ">>> Cloud-Image bereits vorhanden, überspringe Download."
fi

# ─── VM erstellen ─────────────────────────────────────────────────────────────
create_vm() {
    local ID=$1
    local NAME=$2
    local IP=$3
    local CORES=$4
    local MEMORY=$5

    if qm status "$ID" &>/dev/null; then
        echo ">>> VM $ID ($NAME) existiert bereits, überspringe."
        return
    fi

    echo ">>> Erstelle VM $ID ($NAME) mit IP $IP..."

    qm create "$ID" \
        --name "$NAME" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --net0 "virtio,bridge=$BRIDGE" \
        --ostype l26 \
        --agent enabled=1

    qm importdisk "$ID" "$IMAGE_PATH" "$STORAGE" --format raw

    qm set "$ID" \
        --scsihw virtio-scsi-pci \
        --scsi0 "$STORAGE:vm-$ID-disk-0,discard=on,iothread=1" \
        --ide2 "$IMAGE_STORAGE:cloudinit" \
        --boot order=scsi0 \
        --serial0 socket \
        --vga serial0

    qm resize "$ID" scsi0 "$DISK_SIZE"

    qm set "$ID" \
        --ciuser "$CI_USER" \
        --sshkey "$SSH_KEY_FILE" \
        --ipconfig0 "ip=$IP/24,gw=$GATEWAY" \
        --nameserver "8.8.8.8"

    qm start "$ID"
    echo ">>> VM $ID ($NAME) gestartet."
}

# ─── Master erstellen ─────────────────────────────────────────────────────────
create_vm "$MASTER_ID" "$MASTER_NAME" "$MASTER_IP" "$MASTER_CORES" "$MASTER_MEMORY"

# ─── Worker erstellen ─────────────────────────────────────────────────────────
for i in "${!WORKER_IDS[@]}"; do
    create_vm "${WORKER_IDS[$i]}" "${WORKER_NAMES[$i]}" "${WORKER_IPS[$i]}" "$WORKER_CORES" "$WORKER_MEMORY"
done

echo ""
echo "✓ Alle VMs erstellt. Warte ~60 Sekunden bis cloud-init fertig ist, dann:"
echo "  cd .. && ansible all -m ping"
