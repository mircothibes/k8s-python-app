# restart-dev.ps1
# Kubernetes Dev Environment Restart Script (Windows PowerShell 5.1 compatible)
# Project: k8s-python-app

param(
  [switch]$Reset,             # Deletes and recreates Kind cluster 'dev'
  [switch]$NoOpen,            # Do not auto-open browser
  [switch]$SkipPortForward,   # Do not start port-forward
  [int]$TrafficCount = 0      # Generate N requests to create traffic (0 = disabled)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------- logging helpers ----------
function LogInfo ([string]$m){ Write-Host "[INFO ] $m" -ForegroundColor Cyan }
function LogWarn ([string]$m){ Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function LogError([string]$m){ Write-Host "[ERROR] $m" -ForegroundColor Red }
function Die    ([string]$m){ LogError $m; exit 1 }

# Run a command in a clean subshell and fail if exit code != 0
function Exec([string]$cmd){
  Write-Host "-> $cmd" -ForegroundColor DarkGray
  $old = $global:LASTEXITCODE
  $global:LASTEXITCODE = 0
  & powershell -NoProfile -Command $cmd
  if ($LASTEXITCODE -ne 0){ Die "Command failed: $cmd" }
  $global:LASTEXITCODE = $old
}

# Test if a local TCP port is in use
function Test-PortUsed([int]$Port){
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.Connect("127.0.0.1",$Port)
    $client.Close()
    return $true
  } catch {
    return $false
  }
}

# ---------- bootstrap ----------
# Move to repo root (where this script lives)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

# Activate .venv if present (not required for kubectl/helm)
if (Test-Path ".\.venv\Scripts\Activate.ps1"){
  LogInfo "Activating Python virtual environment (.venv)..."
  . .\.venv\Scripts\Activate.ps1
} else {
  LogWarn ".venv not found (skipping)."
}

# Tooling checks
LogInfo "Checking Docker Desktop..."
try { docker info *> $null } catch { Die "Docker Desktop is not running. Start Docker and run this script again." }

kubectl version --client *> $null
if ($LASTEXITCODE -ne 0){ Die "kubectl is not available in PATH." }

kind version *> $null
if ($LASTEXITCODE -ne 0){ Die "kind is not available in PATH." }

helm version --short *> $null
if ($LASTEXITCODE -ne 0){ Die "helm is not available in PATH." }

# ---------- Kind cluster ----------
$clusterName = "dev"
if ($Reset){
  LogWarn "Reset requested -> deleting cluster '$clusterName' if it exists..."
  cmd /c "kind delete cluster --name $clusterName >nul 2>nul"
}
$clusters = & kind get clusters
if (-not ($clusters -match "^\s*$clusterName\s*$")){
  LogInfo "Creating Kind cluster '$clusterName'..."
  if (Test-Path ".\kind-config.yaml"){
    Exec "kind create cluster --name $clusterName --config kind-config.yaml"
  } else {
    Exec "kind create cluster --name $clusterName"
  }
  Start-Sleep -Seconds 8
} else {
  LogInfo "Cluster '$clusterName' already exists."
}
Exec "kubectl config use-context kind-dev"
Exec "kubectl cluster-info"

# ---------- Helm: ingress-nginx ----------
LogInfo "Adding/updating Helm repos..."
Exec "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx"
Exec "helm repo update"

LogInfo "Installing/upgrading ingress-nginx (metrics enabled, hostPort enabled)..."
Exec @"
helm upgrade --install ingress ingress-nginx/ingress-nginx `
  -n ingress-nginx --create-namespace `
  --set controller.hostPort.enabled=true `
  --set controller.metrics.enabled=true `
  --set controller.metrics.serviceMonitor.enabled=true `
  --set controller.metrics.serviceMonitor.namespace=monitoring
"@

Exec "kubectl -n ingress-nginx rollout status deploy/ingress-ingress-nginx-controller --timeout=180s"

# ---------- Namespaces ----------
LogInfo "Ensuring namespaces exist..."
try { kubectl get ns demo -o name *> $null } catch {}
if ($LASTEXITCODE -ne 0){ Exec "kubectl create ns demo" }

try { kubectl get ns monitoring -o name *> $null } catch {}
if ($LASTEXITCODE -ne 0){ Exec "kubectl create ns monitoring" }

# ---------- App Secret (DATABASE_URL) ----------
# This secret is required by the app Deployment.
LogInfo "Ensuring app-secret (DATABASE_URL) exists..."
@"
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: demo
type: Opaque
stringData:
  DATABASE_URL: postgresql://appuser:NvUMiIEuwctVra1KBlqp@postgres.demo.svc.cluster.local:5432/appdb
"@ | kubectl apply -f - | Out-Null

# ---------- Docker image: build and load into Kind ----------
LogInfo "Building local Docker image 'k8s-python-app:dev'..."
Exec "docker build -t k8s-python-app:dev ."

LogInfo "Loading image into Kind cluster 'dev'..."
Exec "kind load docker-image k8s-python-app:dev --name dev"

# ---------- Apply manifests (ordered) ----------
LogInfo "Applying Kubernetes manifests..."
function ApplyIfPresent($path){
  if (Test-Path $path){ Exec "kubectl apply -f `"$path`"" }
  else { LogWarn "File not found, skipping: $path" }
}

ApplyIfPresent "k8s\namespace.yaml"
ApplyIfPresent "k8s\postgres-secret.yaml"
ApplyIfPresent "k8s\postgres-pvc.yaml"
ApplyIfPresent "k8s\postgres-deployment.yaml"
ApplyIfPresent "k8s\postgres-service.yaml"
ApplyIfPresent "k8s\app-configmap.yaml"
ApplyIfPresent "k8s\app-deployment.yaml"
ApplyIfPresent "k8s\app-service.yaml"
ApplyIfPresent "k8s\ingress.yaml"

# Ensure Service port has a name "http" (useful for probes/ingress)
try {
  $svc = kubectl -n demo get svc app-svc -o json | ConvertFrom-Json
  if (-not $svc.spec.ports[0].name){
    LogInfo "Patching app-svc to add port name 'http'..."
    Exec "kubectl -n demo patch svc app-svc -p '{""spec"":{""ports"":[{""port"":80,""targetPort"":8080,""protocol"":""TCP"",""name"":""http""}]}}'"
  }
} catch {
  LogWarn "Could not verify/patch app-svc: $_"
}

# ---------- Wait for app ----------
LogInfo "Waiting for app deployment to become Ready..."
try {
  Exec "kubectl -n demo rollout status deploy/app --timeout=240s"
} catch {
  LogWarn "App did not become Ready within timeout. Continue and inspect logs if needed."
}

# ---------- Port-forward Ingress ----------
[int]$chosenPort = 18080
if (-not $SkipPortForward) {
  if (Test-PortUsed 18080){ $chosenPort = 18081 }
  $pfCmd = "kubectl -n ingress-nginx port-forward svc/ingress-ingress-nginx-controller $chosenPort:80"
  LogInfo "Starting Ingress port-forward on http://127.0.0.1:$chosenPort ..."
  Start-Process powershell -ArgumentList "-NoExit","-Command",$pfCmd | Out-Null
  Start-Sleep -Seconds 2
} else {
  LogWarn "SkipPortForward = true (skipping port-forward)."
}

# ---------- Optional: generate test traffic ----------
if ($TrafficCount -gt 0) {
  LogInfo "Generating $TrafficCount requests of test traffic inside the cluster..."
  $trafficCmd = @"
i=1
while [ \$i -le $TrafficCount ]; do
  curl -s -o /dev/null -H 'Host: app.127.0.0.1.nip.io' http://ingress-ingress-nginx-controller.ingress-nginx.svc/
  i=\$((i+1))
done
echo done
"@
  try {
    Exec "kubectl -n demo run curl --rm -it --image=curlimages/curl:8.8.0 --restart=Never -- /bin/sh -lc `"$trafficCmd`""
  } catch {
    LogWarn "Traffic command could not run now (pods may be pending)."
  }
}

# ---------- Auto-open browser (health) ----------
if (-not $NoOpen -and -not $SkipPortForward) {
  try {
    Start-Sleep -Seconds 2
    Start-Process ("http://127.0.0.1:{0}/healthz" -f $chosenPort)
  } catch {
    LogWarn "Could not auto-open browser."
  }
}

# ---------- Summary ----------
Write-Host ""
LogInfo  "Environment is ready."
Write-Host "Endpoints:"
Write-Host ("  - Ingress (requires Host header): http://127.0.0.1:{0}/" -f $chosenPort)
Write-Host ("  - Health:                         http://127.0.0.1:{0}/healthz" -f $chosenPort)
Write-Host ("  - Ready:                          http://127.0.0.1:{0}/readyz"  -f $chosenPort)
Write-Host ""
Write-Host "If health returns 503, check pod status:"
Write-Host "  kubectl -n demo get pods -o wide"
Write-Host "  kubectl -n demo logs -l app=app --tail=100"
Write-Host ""
