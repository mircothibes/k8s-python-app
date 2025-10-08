# restart-dev.ps1
# Kubernetes Dev Environment Restart Script (Windows PowerShell 5.1 compatible)
# Project: k8s-python-app

param(
  [switch]$Reset,             # Deletes and recreates Kind cluster 'dev'
  [switch]$SkipPortForward,   # Do not start port-forwards
  [int]$TrafficCount = 300    # Number of requests to generate as test traffic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------- helpers ----------
function LogInfo ([string]$m){ Write-Host "[INFO ] $m" -ForegroundColor Cyan }
function LogWarn ([string]$m){ Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function LogError([string]$m){ Write-Host "[ERROR] $m" -ForegroundColor Red }
function Die    ([string]$m){ LogError $m; exit 1 }

function Exec([string]$cmd){
  Write-Host "-> $cmd" -ForegroundColor DarkGray
  $old = $global:LASTEXITCODE
  $global:LASTEXITCODE = 0
  & powershell -NoProfile -Command $cmd
  if ($LASTEXITCODE -ne 0){ Die "Command failed: $cmd" }
  $global:LASTEXITCODE = $old
}

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
# Move to repo root (where this script is)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

# Activate .venv if present (not required for kubectl/helm)
if (Test-Path ".\.venv\Scripts\Activate.ps1"){
  LogInfo "Activating Python virtual environment (.venv)..."
  . .\.venv\Scripts\Activate.ps1
} else {
  LogWarn ".venv not found (skipping)."
}

# Docker check
LogInfo "Checking Docker Desktop..."
try { docker info *> $null } catch { Die "Docker Desktop is not running. Start Docker and run this script again." }

# Kind cluster
$clusterName = "dev"
if ($Reset){
  LogWarn "Reset requested -> deleting cluster '$clusterName' if it exists..."
  & kind delete cluster --name $clusterName *> $null
}
$clusters = & kind get clusters
if (-not ($clusters -match "^\s*$clusterName\s*$")){
  LogInfo "Creating Kind cluster '$clusterName'..."
  if (Test-Path ".\kind-config.yaml"){
    Exec "kind create cluster --name $clusterName --config kind-config.yaml"
  } else {
    Exec "kind create cluster --name $clusterName"
  }
  Start-Sleep -Seconds 10
} else {
  LogInfo "Cluster '$clusterName' already exists."
}
Exec "kubectl cluster-info"

# ---------- ensure namespaces ----------
LogInfo "Ensuring namespaces exist..."
try { kubectl get ns demo -o name *> $null } catch { }
if ($LASTEXITCODE -ne 0) { Exec "kubectl create ns demo" }
try { kubectl get ns monitoring -o name *> $null } catch { }
if ($LASTEXITCODE -ne 0) { Exec "kubectl create ns monitoring" }

# ---------- apply manifests ----------
LogInfo "Applying Kubernetes manifests..."
$files = @(
  "k8s\namespace.yaml",
  "k8s\postgres-secret.yaml",
  "k8s\postgres-pvc.yaml",
  "k8s\postgres-deployment.yaml",
  "k8s\postgres-service.yaml",
  "k8s\app-configmap.yaml",
  "k8s\app-deployment.yaml",
  "k8s\app-service.yaml",
  "k8s\ingress.yaml"
)

foreach($f in $files){
  if (Test-Path $f){
    Exec "kubectl apply -f `"$f`""
  } else {
    LogWarn "File not found: $f"
  }
}

# Ensure Service port has a name (some tooling and ingress prefer it)
try {
  $svc = kubectl -n demo get svc app-svc -o json | ConvertFrom-Json
  if (-not $svc.spec.ports[0].name){
    LogInfo "Patching app-svc to add port name 'http'..."
    Exec "kubectl -n demo patch svc app-svc -p '{""spec"":{""ports"":[{""port"":80,""targetPort"":8080,""protocol"":""TCP"",""name"":""http""}]}}'"
  }
} catch {
  LogWarn "Could not verify/patch app-svc: $_"
}

# ---------- wait for app ----------
LogInfo "Waiting for app deployment to become Ready..."
try {
  Exec "kubectl -n demo rollout status deploy/app --timeout=180s"
} catch {
  LogWarn "App did not become Ready within timeout. Continue and inspect logs if needed."
}

# ---------- port-forward ingress (optional) ----------
if (-not $SkipPortForward) {
  LogInfo "Starting Ingress port-forward in a separate PowerShell window..."
  $ingressPort = 18080
  if (Test-PortUsed 18080){ $ingressPort = 18081 }
  $pfCmd = "kubectl -n ingress-nginx port-forward svc/ingress-ingress-nginx-controller $ingressPort:80"
  Start-Process powershell -ArgumentList "-NoExit","-Command",$pfCmd | Out-Null
  Start-Sleep -Seconds 2
  LogInfo ("Ingress available at http://127.0.0.1:{0} (remember Host header: app.127.0.0.1.nip.io)" -f $ingressPort)
} else {
  LogWarn "SkipPortForward=true (skipping port-forward)."
}

# ---------- generate test traffic ----------
LogInfo "Generating test traffic from inside the cluster..."
$trafficCmd = @"
i=1
while [ \$i -le $TrafficCount ]; do
  curl -s -o /dev/null -H 'Host: app.127.0.0.1.nip.io' http://ingress-ingress-nginx-controller.ingress-nginx.svc/
  i=\$((i+1))
done
echo done
"@

try{
  Exec "kubectl -n demo run curl --rm -it --image=curlimages/curl:8.8.0 --restart=Never -- /bin/sh -lc `"$trafficCmd`""
}catch{
  LogWarn "Traffic command could not run now (pods may be pending). You can run it later with the same command."
}

# ---------- summary ----------
Write-Host ""
LogInfo  "Environment is ready."
Write-Host "Useful commands:"
Write-Host "  - App via ingress (Host header required): http://127.0.0.1:18080/   or   http://127.0.0.1:18081/"
Write-Host "  - Health: http://127.0.0.1:18080/healthz"
Write-Host "  - Grafana:    kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
Write-Host "  - Prometheus: kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
Write-Host ""
