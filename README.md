# 🚀 k8s-python-app

An example application built with **Python (FastAPI)**, containerized using **Docker**, and orchestrated with **Kubernetes** through **Kind** (Kubernetes in Docker).  
The project also includes a **PostgreSQL** database, **NGINX Ingress Controller**, and local development setup for learning cloud-native applications.

---

## 📌 Tech stack
- [Python 3.12 + FastAPI](https://fastapi.tiangolo.com/) – simple API
- [Docker](https://www.docker.com/) – containerization
- [Kind](https://kind.sigs.k8s.io/) – local Kubernetes cluster
- [Kubectl](https://kubernetes.io/docs/tasks/tools/) – Kubernetes CLI
- [Helm](https://helm.sh/) – package manager for Kubernetes (used for ingress-nginx)
- [PostgreSQL](https://www.postgresql.org/) – relational database

---

## 📂 Project structure
```bash
k8s-python-app/
│── app/
│   ├── __init__.py
│   └── main.py          # FastAPI application
│
│── k8s/                 # Kubernetes manifests
│   ├── app-configmap.yaml
│   ├── app-deployment.yaml
│   ├── app-service.yaml
│   ├── postgres-secret.yaml
│   ├── postgres-deployment.yaml
│   ├── postgres-service.yaml
│   ├── namespace.yaml
│   └── ingress.yaml
│
│── Dockerfile
│── requirements.txt
│── kind-config.yaml
└── README.md
 
 ---

