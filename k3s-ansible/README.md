# k3s auf Proxmox — Automatisches Setup

Ein Bash-Skript erstellt 3 Ubuntu 24.04 VMs in Proxmox, Ansible installiert darauf einen k3s-Cluster (1 Master, 2 Worker).

---

## Voraussetzungen

- Proxmox VE läuft auf dem Server
- Server hat Internetzugang (für Cloud-Image-Download)
- Alle Befehle werden in der **Proxmox-Shell** ausgeführt (Web-UI → Node → Shell) als `root`

---

## Wichtig — diese Dateien kommen nie ins Git

| Datei | Inhalt |
|---|---|
| `kubeconfig` | Cluster-Zugangsdaten |
| `.claude/` | Lokale Claude-Konfiguration |

Vor dem ersten `git push` prüfen:
```bash
git status   # kubeconfig darf NICHT auftauchen
```

---

## Schritt 1 — Proxmox Enterprise-Repos deaktivieren

Ohne Lizenz schlägt `apt update` mit 401-Fehlern fehl.

```bash
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
apt update
```

---

## Schritt 2 — Tools installieren

```bash
# Git, Ansible, Python
apt install -y git ansible python3-pip curl

# Ansible Collections
ansible-galaxy collection install community.general ansible.posix
```

---

## Schritt 3 — SSH-Key erstellen

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

---

## Schritt 4 — Repository clonen

```bash
git clone https://github.com/J4N06/Testlab.git
cd Testlab/k3s-ansible
```

---

## Schritt 5 — Skript konfigurieren

```bash
nano setup-vms.sh
```

Folgende Werte oben im Skript anpassen:

| Variable | Beschreibung | Standard |
|---|---|---|
| `STORAGE` | Storage für VM-Disks | `local-lvm` |
| `BRIDGE` | Netzwerk-Bridge | `vmbr0` |
| `GATEWAY` | Standard-Gateway | `192.168.2.1` |
| `MASTER_IP` | IP Master-Node | `192.168.2.21` |
| `WORKER_IPS` | IPs Worker-Nodes | `192.168.2.22 / .23` |

---

## Schritt 6 — VMs erstellen

```bash
bash setup-vms.sh
```

Das Skript lädt das Ubuntu 24.04 Cloud-Image herunter (~600 MB) und erstellt die 3 VMs automatisch. Dauert ca. 3–5 Minuten.

---

## Schritt 7 — Ansible-Inventory prüfen

IPs in `inventory/hosts.yml` kontrollieren — sind standardmässig auf 192.168.2.21–23 gesetzt.

```bash
cat inventory/hosts.yml
```

---

## Schritt 8 — Verbindung zu den VMs testen

~60 Sekunden warten bis cloud-init fertig ist, dann:

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

## Schritt 9 — k3s installieren

```bash
ansible-playbook site.yml
```

Dauert ca. 5–8 Minuten.

---

## Schritt 10 — Cluster prüfen

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

```bash
# VMs löschen
bash destroy-vms.sh

# Alte kubeconfig entfernen
rm -f kubeconfig

# VMs neu erstellen (Cloud-Image bereits vorhanden — dauert ~2 Min.)
bash setup-vms.sh

# ~60 Sekunden warten, dann k3s neu installieren
ansible all -m ping
ansible-playbook site.yml
```

> Der k3s-Node-Token wird bei jeder Neuinstallation neu generiert. Die `kubeconfig` wird durch Ansible automatisch neu erstellt.

---

## Updates einspielen

```bash
git pull
ansible-playbook site.yml
```

---

## Häufige Fehler

**`ansible all -m ping` schlägt fehl**
→ SSH-Key nicht eingespielt. Testen:
```bash
ssh ubuntu@192.168.2.21
```

**VM startet nicht / bleibt bei cloud-init hängen**
→ Im Proxmox Web-UI Console der VM öffnen und Log prüfen. Häufigste Ursache: falsche Gateway-IP in `setup-vms.sh`.
