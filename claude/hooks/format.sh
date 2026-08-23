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

# node_modules/.bin/<name>, walking up the same way has_cfg does. Mirrors the `command -v`
# gate already used below for ruff/gofmt/rustfmt: run the formatter only when it is actually
# installed, never fetch it. Before this, `npx --no-install prettier` still paid full node
# module resolution to fail on a repo that has a prettier config but no `npm install` yet --
# exactly the state of a freshly cloned repo -- costing 557-919ms on every single Edit/Write.
find_bin() {
  d="$dir"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    b="$d/node_modules/.bin/$1"
    [ -x "$b" ] && { printf '%s\n' "$b"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}

# Prettier's own config loader (cosmiconfig) treats .prettierrc.js/.cjs/.mjs/.ts and
# prettier.config.js/.cjs/.mjs/.ts as ordinary JavaScript and require()s them the moment it
# resolves config -- which is the moment prettier runs, with no confirmation, because this hook
# fires on every Edit/Write and hooks sit outside the permission system. A hostile repo shipping
# one of those with code at module load gets it executed unattended the instant the agent edits
# any file this hook covers.
#
# Fixed by replicating prettier's own config search (closest directory wins, same priority
# order prettier's cosmiconfig searchPlaces uses for the "prettier" module) far enough to
# classify what it would load, and refusing outright when that is a JS/TS file -- prettier is
# never invoked at all in that case, rather than trusting it to somehow not execute code it was
# built to execute. When the winning config is a static format we still pass it to prettier via
# --config explicitly, so a bug in this approximation can only be too cautious, never silently
# permissive: prettier is never handed a bare directory to search on its own account, so it can
# never resolve to a JS file this function did not already see and approve.
#
# Residual risk, left open rather than silently patched: a static (JSON/YAML) config's own
# "plugins" array can still name a local .js file, and prettier will load and execute it
# regardless of how the config itself was found. That requires the static config to explicitly
# declare a plugin path, which is a far more visible supply-chain signal than an arbitrary file
# executing on mere discovery, and prettier 3 has no flag to refuse plugin loading outright.
# Biome's config format (biome.json) has no executable variant, so the biome branch below carries
# no equivalent risk and needed no change beyond the same node_modules/.bin perf fix.
find_prettier_cfg() {
  d="$dir"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    for name in package.json .prettierrc .prettierrc.json .prettierrc.yaml .prettierrc.yml \
                .prettierrc.json5 .prettierrc.js .prettierrc.cjs .prettierrc.mjs .prettierrc.ts \
                prettier.config.js prettier.config.cjs prettier.config.mjs prettier.config.ts \
                .prettierrc.toml; do
      p="$d/$name"
      [ -e "$p" ] || continue
      if [ "$name" = package.json ]; then
        grep -q '"prettier"[[:space:]]*:' "$p" 2>/dev/null || continue
      fi
      printf '%s\n' "$p"
      return 0
    done
    d=$(dirname "$d")
  done
  return 1
}

case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|json|jsonc|css|scss|md|mdx|html|yaml|yml)
    if cfg=$(find_prettier_cfg); then
      case "$cfg" in
        *.js|*.cjs|*.mjs|*.ts) : ;; # executable-format config: never handed to prettier
        *)
          pb=$(find_bin prettier) && "$pb" --config "$cfg" --write "$f" >/dev/null 2>&1 ;;
      esac
    elif has_cfg "biome.json*"; then
      bb=$(find_bin biome) && "$bb" format --write "$f" >/dev/null 2>&1
    fi ;;
  py)
    command -v ruff >/dev/null 2>&1 && ruff format "$f" >/dev/null 2>&1 ;;
  go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$f" >/dev/null 2>&1 ;;
  rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt "$f" >/dev/null 2>&1 ;;
esac
exit 0
