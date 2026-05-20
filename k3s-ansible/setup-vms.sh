#!/bin/bash
set -e

# ─── whiptail prüfen ──────────────────────────────────────────────────────────
if ! command -v whiptail &>/dev/null; then
    apt-get install -y whiptail
fi

TITLE="k3s VM Setup für Proxmox"

# ─── Parameter abfragen ───────────────────────────────────────────────────────
STORAGE=$(whiptail --title "$TITLE" --inputbox \
    "Storage für VM-Disks\n(z.B. local-lvm, local-zfs)" 10 50 "local-lvm" 3>&1 1>&2 2>&3)

BRIDGE=$(whiptail --title "$TITLE" --inputbox \
    "Netzwerk-Bridge" 10 50 "vmbr0" 3>&1 1>&2 2>&3)

GATEWAY=$(whiptail --title "$TITLE" --inputbox \
    "Standard-Gateway" 10 50 "192.168.2.1" 3>&1 1>&2 2>&3)

MASTER_IP=$(whiptail --title "$TITLE" --inputbox \
    "IP Master-Node" 10 50 "192.168.2.21" 3>&1 1>&2 2>&3)

WORKER1_IP=$(whiptail --title "$TITLE" --inputbox \
    "IP Worker 1" 10 50 "192.168.2.22" 3>&1 1>&2 2>&3)

WORKER2_IP=$(whiptail --title "$TITLE" --inputbox \
    "IP Worker 2" 10 50 "192.168.2.23" 3>&1 1>&2 2>&3)

MASTER_CORES=$(whiptail --title "$TITLE" --inputbox \
    "CPU-Kerne Master" 10 50 "2" 3>&1 1>&2 2>&3)

MASTER_MEM=$(whiptail --title "$TITLE" --inputbox \
    "RAM Master (MB)" 10 50 "4096" 3>&1 1>&2 2>&3)

WORKER_CORES=$(whiptail --title "$TITLE" --inputbox \
    "CPU-Kerne Worker" 10 50 "2" 3>&1 1>&2 2>&3)

WORKER_MEM=$(whiptail --title "$TITLE" --inputbox \
    "RAM Worker (MB)" 10 50 "4096" 3>&1 1>&2 2>&3)

DISK_SIZE=$(whiptail --title "$TITLE" --inputbox \
    "Disk-Grösse pro VM" 10 50 "30G" 3>&1 1>&2 2>&3)

# ─── Zusammenfassung + Bestätigung ───────────────────────────────────────────
whiptail --title "$TITLE" --yesno \
"Zusammenfassung — bitte prüfen:

  Storage :  $STORAGE
  Bridge  :  $BRIDGE
  Gateway :  $GATEWAY

  Master  :  $MASTER_IP  ($MASTER_CORES vCPU, ${MASTER_MEM} MB, $DISK_SIZE)
  Worker1 :  $WORKER1_IP ($WORKER_CORES vCPU, ${WORKER_MEM} MB, $DISK_SIZE)
  Worker2 :  $WORKER2_IP ($WORKER_CORES vCPU, ${WORKER_MEM} MB, $DISK_SIZE)

Jetzt starten?" 20 55

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
        --ide2 "$STORAGE:cloudinit" \
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

create_vm "$MASTER_ID" "k3s-master" "$MASTER_IP" "$MASTER_CORES" "$MASTER_MEM"

for i in "${!WORKER_IDS[@]}"; do
    create_vm "${WORKER_IDS[$i]}" "${WORKER_NAMES[$i]}" "${WORKER_IPS[$i]}" "$WORKER_CORES" "$WORKER_MEM"
done

# ─── Ansible-Inventory automatisch aktualisieren ─────────────────────────────
INVENTORY="$(dirname "$0")/inventory/hosts.yml"
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

whiptail --title "$TITLE" --msgbox \
"✓ Alle VMs erstellt!

Warte ~60 Sekunden bis cloud-init fertig ist.

Dann weiter mit:
  ansible all -m ping
  ansible-playbook site.yml" 15 50
