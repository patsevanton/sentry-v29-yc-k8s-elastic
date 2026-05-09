import * as Sentry from "@sentry/node";

const dsn = process.env.SENTRY_DSN;

Sentry.init({
  dsn: dsn || undefined,
  tracesSampleRate: 1.0,
});

if (!dsn) {
  console.warn("SENTRY_DSN is not set; /demo/* will return 503");
}
