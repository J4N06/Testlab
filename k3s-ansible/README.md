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

Ohne Lizenz schlägt `apt update` mit 401-Fehlern fehl. Proxmox verwendet das neuere `.sources`-Format:

```bash
# Enterprise-Repos deaktivieren
cat > /etc/apt/sources.list.d/pve-enterprise.sources << 'EOF'
Types: deb
URIs: https://enterprise.proxmox.com/debian/ceph-squid
Suites: trixie
Components: enterprise
Enabled: no
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg

Types: deb
URIs: https://enterprise.proxmox.com/debian/pve
Suites: trixie
Components: pve-enterprise
Enabled: no
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

cat > /etc/apt/sources.list.d/ceph.sources << 'EOF'
Types: deb
URIs: https://enterprise.proxmox.com/debian/ceph-squid
Suites: trixie
Components: enterprise
Enabled: no
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

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
apt install -y git ansible python3-pip curl

# Ansible Collections
ansible-galaxy collection install community.general ansible.posix
```

---

## Schritt 3 — Projekt-SSH-Key erstellen

Ein dedizierter Key für dieses Projekt — unabhängig vom Linux-User.
`k3s_key` bleibt lokal (gitignore), `k3s_key.pub` kommt ins Repo.

```bash
cd Testlab/k3s-ansible
ssh-keygen -t ed25519 -f k3s_key -N ""
```

---

## Schritt 4 — Repository clonen

```bash
git clone https://github.com/J4N06/Testlab.git
cd Testlab/k3s-ansible
```

---

## Schritt 5 — VMs erstellen

```bash
bash setup-vms.sh
```

Das Skript fragt alle Parameter interaktiv ab (mit Standardwerten):

```
Storage für VM-Disks  [local-lvm]:
Netzwerk-Bridge       [vmbr0]:
Standard-Gateway      [192.168.2.1]:
IP Master-Node        [192.168.2.21]:
IP Worker 1           [192.168.2.22]:
IP Worker 2           [192.168.2.23]:
CPU-Kerne Master      [2]:
RAM Master (MB)       [4096]:
...
Starten? [j/N]: j
```

Danach lädt es das Ubuntu 24.04 Cloud-Image herunter (~600 MB), erstellt die 3 VMs und aktualisiert `inventory/hosts.yml` automatisch. Dauert ca. 3–5 Minuten.

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

**`ssh ubuntu@192.168.2.21` — Permission denied (publickey)**
→ SSH-Key wurde nicht als `root` generiert. VMs neu erstellen:
```bash
sudo -i
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
bash destroy-vms.sh && bash setup-vms.sh
```

**`ansible all -m ping` schlägt fehl**
→ SSH-Key nicht eingespielt. Testen:
```bash
ssh ubuntu@192.168.2.21
```

**VM startet nicht / bleibt bei cloud-init hängen**
→ Im Proxmox Web-UI Console der VM öffnen und Log prüfen. Häufigste Ursache: falsche Gateway-IP in `setup-vms.sh`.
