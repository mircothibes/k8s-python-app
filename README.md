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
 ```

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
- Integrate a simple application with PostgreSQL
- Understand how to use an Ingress Controller (NGINX)

---

## 📜 License

This project is intended for learning purposes. Free to use and modify.

---

## 👤 Author

**Marcos Vinicius Thibes Kemer**

---


