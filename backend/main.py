"""
main.py — Samantha AI FastAPI Backend
Run: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Samantha AI Backend", version="1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────

from samantha_brain import router as brain_router
app.include_router(brain_router)

try:
    from schedule_api import router as schedule_router
    app.include_router(schedule_router)
except ImportError:
    pass  # schedule_api optional

# ── Health check ──────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {"status": "Samantha backend running", "version": "1.0"}

@app.get("/health")
def health():
    return {"status": "ok"}


# ── Run directly ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
