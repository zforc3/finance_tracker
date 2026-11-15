from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from app.api.v1.api import api_router
from app.core.config import settings

app = FastAPI(
    title="Finance Tracker Offline-First API",
    version="1.0.0",
    description="API for Finance Tracker backend supporting offline-first operations, outbox batch push, idempotent sync, and optimistic concurrency control (OCC)."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(HTTPException)
async def custom_http_exception_handler(request: Request, exc: HTTPException):
    if isinstance(exc.detail, dict) and "error_code" in exc.detail:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error_code": "HTTP_ERROR",
            "message": str(exc.detail)
        }
    )


@app.get("/health", tags=["health"])
def health_check():
    return {"status": "ok"}


app.include_router(api_router, prefix=settings.API_V1_PREFIX)
