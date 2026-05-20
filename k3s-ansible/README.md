# k3s auf Proxmox — Automatisches Setup

Terraform erstellt 3 Ubuntu 24.04 VMs in Proxmox, Ansible installiert darauf einen k3s-Cluster (1 Master, 2 Worker).

---

## Voraussetzungen

- Proxmox VE läuft auf dem Server
- Server hat Internetzugang (für Cloud-Image-Download)
- Alle Befehle werden in der **Proxmox-Shell** ausgeführt (Web-UI → Node → Shell)

---

## Wichtig — diese Dateien kommen nie ins Git

Folgendes ist in `.gitignore` eingetragen und wird **nicht** ins Repository eingecheckt:

| Datei / Ordner | Inhalt |
|---|---|
| `terraform/terraform.tfvars` | Proxmox-Passwort, SSH-Key |
| `terraform/terraform.tfstate` | Aktueller Infrastruktur-Zustand |
| `terraform/.terraform/` | Lokale Provider-Binaries |
| `kubeconfig` | Cluster-Zugangsdaten |
| `.claude/` | Lokale Claude-Konfiguration |

Vor dem ersten `git push` prüfen:
```bash
git status   # terraform.tfvars darf NICHT auftauchen
```

---

## Schritt 1 — Proxmox Enterprise-Repos deaktivieren

Proxmox ist standardmässig auf kostenpflichtige Enterprise-Repos eingestellt. Ohne Lizenz schlägt `apt update` mit 401-Fehlern fehl.

```bash
# Enterprise-Repos deaktivieren
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list

# Kostenloses No-Subscription-Repo hinzufügen
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

# Testen
apt update
```

---

## Schritt 2 — Tools installieren

```bash
# Git, Ansible, Python
sudo apt update && sudo apt install -y git ansible python3-pip curl unzip

# Ansible Collections
ansible-galaxy collection install community.general ansible.posix

# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
```

---

## Schritt 3 — Proxmox API-User anlegen

```bash
pveum user add terraform@pve --password 'DeinPasswort'
pveum aclmod / -user terraform@pve -role PVEVMAdmin
pveum aclmod /storage/local -user terraform@pve -role PVEDatastoreAdmin
pveum aclmod /storage/local-lvm -user terraform@pve -role PVEDatastoreAdmin
```

---

## Schritt 4 — SSH-Key erstellen

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub   # diesen Wert später in terraform.tfvars eintragen
```

---

## Schritt 5 — Repository clonen

```bash
git clone https://github.com/J4N06/Testlab.git
cd Testlab/k3s-ansible
```

---

## Schritt 6 — Terraform konfigurieren

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Hinweis: du bist jetzt in Testlab/k3s-ansible/terraform/
```

Folgende Werte anpassen:

| Variable | Beschreibung | Beispiel |
|---|---|---|
| `proxmox_endpoint` | Proxmox API-URL | `https://127.0.0.1:8006/` |
| `proxmox_password` | Passwort des terraform@pve Users | |
| `proxmox_node` | Name des Proxmox-Hosts | `pve` |
| `proxmox_storage` | Storage für VM-Disks | `local-lvm` |
| `ssh_public_key` | Inhalt von `~/.ssh/id_ed25519.pub` | |
| `network_gateway` | Gateway des VM-Netzes | `192.168.2.1` |
| `master_ip` | IP Master (mit /24) | `192.168.2.21/24` |
| `worker_ips` | IPs Worker (mit /24) | `["192.168.2.22/24", "192.168.2.23/24"]` |

---

## Schritt 7 — VMs erstellen

```bash
terraform init
terraform plan    # Vorschau — noch nichts wird erstellt
terraform apply   # Mit "yes" bestätigen
```

Terraform lädt das Ubuntu 24.04 Cloud-Image herunter (~600 MB) und erstellt die 3 VMs automatisch. Dauert ca. 3–5 Minuten.

---

## Schritt 8 — Ansible-Inventory befüllen

```bash
cd ..
terraform -chdir=terraform output ansible_inventory_hint
```

Die ausgegebenen IPs in `inventory/hosts.yml` eintragen (sind standardmässig bereits auf 192.168.2.21–23 gesetzt).

---

## Schritt 9 — Verbindung zu den VMs testen

```bash
ansible all -m ping
```

Erwartete Ausgabe:
```
master  | SUCCESS
worker1 | SUCCESS
worker2 | SUCCESS
```

---

## Schritt 10 — k3s installieren

```bash
ansible-playbook site.yml
```

Dauert ca. 5–8 Minuten.

---

## Schritt 11 — Cluster prüfen

```bash
kubectl --kubeconfig=kubeconfig get nodes
```

Erwartete Ausgabe:
```
NAME      STATUS   ROLES                  AGE   VERSION
master    Ready    control-plane,master   2m    v1.30.x+k3s1
worker1   Ready    <none>                 1m    v1.30.x+k3s1
worker2   Ready    <none>                 1m    v1.30.x+k3s1
```

---

## VMs löschen und neu aufsetzen (Reset)

Wenn du die VMs komplett löschen und den Cluster neu aufbauen willst:

### 1. VMs zerstören

```bash
cd k3s-ansible/terraform/
terraform destroy   # Mit "yes" bestätigen
```

Terraform löscht alle 3 VMs in Proxmox. Das Cloud-Image bleibt erhalten — es muss nicht nochmal heruntergeladen werden.

### 2. Alte kubeconfig entfernen

```bash
cd ..
rm -f kubeconfig
```

### 3. VMs neu erstellen

```bash
cd terraform/
terraform apply   # Mit "yes" bestätigen
```

Dauert ca. 2–3 Minuten (Cloud-Image ist bereits vorhanden).

### 4. Warten bis cloud-init fertig ist

Nach dem `terraform apply` brauchen die VMs ~60 Sekunden bis cloud-init abgeschlossen ist und SSH bereit ist. Danach testen:

```bash
cd ..
ansible all -m ping
```

### 5. k3s neu installieren

```bash
ansible-playbook site.yml
```

> **Hinweis:** Der k3s-Node-Token wird bei jeder Neuinstallation neu generiert. Die alte `kubeconfig` funktioniert danach nicht mehr — sie wird durch Ansible automatisch neu erstellt.

---

## Updates einspielen

Nach Code-Änderungen auf GitHub:

```bash
git pull
terraform -chdir=terraform apply   # bei Infrastruktur-Änderungen
ansible-playbook site.yml          # bei k3s-Änderungen
```

---

## Häufige Fehler

**`ansible all -m ping` schlägt fehl**
→ SSH-Key in `terraform.tfvars` und `ansible.cfg` stimmen nicht überein. Prüfen ob der Key korrekt eingespielt wurde:
```bash
ssh ubuntu@192.168.2.21
```

**Terraform-Download schlägt fehl**
→ Proxmox-Berechtigungen für `/storage/local` fehlen — Schritt 2 wiederholen.

**VM startet nicht / bleibt bei cloud-init hängen**
→ Im Proxmox Web-UI die Console der VM öffnen und Log prüfen. Häufigste Ursache: falsche Gateway-IP in `terraform.tfvars`.
