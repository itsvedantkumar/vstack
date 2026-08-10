#!/usr/bin/env bash
# PostToolUse hook: auto-format the file Claude just edited.
# Safe by design: only acts when the project opted into a formatter,
# never blocks, never fails the tool call.
input=$(cat)
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$f" ] || [ ! -f "$f" ] && exit 0

ext="${f##*.}"
dir=$(dirname "$f")
has_cfg() { # walk up looking for a config file matching $1 glob
  d="$dir"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    for p in $d/$1; do [ -e "$p" ] && return 0; done
    d=$(dirname "$d")
  done
  return 1
}

case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|json|jsonc|css|scss|md|mdx|html|yaml|yml)
    if has_cfg ".prettierrc*" || has_cfg "prettier.config.*"; then
      npx --no-install prettier --write "$f" >/dev/null 2>&1
    elif has_cfg "biome.json*"; then
      npx --no-install @biomejs/biome format --write "$f" >/dev/null 2>&1
    fi ;;
  py)
    command -v ruff >/dev/null 2>&1 && ruff format "$f" >/dev/null 2>&1 ;;
  go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$f" >/dev/null 2>&1 ;;
  rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt "$f" >/dev/null 2>&1 ;;
esac
exit 0
