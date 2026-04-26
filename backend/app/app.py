from .routers import furniture, designs, preferences, agent, scans
from .db import close_client, check_connection
from .logging import configure_logging, log
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from dotenv import load_dotenv
load_dotenv()  # Load environment variables from .env file


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()
    log.info("startup")
    yield
    await close_client()
    log.info("shutdown")


app = FastAPI(title="Interior Design LiDAR API",
              version="0.1.0", lifespan=lifespan)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    log.error(
        "request_validation_failed",
        path=request.url.path,
        method=request.method,
        errors=exc.errors(),
    )
    return JSONResponse(status_code=422, content={"detail": exc.errors()})


app.include_router(furniture.router)
app.include_router(designs.router)
app.include_router(preferences.router)
app.include_router(agent.router)
app.include_router(scans.router)


@app.get("/health")
async def health():
    db = await check_connection()
    return {"api": "ok", "db": db}
