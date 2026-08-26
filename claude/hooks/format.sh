#!/usr/bin/env bash
# PostToolUse hook: auto-format the file Claude just edited.
# Safe by design: only acts when the project opted into a formatter,
# never blocks, never fails the tool call.
input=$(cat)
# jq is preferred, but its absence used to make this whole hook a silent no-op: `jq -r ...`
# under `command not found` produces empty output, $f stayed empty, and the early exit below
# fired on every single edit -- formatting simply never happened, with nothing said about why.
# The fallback below only needs to extract one flat string field from JSON Claude Code itself
# generated (no attacker-controlled nesting to worry about), so a bounded grep+sed pair is
# sufficient without pulling in a JSON parser.
if command -v jq >/dev/null 2>&1; then
  f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
else
  f=$(printf '%s' "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
        | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
  [ -z "$f" ] && f=$(printf '%s' "$input" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
        | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
fi
[ -z "$f" ] || [ ! -f "$f" ] && exit 0

# systemMessage note, shown to the operator without failing the tool call. Same JSON-if-jq,
# manual-escape-if-not shape verify-gate.sh already uses for the same purpose, so there is one
# convention for "this hook silently skipped something and here is why" across the repo.
note() {
  m="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "$m" '{systemMessage:$m}'
  else
    e=$(printf '%s' "$m" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '{"systemMessage":"%s"}\n' "$e"
  fi
}

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
# A static (JSON/YAML/TOML) config's own "plugins" entry can still name a local .js file, and
# prettier loads and require()s it regardless of how the config itself was found -- installed
# prettier is 3.9.6 here and prettier 3 has no --no-plugin-search or equivalent flag to refuse
# plugin loading outright, so the only honest options are "never invoke prettier when a plugin
# is declared" (closes the hole but breaks every repo that legitimately uses a prettier plugin)
# or "invoke it only where a human already drew a trust boundary". This hook has no boundary of
# its own to draw, so it reads the one `vstack trust` already writes: it treats the project as
# trusted for this purpose exactly when $CLAUDE_PROJECT_DIR/.claude/verify.sh's hash is recorded
# in ~/.config/agents/verify-trust, the same literal check verify-gate.sh makes before running
# that script unattended. Repurposing that record is a deliberate, documented coupling, not a
# discovery: it means a repository with no .claude/verify.sh, or one nobody has run `vstack
# trust` in, can never get a prettier plugin loaded through this hook, even if the operator
# trusts it for other reasons -- there is no separate "I trust this repo's prettier plugins"
# switch to check, and inventing one is out of scope for a formatter hook. Biome's config format
# (biome.json) has no executable variant, so the biome branch below carries no equivalent risk
# and needed no change beyond the same node_modules/.bin perf fix.
cfg_has_plugins() { # $1: winning static config path
  grep -Eq '"plugins"[[:space:]]*:|^[[:space:]]*plugins[[:space:]]*[:=]' "$1" 2>/dev/null
}

is_project_trusted() {
  proj="${CLAUDE_PROJECT_DIR:-$PWD}"
  v=$(cd "$proj/.claude" 2>/dev/null && pwd)/verify.sh
  [ -f "$v" ] || return 1
  ts="$HOME/.config/agents/verify-trust"
  [ -f "$ts" ] || return 1
  if command -v shasum >/dev/null 2>&1; then h=$(shasum -a 256 "$v" | cut -d' ' -f1)
  else h=$(sha256sum "$v" 2>/dev/null | cut -d' ' -f1); fi
  [ -n "$h" ] && grep -qxF "$h  $v" "$ts" 2>/dev/null
}
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
          if cfg_has_plugins "$cfg" && ! is_project_trusted; then
            note "format.sh: skipped prettier -- $cfg declares a \"plugins\" entry, which prettier loads and executes as code, and this project has not been trusted (run 'vstack trust' to allow it)."
          else
            pb=$(find_bin prettier) && "$pb" --config "$cfg" --write "$f" >/dev/null 2>&1
          fi ;;
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
