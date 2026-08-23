---
name: observability
description: Check observability setup and help integrate error tracking or analytics.
---

Check what observability (error tracking, analytics, monitoring) is currently set up in this project. **$ARGUMENTS**

Observability tooling — Sentry, PostHog, Datadog, Prometheus, etc. — is not shipped with vstack. This command helps you choose and set up one. You install and configure the tool; the command validates the setup.

1. **Check what's installed.** Look for evidence of existing observability tools:
   ```bash
   grep -r "sentry\|posthog\|datadog\|honeycomb\|elastic" package.json 2>/dev/null | head -5
   grep -r "@sentry/\|posthog\|datadog" src/ app/ 2>/dev/null | head -5
   env | grep -i "sentry\|posthog\|datadog"
   ```
   Report what is already configured, if anything.

2. **If already configured:** Run a health check. For Sentry: `sentry-cli issues list --query "is:unresolved" --limit 3`. For PostHog: confirm the DSN/key environment variable is set. Report the status.

3. **If not configured and user wants to add observability:**
   a. Present the tool matrix (Errors: Sentry/Datadog, Logs: Logtail/Better Stack, Analytics: PostHog/LogRocket, Monitoring: Prometheus/Datadog, Uptime: UptimeRobot/Pingdom).
   b. For the chosen tool, provide install and configure steps in the tool's own documentation (e.g. `npm install @sentry/nextjs && npx @sentry/wizard@latest -i nextjs` for Sentry in Next.js). You provide the reference only; the user runs the commands.
   c. After the user installs, verify the setup: check for the tool's environment variables and imports in the code, then confirm a test event is received.

4. **No required integration.** Observability is optional and does not block builds or deploys. This command only helps users who want to add it.
