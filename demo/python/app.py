import asyncio
import logging
import os
import urllib.error
import urllib.request

import sentry_sdk
from fastapi import FastAPI, HTTPException
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DSN = os.environ.get("SENTRY_DSN")

if DSN:
    sentry_sdk.init(
        dsn=DSN,
        traces_sample_rate=1.0,
        integrations=[
            StarletteIntegration(transaction_style="endpoint"),
            FastApiIntegration(),
        ],
    )
else:
    logger.warning("SENTRY_DSN is not set; /demo/* will return 503")

app = FastAPI(title="Sentry demo (Python)")


def require_dsn():
    if not DSN:
        raise HTTPException(
            status_code=503,
            detail="SENTRY_DSN is not configured",
        )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/demo/exception")
def demo_unhandled_exception():
    require_dsn()
    raise RuntimeError("Demo: unhandled exception from Python")


@app.get("/demo/capture-exception")
def demo_capture_exception():
    require_dsn()
    raise ValueError("Demo: unhandled exception from capture-exception route")


@app.get("/demo/message")
def demo_message():
    require_dsn()
    sentry_sdk.capture_message("Demo: info message from Python", level="info")
    sentry_sdk.capture_message("Demo: warning from Python", level="warning")
    return {"ok": True, "event": "capture_message"}


@app.get("/demo/transaction")
def demo_transaction():
    require_dsn()
    with sentry_sdk.start_span(op="demo.task", name="outer"):
        with sentry_sdk.start_span(op="demo.subtask", name="inner"):
            pass
    return {"ok": True, "event": "transaction_spans"}


@app.get("/demo/breadcrumb")
def demo_breadcrumb():
    require_dsn()
    sentry_sdk.add_breadcrumb(
        category="demo",
        message="User opened breadcrumb demo",
        level="info",
    )
    raise RuntimeError("Demo: error after breadcrumb")


@app.get("/demo/context")
def demo_context():
    require_dsn()
    sentry_sdk.set_tag("demo_route", "context")
    sentry_sdk.set_user({"id": "demo-user-1", "email": "demo@example.local"})
    sentry_sdk.set_context("demo_payload", {"feature": "context-demo", "version": 1})
    sentry_sdk.capture_message("Demo: message with tags and context", level="info")
    return {"ok": True, "event": "context_and_message"}


def _auto_exception_interval_sec() -> int:
    raw = os.environ.get("DEMO_AUTO_EXCEPTION_INTERVAL_SEC")
    if raw is None or raw == "":
        return 60
    try:
        n = int(raw)
    except ValueError:
        return 0
    return n if n >= 0 else 0


@app.on_event("startup")
async def startup_auto_exception() -> None:
    if not DSN:
        return
    interval_sec = _auto_exception_interval_sec()
    if interval_sec <= 0:
        return

    async def tick() -> None:
        await asyncio.sleep(1)
        port = int(os.environ.get("PORT", "8080"))
        while True:
            await asyncio.sleep(interval_sec)

            def hit() -> None:
                try:
                    urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/demo/exception",
                        timeout=10,
                    )
                except (urllib.error.HTTPError, OSError):
                    pass

            await asyncio.to_thread(hit)

    asyncio.create_task(tick())
    logger.info(
        "Auto Sentry exceptions every %ss (set DEMO_AUTO_EXCEPTION_INTERVAL_SEC=0 to disable)",
        interval_sec,
    )
