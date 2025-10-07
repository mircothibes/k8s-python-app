"""
FastAPI application for a containerized demo deployed on Kubernetes.

Features
--------
- Root endpoint (`/`) that returns a simple JSON message.
- Liveness probe (`/livez`) used by Kubernetes to check if the process is alive.
- Readiness probe (`/readyz`) used by Kubernetes to decide if the Pod can receive traffic.
- Prometheus metrics at (`/metrics`) via `prometheus-fastapi-instrumentator`.

Intended Use
------------
This service is built to run behind an Ingress (nginx) inside a local Kind cluster
or on GKE. Health endpoints are designed to be wired to Kubernetes probes, and
metrics are scraped by Prometheus (e.g., kube-prometheus-stack) and visualized in Grafana.

Notes
-----
- The metrics endpoint is mounted at `/metrics` (default content-type: text/plain).
- No persistent state is stored here; database connectivity (if any) is provided
  via environment variables (e.g., `DATABASE_URL`) through ConfigMaps/Secrets.

"""
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()

# instrument and expose /metrics
Instrumentator().instrument(app).expose(app, endpoint="/metrics")

@app.get("/")
def root():
    return {"message": "Hello, Kubernetes!"}

@app.get("/livez")
def livez():
    return JSONResponse(content={"status": "ok"})

@app.get("/readyz")
def readyz():
    return {"ready": True}

@app.get("/healthz")
def healthz():
    return {"status": "ok"}