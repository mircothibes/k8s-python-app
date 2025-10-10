# 🚀 k8s-python-app

An example application built with **Python (FastAPI)**, containerized using **Docker**, and orchestrated with **Kubernetes** through **Kind** (Kubernetes in Docker).  
The project also includes a **PostgreSQL** database, **NGINX Ingress Controller**, and local development setup for learning cloud-native applications.

---

## 🧩 Overview

This repository was created to **learn and demonstrate a full Kubernetes application lifecycle**:
- Building and packaging an app with Docker  
- Deploying backend services with manifests (ConfigMap, Secret, PVC, Deployment, Service, Ingress)  
- Integrating a database (PostgreSQL)  
- Setting up monitoring (Prometheus & Grafana)  
- Testing local Kubernetes clusters using Kind

---

## 🧰 Tech Stack

| Tool | Purpose |
|------|----------|
| **Python 3.12 + FastAPI** | Application framework |
| **PostgreSQL** | Relational database |
| **Docker** | Containerization |
| **Kubernetes (Kind)** | Local cluster for development |
| **Helm** | Package manager for installing Ingress NGINX |
| **Prometheus + Grafana** | Observability stack (optional) |

---

## 📂 Project structure
```bash
k8s-python-app/
│
├── app/                        # Application source code
│   ├── __init__.py
│   └── main.py                 # FastAPI app with health endpoints
│
├── k8s/                        # Kubernetes manifests
│   ├── app-configmap.yaml
│   ├── app-deployment.yaml
│   ├── app-service.yaml
│   ├── app-secret.yaml
│   ├── postgres-deployment.yaml
│   ├── postgres-pvc.yaml
│   ├── postgres-service.yaml
│   ├── namespace.yaml
│   └── ingress.yaml
│
├── monitoring/                 # Optional observability setup
│   ├── app-servicemonitor.yaml
│   ├── ingress-servicemonitor.yaml
│   ├── app-alerts.yaml
│   └── app-recording-rules.yaml
│
├── Dockerfile
├── kind-config.yaml
├── loadgen-job.yaml            # Load generator to simulate traffic
├── requirements.txt
└── README.md
 ```
---
## ⚙️ Prerequisites

Make sure you have the following installed:
- Docker Desktop
- Kind
- Kubectl
- Helm

---

## ▶️ How to run locally

1. Create a Kind cluster
```bash
kind create cluster --name dev --config kind-config.yaml
```

2. Install NGINX ingress controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true
```

3. Build and load Docker image into Kind
```bash
docker build -t k8s-python-app:dev .
kind load docker-image k8s-python-app:dev --name dev
```

4. Apply Kubernetes manifests
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-configmap.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/ingress.yaml
```

5. Test the application
- Inside the cluster:
```bash
kubectl -n demo run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://app-svc/healthz
```
- Via browser (with DNS/hosts configured):
```bash
http://app.localtest.me:8080/
http://app.localtest.me:8080/healthz
http://app.localtest.me:8080/readyz
```

---

## 📖 API endpoints

- / → returns {"message": "Hello, Kubernetes!"}
- /healthz → returns {"status": "ok"}
- /readyz → returns {"status": "ready"}

---

## 🎯 Project goals

- Practice Kubernetes and Docker with Python
- Learn how to configure a local cluster with Kind
- Deploy and link PostgreSQL database
- Configure Ingress routing
- Integrate Prometheus + Grafana for observability
- Understand how to use an Ingress Controller (NGINX)
- Simulate traffic using a Job (loadgen)

---

## 📜 License

This project is intended for learning purposes. Free to use and modify.

---

## 👤 Author

**Marcos Vinicius Thibes Kemer**

---


