---
name: release
description: Semantic versioning + changelog automation. One command to release.
---

# Release Command

## Semantic Versioning

```bash
# Patch (bug fixes)
/release patch

# Minor (features)
/release minor

# Major (breaking)
/release major

# Auto-detect from commits
/release
```

## Prerequisites

```bash
npm install -D standard-version commitizen @commitlint/cli @commitlint/config-conventional
```

## Commit Convention

```
feat: add user authentication     # Minor bump
fix: resolve login redirect       # Patch bump
feat!: new API structure          # Major bump
docs: update README
chore: bump dependencies
refactor: simplify auth logic
test: add unit tests
```

## Implementation

```bash
#!/bin/bash
# ~/.local/bin/release
set -e

TYPE=$1

case $TYPE in
  patch|minor|major)
    npx standard-version --release-as $TYPE
    ;;
  *)
    npx standard-version
    ;;
esac

echo "Release created. Push with:"
echo "  git push --follow-tags origin main"
```

## package.json

```json
{
  "scripts": {
    "release": "standard-version",
    "release:minor": "standard-version --release-as minor",
    "release:major": "standard-version --release-as major"
  }
}
```

## Auto-changelog

Generated automatically from conventional commits:

```markdown
# Changelog

## [1.2.0] - 2024-01-15
### Features
- Add user authentication
- Implement rate limiting

### Bug Fixes
- Resolve login redirect issue

## [1.1.0] - 2024-01-10
...
```
