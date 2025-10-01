from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI()

@app.get("/")
def root():
    return {"message": "Hello, Kubernetes!"}

@app.get("/livez")
def livez():
    return JSONResponse(content={"status": "ok"})

@app.get("/readyz")
def readyz():
    return {"ready": True}

