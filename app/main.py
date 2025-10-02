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

