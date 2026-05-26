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

