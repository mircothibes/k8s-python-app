<# ==============================
    Kubernetes Dev Environment Restart Script
    Project : k8s-python-app
    Author  : Marcos Vinicius Thibes Kemer
    Notes   : Windows PowerShell 5+ / PowerShell 7+
   =============================== #>

param(
  [switch]$Reset,
  [switch]$SkipTraffic,
  [switch]$SkipPortForward
)

# ---------- helper: colored log ----------
function LogInfo($msg){ Write-Host $msg -ForegroundColor Cyan }
function LogWarn($msg){ Write-Host $msg -ForegroundColor Yellow }
function LogOk  ($msg){ Write-Host $msg -ForegroundColor Green }
function LogErr ($msg){ Write-Host $msg -ForegroundColor Red }

# ---------- helper: run and fail if error ----------
function Run($cmd){
  LogInfo "» $cmd"
  iex $cmd
  if ($LASTEXITCODE -ne 0) {
    LogErr "✖ Command failed (exit $LASTEXITCODE): $cmd"
    exit 1
  }
}

# ---------- helper: returns $true if TCP port is in use ----------
function Test-PortUsed([int]$Port){
  try {
    $c = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    return [bool]$c
  } catch { return $false }
}

# ---------- helper: background port-forward if port free ----------
function Start-PortForward($ns, $svc, [int]$local, [int]$remote){
  if (Test-PortUsed $local) {
    LogWarn "⚠ Port $local already in use. Skipping port-forward for $svc."
    return
  }
  $args = "kubectl -n $ns port-forward svc/$svc $local`:$remote"
  LogInfo "⤴ Starting port-forward: $args"
  Start-Process powershell -WindowStyle Minimized -ArgumentList $args | Out-Null
}

# ---------- 0) Move to repo root ----------
$repo = Split-Path -Parent $PSCommandPath
if (-not $repo) { $repo = Get-Location }
Set-Location $repo
LogInfo  "🚀 Starting Kubernetes development environment at: $repo"

# ---------- 1) Activate Python venv (optional – safe if missing) ----------
if (Test-Path ".\.venv\Scripts\Activate.ps1") {
  LogInfo "🐍 Activating Python virtual environment (.venv)..."
  & .\.venv\Scripts\Activate.ps1
} else {
  LogWarn "⚠ No .venv found. Skipping Python activation."
}

# ---------- 2) Basic tooling checks ----------
LogInfo "🔎 Checking Docker Desktop status..."
docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  LogErr "✖ Docker Desktop is not running. Please start Docker and run this script again."
  exit 1
}
LogOk "✔ Docker is running."

kubectl version --client --short > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  LogErr "✖ kubectl not found in PATH."
  exit 1
}
kind version > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  LogErr "✖ kind not found in PATH."
  exit 1
}
helm version --short > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  LogErr "✖ helm not found in PATH."
  exit 1
}

# ---------- 3) Create / reset Kind cluster ----------
$clusterExists = kind get clusters | Select-String -SimpleMatch "dev"
if ($Reset -and $clusterExists){
  LogWarn "🧨 Reset requested: deleting cluster 'dev'..."
  Run "kind delete cluster --name dev"
  $clusterExists = $null
}

if (-not $clusterExists){
  LogWarn "⚙ Creating Kind cluster 'dev'..."
  $kindCfg = Join-Path $repo "kind-config.yaml"
  if (Test-Path $kindCfg) { Run "kind create cluster --name dev --config `"$kindCfg`"" }
  else { Run "kind create cluster --name dev" }
  LogInfo "⏳ Waiting Kubernetes API to settle..."
  Start-Sleep -Seconds 10
} else {
  LogOk "✔ Cluster 'dev' already exists."
}

# ---------- 4) Helm: ingress-nginx and kube-prometheus-stack (idempotent) ----------
LogInfo "📦 Adding / updating Helm repos..."
Run "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx"
Run "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
Run "helm repo update"

LogInfo "🧭 Installing/Upgrading ingress-nginx (with metrics enabled)..."
Run @"
helm upgrade --install ingress ingress-nginx/ingress-nginx `
  -n ingress-nginx --create-namespace `
  --set controller.hostPort.enabled=true `
  --set controller.metrics.enabled=true `
  --set controller.metrics.serviceMonitor.enabled=true `
  --set controller.metrics.serviceMonitor.namespace=monitoring
"@

LogInfo "📈 Installing/Upgrading kube-prometheus-stack..."
Run @"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack `
  -n monitoring --create-namespace `
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
"@

# ---------- 5) Ensure namespaces ----------
LogInfo "📁 Ensuring application namespaces exist..."
kubectl get ns demo -o name > $null 2>&1  ; if ($LASTEXITCODE -ne 0) { Run "kubectl create ns demo" }
kubectl get ns monitoring -o name > $null 2>&1 ; if ($LASTEXITCODE -ne 0) { Run "kubectl create ns monitoring" }

# ---------- 6) Re-apply your Kubernetes manifests (ordered) ----------
function ApplyIfPresent($path){
  if (Test-Path $path) { Run "kubectl apply -f `"$path`"" }
  else { LogWarn "⚠ File not found, skipping: $path" }
}

LogInfo "📜 Applying Kubernetes manifests..."

# Base app resources
ApplyIfPresent "k8s\namespace.yaml"
ApplyIfPresent "k8s\postgres-secret.yaml"
ApplyIfPresent "k8s\postgres-pvc.yaml"
ApplyIfPresent "k8s\postgres-deployment.yaml"
ApplyIfPresent "k8s\postgres-service.yaml"
ApplyIfPresent "k8s\app-configmap.yaml"
ApplyIfPresent "k8s\app-deployment.yaml"
ApplyIfPresent "k8s\app-service.yaml"
ApplyIfPresent "k8s\ingress.yaml"

# Monitoring add-ons (if you keep them as files)
ApplyIfPresent "monitoring\ingress-servicemonitor.yaml"
ApplyIfPresent "monitoring\app-recording-rules.yaml"
ApplyIfPresent "monitoring\app-alerts.yaml"

# ---------- 7) Wait for pods ----------
LogInfo "⏳ Waiting for app pods to be ready..."
Run "kubectl -n demo rollout status deploy/app --timeout=120s"
LogOk "✔ App is ready."

# ---------- 8) Optional: generate traffic (use your file if present, else inline job) ----------
if (-not $SkipTraffic) {
  $trafficFile = "monitoring\traffic-gen.yaml"
  if (Test-Path $trafficFile) {
    LogInfo "🚦 Applying traffic generator from $trafficFile ..."
    Run "kubectl apply -f `"$trafficFile`""
  } else {
    LogInfo "🚦 Creating inline traffic generator Job (curl 300 requests)..."
    @"
apiVersion: batch/v1
kind: Job
metadata:
  name: traffic
  namespace: demo
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: curl
        image: curlimages/curl:8.8.0
        command: ["/bin/sh","-lc"]
        args:
          - >
            i=0; while [ \$i -lt 300 ];
            do curl -s -o /dev/null -H 'Host: app.127.0.0.1.nip.io'
               http://ingress-ingress-nginx-controller.ingress-nginx.svc/;
               i=\$((i+1));
            done; echo done;
"@ | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { LogWarn "⚠ Traffic job apply reported a non-zero exit." }
  }
}

# ---------- 9) Safe port-forwards ----------
if (-not $SkipPortForward) {
  # Grafana 3000 -> 80 (monitoring namespace)
  Start-PortForward -ns "monitoring" -svc "monitoring-grafana" -local 3000 -remote 80

  # Prometheus 9090 -> 9090
  Start-PortForward -ns "monitoring" -svc "monitoring-kube-prometheus-prometheus" -local 9090 -remote 9090

  # Expose ingress-nginx to the host for quick curl tests (choose 18080 or 18081)
  $ingressPort = (Test-PortUsed 18080) ? 18081 : 18080
  Start-PortForward -ns "ingress-nginx" -svc "ingress-ingress-nginx-controller" -local $ingressPort -remote 80
  LogOk "✔ Ingress port-forward on http://127.0.0.1:$ingressPort/"
}

# ---------- 10) Final hints ----------
LogOk  "✅ Environment is up!"
LogInfo "🔗 Grafana:     http://localhost:3000  (user: admin, pass: prom-operator unless changed)"
LogInfo "🔗 Prometheus:  http://localhost:9090"
LogInfo "🔗 Ingress test: curl -H 'Host: app.127.0.0.1.nip.io' http://127.0.0.1:18080/ (or :18081)"
