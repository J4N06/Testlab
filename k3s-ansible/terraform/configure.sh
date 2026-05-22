#!/bin/bash
set -e

if ! command -v whiptail &>/dev/null; then
    apt-get install -y whiptail
fi

TITLE="k3s Konfiguration"
TFVARS="$(dirname "$0")/terraform.tfvars"

# ─── Aktuelle Werte aus terraform.tfvars lesen (oder Defaults) ───────────────
read_var() {
    local key=$1
    local default=$2
    if [ -f "$TFVARS" ]; then
        local val
        val=$(grep -E "^${key}\s*=" "$TFVARS" | sed 's/.*=\s*"\?\([^"]*\)"\?.*/\1/' | tr -d ' ' | head -1)
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

read_list() {
    local key=$1
    local default=$2
    if [ -f "$TFVARS" ]; then
        local val
        val=$(grep -E "^${key}\s*=" "$TFVARS" | sed 's/.*\["\(.*\)"\].*/\1/' | sed 's/", "/,/g' | head -1)
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

# ─── Werte abfragen ───────────────────────────────────────────────────────────
PROXMOX_URL=$(whiptail --title "$TITLE" --inputbox \
    "Proxmox API URL" 10 60 "$(read_var proxmox_url 'https://192.168.2.10:8006')" 3>&1 1>&2 2>&3)

PROXMOX_TOKEN=$(whiptail --title "$TITLE" --passwordbox \
    "Proxmox API Token\n(root@pam!terraform=uuid)" 10 60 "$(read_var proxmox_api_token '')" 3>&1 1>&2 2>&3)

PROXMOX_NODE=$(whiptail --title "$TITLE" --inputbox \
    "Proxmox Node-Name\n(oben links im Web-UI sichtbar)" 10 60 "$(read_var proxmox_node 'pve')" 3>&1 1>&2 2>&3)

STORAGE=$(whiptail --title "$TITLE" --inputbox \
    "Storage für VM-Disks" 10 60 "$(read_var storage 'local-lvm')" 3>&1 1>&2 2>&3)

BRIDGE=$(whiptail --title "$TITLE" --inputbox \
    "Netzwerk-Bridge" 10 60 "$(read_var bridge 'vmbr0')" 3>&1 1>&2 2>&3)

GATEWAY=$(whiptail --title "$TITLE" --inputbox \
    "Standard-Gateway" 10 60 "$(read_var gateway '192.168.2.1')" 3>&1 1>&2 2>&3)

MASTER_NAME=$(whiptail --title "$TITLE" --inputbox \
    "Name Master-VM (= Hostname im Cluster)" 10 60 "$(read_var master_name 'master')" 3>&1 1>&2 2>&3)

MASTER_IP=$(whiptail --title "$TITLE" --inputbox \
    "IP Master" 10 60 "$(read_var master_ip '192.168.2.21')" 3>&1 1>&2 2>&3)

MASTER_CORES=$(whiptail --title "$TITLE" --inputbox \
    "CPU-Kerne Master" 10 60 "$(read_var master_cores '2')" 3>&1 1>&2 2>&3)

MASTER_MEM=$(whiptail --title "$TITLE" --inputbox \
    "RAM Master (MB)" 10 60 "$(read_var master_memory '4096')" 3>&1 1>&2 2>&3)

WORKER1_NAME=$(whiptail --title "$TITLE" --inputbox \
    "Name Worker 1" 10 60 "$(read_list worker_names 'worker1,worker2' | cut -d, -f1)" 3>&1 1>&2 2>&3)

WORKER2_NAME=$(whiptail --title "$TITLE" --inputbox \
    "Name Worker 2" 10 60 "$(read_list worker_names 'worker1,worker2' | cut -d, -f2)" 3>&1 1>&2 2>&3)

WORKER1_IP=$(whiptail --title "$TITLE" --inputbox \
    "IP Worker 1" 10 60 "$(read_list worker_ips '192.168.2.22,192.168.2.23' | cut -d, -f1)" 3>&1 1>&2 2>&3)

WORKER2_IP=$(whiptail --title "$TITLE" --inputbox \
    "IP Worker 2" 10 60 "$(read_list worker_ips '192.168.2.22,192.168.2.23' | cut -d, -f2)" 3>&1 1>&2 2>&3)

WORKER_CORES=$(whiptail --title "$TITLE" --inputbox \
    "CPU-Kerne Worker" 10 60 "$(read_var worker_cores '2')" 3>&1 1>&2 2>&3)

WORKER_MEM=$(whiptail --title "$TITLE" --inputbox \
    "RAM Worker (MB)" 10 60 "$(read_var worker_memory '4096')" 3>&1 1>&2 2>&3)

DISK_SIZE=$(whiptail --title "$TITLE" --inputbox \
    "Disk-Grösse pro VM (GB)" 10 60 "$(read_var disk_size '30')" 3>&1 1>&2 2>&3)

# ─── Zusammenfassung ─────────────────────────────────────────────────────────
whiptail --title "$TITLE" --yesno \
"Zusammenfassung — bitte prüfen:

  Proxmox  :  $PROXMOX_URL  (Node: $PROXMOX_NODE)
  Storage  :  $STORAGE  |  Bridge: $BRIDGE  |  Gateway: $GATEWAY

  Master   :  $MASTER_NAME ($MASTER_IP)  $MASTER_CORES vCPU, ${MASTER_MEM} MB, ${DISK_SIZE} GB
  Worker 1 :  $WORKER1_NAME ($WORKER1_IP)  $WORKER_CORES vCPU, ${WORKER_MEM} MB, ${DISK_SIZE} GB
  Worker 2 :  $WORKER2_NAME ($WORKER2_IP)  $WORKER_CORES vCPU, ${WORKER_MEM} MB, ${DISK_SIZE} GB

Speichern?" 20 70

# ─── terraform.tfvars schreiben ───────────────────────────────────────────────
cat > "$TFVARS" <<EOF
proxmox_url       = "$PROXMOX_URL"
proxmox_api_token = "$PROXMOX_TOKEN"
proxmox_node      = "$PROXMOX_NODE"
storage           = "$STORAGE"
bridge            = "$BRIDGE"
gateway           = "$GATEWAY"
master_name       = "$MASTER_NAME"
master_ip         = "$MASTER_IP"
master_cores      = $MASTER_CORES
master_memory     = $MASTER_MEM
worker_names      = ["$WORKER1_NAME", "$WORKER2_NAME"]
worker_ips        = ["$WORKER1_IP", "$WORKER2_IP"]
worker_cores      = $WORKER_CORES
worker_memory     = $WORKER_MEM
disk_size         = $DISK_SIZE
EOF

whiptail --title "$TITLE" --msgbox \
"✓ terraform.tfvars gespeichert!

Weiter mit:
  terraform init   (nur beim ersten Mal)
  terraform apply" 12 50
