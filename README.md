# ISE-Testlab Proxmox

---

## Übersicht

```
Testlab/
├── k3s-ansible/                 # k3s Kubernetes-Cluster
│   ├── terraform/               # Linux VMs erstellen
│   ├── roles/                   # Ansible-Rollen
│   └── argocd-apps/             # GitOps-Applikationen
├── radius-cert-automation/      # TLS-Zertifikate für Windows NPS
│   ├── docker/                  # Deployer-Container
│   ├── k8s/                     # Helm Chart
│   ├── customers/               # Pro-Kunden-Konfiguration
│   └── windows/                 # PowerShell-Hilfsskripte
└── windows-vms/                 # Windows VMs auf Proxmox
    └── nps-test/                # NPS Test-Server
        ├── main.tf              # VM erstellen
        └── ansible/             # Windows konfigurieren
```

---

## Projekte

### k3s-ansible

Automatisches Setup eines k3s-Clusters auf Proxmox:

- **Terraform** erstellt 3 Ubuntu 24.04 VMs (1 Master, 2 Worker)
- **Ansible** installiert k3s, ArgoCD und den Monitoring-Stack
- **ArgoCD** verwaltet alle weiteren Applikationen via GitOps

| Komponente | Beschreibung |
|---|---|
| k3s | Leichtgewichtiges Kubernetes |
| ArgoCD | GitOps — deployt Apps automatisch aus Git |
| Prometheus | Metriken sammeln |
| Grafana | Dashboards & Visualisierung |
| Alertmanager | Alerts via Microsoft Teams |
| node-exporter | Node-Metriken (CPU, RAM, Disk, Netzwerk) |
| kube-state-metrics | Pod/Deployment-Zustand |

**→ [Zur Anleitung](k3s-ansible/README.md)**

---

### radius-cert-automation

Automatisches TLS-Zertifikat-Deployment für Windows NPS (RADIUS) Server:

- **cert-manager** stellt Zertifikate von interner CA aus
- **CronJob** deployt täglich das Zertifikat via WinRM auf Windows
- **ArgoCD** verwaltet jeden Kunden als eigene Application
- Skalierbar für beliebig viele Kunden — jeder komplett isoliert

**→ [Zur Anleitung](radius-cert-automation/README.md)**

---

### windows-vms

Windows Server VMs auf Proxmox — Terraform erstellt die VM, Ansible konfiguriert sie.

| VM | Zweck | IP |
|---|---|---|
| nps-test | Windows NPS Server für RADIUS-Tests | 192.168.2.30 |

**→ [Zur Anleitung](windows-vms/nps-test/README.md)**

---