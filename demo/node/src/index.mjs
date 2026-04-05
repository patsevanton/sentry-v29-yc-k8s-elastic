import "./instrument.mjs";
import express from "express";
import * as Sentry from "@sentry/node";

const dsn = process.env.SENTRY_DSN;

const app = express();

function requireDsn(res) {
  if (!dsn) {
    res.status(503).json({ detail: "SENTRY_DSN is not configured" });
    return false;
  }
  return true;
}

app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/demo/exception", (req, res) => {
  if (!requireDsn(res)) return;
  throw new Error("Demo: unhandled exception from Node");
});

app.get("/demo/capture-exception", async (req, res) => {
  if (!requireDsn(res)) return;
  try {
    throw new Error("Demo: caught then reported");
  } catch (e) {
    Sentry.captureException(e);
  }
  res.json({ ok: true, event: "capture_exception" });
});

app.get("/demo/message", (req, res) => {
  if (!requireDsn(res)) return;
  Sentry.captureMessage("Demo: info message from Node", "info");
  Sentry.captureMessage("Demo: warning from Node", "warning");
  res.json({ ok: true, event: "capture_message" });
});

app.get("/demo/transaction", async (req, res) => {
  if (!requireDsn(res)) return;
  await Sentry.startSpan({ name: "outer", op: "demo.task" }, async () => {
    await Sentry.startSpan({ name: "inner", op: "demo.subtask" }, async () => {
      await Promise.resolve();
    });
  });
  res.json({ ok: true, event: "transaction_spans" });
});

app.get("/demo/breadcrumb", (req, res) => {
  if (!requireDsn(res)) return;
  Sentry.addBreadcrumb({
    category: "demo",
    message: "User opened breadcrumb demo",
    level: "info",
  });
  throw new Error("Demo: error after breadcrumb");
});

app.get("/demo/context", (req, res) => {
  if (!requireDsn(res)) return;
  Sentry.setTag("demo_route", "context");
  Sentry.setUser({ id: "demo-user-1", email: "demo@example.local" });
  Sentry.setContext("demo_payload", { feature: "context-demo", version: 1 });
  Sentry.captureMessage("Demo: message with tags and context", "info");
  res.json({ ok: true, event: "context_and_message" });
});

Sentry.setupExpressErrorHandler(app);

function parseAutoExceptionIntervalSec() {
  const raw = process.env.DEMO_AUTO_EXCEPTION_INTERVAL_SEC;
  if (raw === undefined || raw === "") return 60;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

const port = Number(process.env.PORT) || 8080;
app.listen(port, "0.0.0.0", () => {
  console.log(`Listening on ${port}`);
  const intervalSec = parseAutoExceptionIntervalSec();
  if (dsn && intervalSec > 0) {
    setInterval(() => {
      Sentry.captureException(
        new Error("Demo: automatic periodic exception from Node"),
      );
    }, intervalSec * 1000);
    console.log(
      `Auto Sentry exceptions every ${intervalSec}s (set DEMO_AUTO_EXCEPTION_INTERVAL_SEC=0 to disable)`,
    );
  }
});
