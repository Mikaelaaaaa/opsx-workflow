# Context

## Glossary

**Upstream** — the partner inventory API that `getJson` calls. It rate-limits at 20 requests per second and returns 503 while it redeploys, usually for under a minute.

**Sync job** — the nightly job that pulls the full inventory through `getJson`. It has a 60-second budget per page before the scheduler kills it.
