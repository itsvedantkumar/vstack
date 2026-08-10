---
name: observability
description: Monitoring, logging, and observability stack setup.
---

# Observability Stack

## Tools

| Category | Free | Paid |
|----------|------|------|
| Errors | Sentry Free | Sentry Team ($26/mo) |
| Logs | Better Stack Free | Logtail ($20/mo) |
| Metrics | Prometheus | Datadog ($15/host) |
| Traces | Jaeger | Honeycomb ($50/mo) |
| Uptime | UptimeRobot Free | Pingdom ($10/mo) |
| Real User | PostHog Free | LogRocket ($100/mo) |

## Sentry Setup

```bash
# Install
npm install @sentry/nextjs

# Configure
npx @sentry/wizard@latest -i nextjs

# Environment variables
NEXT_PUBLIC_SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
SENTRY_AUTH_TOKEN=xxx
```

## PostHog Setup

```bash
# Install
npm install posthog-js posthog-node

# Initialize (client)
import posthog from 'posthog-js'
posthog.init('phc_xxx', { api_host: 'https://app.posthog.com' })

# Initialize (server)
import { PostHog } from 'posthog-node'
const posthog = new PostHog('phc_xxx')
```

## Health Check Endpoint

```typescript
// app/api/health/route.ts
export async function GET() {
  const checks = {
    database: await checkDatabase(),
    redis: await checkRedis(),
    storage: await checkStorage(),
  }
  
  const healthy = Object.values(checks).every(Boolean)
  
  return Response.json(
    { status: healthy ? 'ok' : 'degraded', checks },
    { status: healthy ? 200 : 503 }
  )
}
```

## Alert Rules

```yaml
# Critical alerts
- name: "Error rate > 5%"
  condition: error_rate > 0.05
  notify: pagerduty

- name: "P99 latency > 2s"
  condition: p99_latency > 2000
  notify: slack

- name: "Uptime < 99%"
  condition: uptime < 0.99
  notify: email

# Warning alerts
- name: "DB connections > 80%"
  condition: db_connections > 0.8
  notify: slack

- name: "Memory > 90%"
  condition: memory_usage > 0.9
  notify: slack
```

## Dashboard Queries

```bash
# Error count (last hour)
sentry-cli issues list --query "is:unresolved" --limit 10

# Request rate
curl -s "https://api.vercel.app/v1/projects/{id}/metrics"

# Deployments
vercel list --limit 10
```

## Cost Comparison (Monthly, 100K users)

| Tool | Free Tier | Paid |
|------|-----------|------|
| Sentry | 5K errors | $26+ |
| PostHog | 1M events | $0+ |
| Vercel Analytics | 2.5M events | $10+ |
| Datadog | None | $100+ |
| **Total** | **$0** | **$136+** |
