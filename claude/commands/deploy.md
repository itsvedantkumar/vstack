---
name: deploy
description: One-command deploy to Vercel/Cloudflare/Railway with automatic checks.
---

# Deploy Command

## Pre-deploy Checks

1. Typecheck
2. Lint
3. Tests
4. Build

## Commands

```bash
# Vercel (auto-detects)
/deploy vercel

# Cloudflare Workers
/deploy cf

# Railway
/deploy railway

# Fly.io
/deploy fly
```

## Implementation

```bash
#!/bin/bash
# ~/.local/bin/deploy
set -e

PLATFORM=$1
shift

echo "Running pre-deploy checks..."

# Typecheck
npm run typecheck 2>&1 | tail -5 || { echo "Typecheck failed"; exit 1; }

# Lint
npm run lint 2>&1 | tail -5 || { echo "Lint failed"; exit 1; }

# Tests
npm test -- --passWithNoTests 2>&1 | tail -5 || { echo "Tests failed"; exit 1; }

# Build
npm run build 2>&1 | tail -10 || { echo "Build failed"; exit 1; }

echo "Checks passed. Deploying to $PLATFORM..."

case $PLATFORM in
  vercel)
    vercel --prod "$@"
    ;;
  cf|cloudflare)
    npx wrangler deploy "$@"
    ;;
  railway)
    railway up "$@"
    ;;
  fly)
    fly deploy "$@"
    ;;
  *)
    echo "Unknown platform: $PLATFORM"
    exit 1
    ;;
esac
```

## Quick Deploy

```bash
# Production
npm run deploy

# Preview
npm run deploy:preview
```

## package.json

```json
{
  "scripts": {
    "deploy": "deploy vercel",
    "deploy:preview": "vercel",
    "deploy:cf": "deploy cf"
  }
}
```
