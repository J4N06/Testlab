# ISE-Testlab Proxmox



---

## Übersicht

```
Testlab/
└── k3s-ansible/        # k3s Kubernetes-Cluster
    ├── terraform/      # VM-Erstellung auf Proxmox
    ├── roles/          # Ansible-Rollen
    └── argocd-apps/    # GitOps-Applikationen
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
| Alertmanager | Alert-Verwaltung |
| node-exporter | Node-Metriken (CPU, RAM, Disk, Netzwerk) |
| kube-state-metrics | Pod/Deployment-Zustand |

**→ [Zur Anleitung](k3s-ansible/README.md)**



## Schnellstart

## Services

| Service | URL | Login |
|---|---|---|
| ArgoCD | https://192.168.2.21:30443 | admin / siehe Ansible-Output |
| Grafana | http://192.168.2.21:30300 | admin / admin |

---

## Netzwerk

| Host | IP |
|---|---|
| Gateway | 192.168.2.1 |
| Proxmox | 192.168.2.12 |
| k3s Master | 192.168.2.21 |
| k3s Worker 1 | 192.168.2.22 |
| k3s Worker 2 | 192.168.2.23 |

