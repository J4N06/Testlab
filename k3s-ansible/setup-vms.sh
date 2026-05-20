#!/bin/bash
set -e

# ─── Hilfsfunktion: Eingabe mit Standardwert ──────────────────────────────────
ask() {
    local prompt=$1
    local default=$2
    local var
    read -rp "$prompt [$default]: " var
    echo "${var:-$default}"
}

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     k3s VM Setup für Proxmox         ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ─── Parameter abfragen ───────────────────────────────────────────────────────
STORAGE=$(ask    "Storage für VM-Disks     (local-lvm / local-zfs)" "local-lvm")
BRIDGE=$(ask     "Netzwerk-Bridge                                  " "vmbr0")
GATEWAY=$(ask    "Standard-Gateway                                 " "192.168.2.1")

echo ""
MASTER_IP=$(ask  "IP Master-Node                                   " "192.168.2.21")
WORKER1_IP=$(ask "IP Worker 1                                      " "192.168.2.22")
WORKER2_IP=$(ask "IP Worker 2                                      " "192.168.2.23")

echo ""
MASTER_CORES=$(ask  "CPU-Kerne Master                              " "2")
MASTER_MEM=$(ask    "RAM Master (MB)                               " "4096")
WORKER_CORES=$(ask  "CPU-Kerne Worker                              " "2")
WORKER_MEM=$(ask    "RAM Worker (MB)                               " "4096")
DISK_SIZE=$(ask     "Disk-Grösse pro VM                            " "30G")

echo ""
echo "──────────────────────────────────────────"
echo "Zusammenfassung:"
echo "  Storage:   $STORAGE | Bridge: $BRIDGE | Gateway: $GATEWAY"
echo "  Master:    $MASTER_IP  ($MASTER_CORES vCPU, ${MASTER_MEM}MB RAM)"
echo "  Worker 1:  $WORKER1_IP ($WORKER_CORES vCPU, ${WORKER_MEM}MB RAM)"
echo "  Worker 2:  $WORKER2_IP ($WORKER_CORES vCPU, ${WORKER_MEM}MB RAM)"
echo "  Disk:      $DISK_SIZE pro VM"
echo "──────────────────────────────────────────"
echo ""
read -rp "Starten? [j/N]: " confirm
[[ "${confirm,,}" != "j" ]] && echo "Abgebrochen." && exit 0

# ─── Fixe Werte ───────────────────────────────────────────────────────────────
IMAGE_STORAGE="local"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_PATH="/var/lib/vz/template/iso/ubuntu-24.04-cloudimg.img"
SSH_KEY_FILE="/root/.ssh/id_ed25519.pub"
CI_USER="ubuntu"

MASTER_ID=200
WORKER_IDS=(201 202)
WORKER_IPS=("$WORKER1_IP" "$WORKER2_IP")
WORKER_NAMES=("k3s-worker1" "k3s-worker2")

# ─── Cloud-Image herunterladen ────────────────────────────────────────────────
if [ ! -f "$IMAGE_PATH" ]; then
    echo ""
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

echo ""
create_vm "$MASTER_ID" "k3s-master" "$MASTER_IP" "$MASTER_CORES" "$MASTER_MEM"

for i in "${!WORKER_IDS[@]}"; do
    create_vm "${WORKER_IDS[$i]}" "${WORKER_NAMES[$i]}" "${WORKER_IPS[$i]}" "$WORKER_CORES" "$WORKER_MEM"
done

# ─── Ansible-Inventory automatisch aktualisieren ─────────────────────────────
INVENTORY="$(dirname "$0")/inventory/hosts.yml"
if [ -f "$INVENTORY" ]; then
    echo ""
    echo ">>> Ansible-Inventory wird aktualisiert..."
    cat > "$INVENTORY" <<EOF
---
all:
  children:
    k3s_master:
      hosts:
        master:
          ansible_host: $MASTER_IP
          ansible_user: $CI_USER

    k3s_workers:
      hosts:
        worker1:
          ansible_host: $WORKER1_IP
          ansible_user: $CI_USER
        worker2:
          ansible_host: $WORKER2_IP
          ansible_user: $CI_USER
EOF
    echo ">>> inventory/hosts.yml aktualisiert."
fi

echo ""
echo "✓ Alle VMs erstellt."
echo ""
echo "Warte ~60 Sekunden bis cloud-init fertig ist, dann:"
echo "  ansible all -m ping"
echo "  ansible-playbook site.yml"
