# k3s auf Proxmox — Automatisches Setup

Terraform erstellt 3 Ubuntu 24.04 VMs in Proxmox, Ansible installiert darauf einen k3s-Cluster (1 Master, 2 Worker).

---

## Voraussetzungen

- Proxmox VE läuft auf dem Server
- Server hat Internetzugang
- Alle Befehle werden in der **Proxmox-Shell** ausgeführt (Web-UI → Node → Shell) als `root`

---

## Wichtig — diese Dateien kommen nie ins Git

| Datei | Inhalt |
|---|---|
| `terraform/terraform.tfvars` | Proxmox API-Token |
| `kubeconfig` | Cluster-Zugangsdaten |
| `k3s_key` | Privater SSH-Key |

---

## Schritt 1 — Proxmox Enterprise-Repos deaktivieren

Ohne Lizenz schlägt `apt update` mit 401-Fehlern fehl:

```bash
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

echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

apt update
```

---

## Schritt 2 — Tools installieren

```bash
# Git, Ansible, Python
apt install -y git ansible python3-pip curl unzip

# Ansible Collections
ansible-galaxy collection install community.general ansible.posix

# Terraform
TERRAFORM_VERSION="1.9.8"
wget -q -O terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip terraform.zip && mv terraform /usr/local/bin/ && rm terraform.zip
```

---

## Schritt 3 — Repository clonen

```bash
git clone https://github.com/J4N06/Testlab.git
cd Testlab/k3s-ansible
```

---

## Schritt 4 — Projekt-SSH-Key erstellen

```bash
ssh-keygen -t ed25519 -f k3s_key -N ""
git add k3s_key.pub
git commit -m "add: projekt ssh public key"
git push
```

### Weitere Benutzer hinzufügen (optional)

Public Keys in `team_keys.pub` eintragen (eine Zeile pro Key) und committen:

```
ssh-ed25519 AAAAC3... jan@laptop
ssh-ed25519 AAAAC3... lisa@pc
```

---

## Schritt 5 — Proxmox API-Token erstellen

Proxmox Web-UI → **Datacenter → API Tokens → Add**

| Feld | Wert |
|---|---|
| User | `root@pam` |
| Token ID | `terraform` |
| Privilege Separation | **nein** |

Den angezeigten Secret-Wert kopieren — er wird nur **einmal** angezeigt.

---

## Schritt 6 — Terraform konfigurieren

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` bearbeiten:

```hcl
proxmox_url       = "https://192.168.2.10:8006"   # IP deines Proxmox-Hosts
proxmox_api_token = "root@pam!terraform=dein-secret"
proxmox_node      = "pve"                          # Node-Name (oben links im Web-UI)
```

---

## Schritt 7 — VMs erstellen

```bash
terraform init
terraform apply
```

Terraform lädt das Ubuntu 24.04 Cloud-Image herunter (~600 MB), erstellt die 3 VMs und schreibt `inventory/hosts.yml` automatisch.

---

## Schritt 8 — Verbindung testen

~60 Sekunden warten bis cloud-init fertig ist, dann:

```bash
cd ..
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
ssh -i k3s_key ubuntu@192.168.2.21 "sudo kubectl get nodes"
```

Erwartete Ausgabe:
```
NAME      STATUS   ROLES           AGE   VERSION
master    Ready    control-plane   2m    v1.35.x+k3s1
worker1   Ready    <none>          1m    v1.35.x+k3s1
worker2   Ready    <none>          1m    v1.35.x+k3s1
```

---

## VMs löschen und neu aufsetzen (Reset)

```bash
cd terraform

# VMs löschen
terraform destroy

# VMs neu erstellen
terraform apply

# ~60 Sekunden warten, dann k3s neu installieren
cd ..
ansible all -m ping
ansible-playbook site.yml
```

---

## Updates einspielen

```bash
git pull
ansible-playbook site.yml
```

---

## Häufige Fehler

**`ssh ubuntu@192.168.2.21` — Permission denied (publickey)**
→ Projekt-Key angeben:
```bash
ssh -i k3s_key ubuntu@192.168.2.21
```

**`ansible all -m ping` schlägt fehl**
→ Verbindung manuell testen:
```bash
ssh -i k3s_key ubuntu@192.168.2.21
```

**`terraform apply` — 401 Unauthorized**
→ API-Token falsch. Format prüfen: `root@pam!terraform=uuid`

**VM startet nicht / bleibt bei cloud-init hängen**
→ Im Proxmox Web-UI Console der VM öffnen. Häufigste Ursache: falsche Gateway-IP in `terraform.tfvars`.
