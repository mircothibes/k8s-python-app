# ==========================================
# 🐳 Kubernetes Dev Environment Restart Script
# Project: k8s-python-app
# Author: Marcos Vinicius Thibes Kemer
# ==========================================

Write-Host "🚀 Starting Kubernetes development environment..." -ForegroundColor Cyan

# 1️⃣ Go to the project directory
Set-Location "C:\Users\mirco\Desktop\TI\New Projects 2025\k8s-python-app"

# 2️⃣ Activate Python virtual environment
Write-Host "🧠 Activating Python virtual environment (.venv)..." -ForegroundColor Yellow
& .\.venv\Scripts\Activate.ps1

# 3️⃣ Check if Docker is running
Write-Host "🐋 Checking Docker Desktop status..." -ForegroundColor Yellow
docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker Desktop is not running. Please open Docker and re-run this script." -ForegroundColor Red
    exit
}

# 4️⃣ Check if Kind cluster exists
$cluster = kind get clusters | Select-String "dev"
if (-not $cluster) {
    Write-Host "⚙️  Cluster 'dev' not found. Creating..." -ForegroundColor Yellow
    kind create cluster --name dev --config kind-config.yaml
} else {
    Write-Host "✅ Cluster 'dev' already exists." -ForegroundColor Green
}

# 5️⃣ Display cluster info
kubectl cluster-info

# 6️⃣ Reapply main Kubernetes manifests
Write-Host "📦 Applying main Kubernetes manifests..." -ForegroundColor Yellow
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-configmap.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/ingress.yaml

# 7️⃣ Generate test traffic (for Prometheus & Grafana metrics)
Write-Host "📈 Generating test traffic..." -ForegroundColor Yellow
@"
apiVersion: batch/v1
kind: Job
metadata:
  name: gen-traffic
  namespace: demo
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: curl
        image: curlimages/curl:8.8.0
        command: ["/bin/sh","-lc"]
        args:
          - |
            for i in $$(seq 1 200); do
              curl -s -o /dev/null -H "Host: app.127.0.0.1.nip.io" \
                http://ingress-ingress-nginx-controller.ingress-nginx.svc/;
              sleep 0.05;
            done
            echo done
"@ | kubectl apply -f -

# 8️⃣ Open Grafana and Prometheus (background)
Start-Process powershell -ArgumentList "kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80" -WindowStyle Minimized
Start-Process powershell -ArgumentList "kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090" -WindowStyle Minimized

Write-Host "✅ Environment is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Grafana →  http://localhost:3000   (user: admin | pass: prom-operator)"
Write-Host "📊 Prometheus → http://localhost:9090"
Write-Host "💻 App → http://127.0.0.1:8080/"
Write-Host ""
Write-Host "⚙️  Press Ctrl+C to stop port-forward sessions when done."
