# claude-parity.zsh — make bare-metal `claude` launch the way Conductor launches it.
#
# Conductor runs:  --model claude-opus-5[1m] --effort high --settings '{"fastMode":true}'
#                  --permission-mode bypassPermissions --chrome --plugin-dir <conductor-skill>
#                  and deletes ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN from the child env.
# Everything with a settings.json key now lives in ~/.claude/settings.json (so it also
# reaches Remote Control sessions). This file covers only the flags that have NO settings
# key, plus env hygiene.
#
# Escape hatches:  command claude ... | claude-raw ... | NO_CLAUDE_WRAPPER=1 claude ...

_claude_conductor_plugin_dir() {
  if [[ -n "$CONDUCTOR_INTERNAL_SKILL_PLUGIN_DIR" \
     && -f "$CONDUCTOR_INTERNAL_SKILL_PLUGIN_DIR/.claude-plugin/plugin.json" ]]; then
    print -r -- "$CONDUCTOR_INTERNAL_SKILL_PLUGIN_DIR"; return 0
  fi
  local d="/Applications/Conductor.app/Contents/Resources/conductor-skill"
  [[ -f "$d/.claude-plugin/plugin.json" ]] && { print -r -- "$d"; return 0 }
  return 1
}

claude() {
  local bin; bin="$(whence -p claude)"
  [[ -n "$bin" ]] || { print -u2 "claude: binary not on PATH"; return 127 }

  # Inside Conductor, or explicitly opted out -> exact passthrough.
  if [[ -n "$CONDUCTOR_WORKSPACE_PATH" || -n "$NO_CLAUDE_WRAPPER" ]]; then
    "$bin" "$@"; return
  fi

  # Decorate only real interactive TUI launches.
  local decorate=1 a
  [[ -t 0 && -t 1 ]] || decorate=0
  case "$1" in
    agents|auth|auto-mode|doctor|gateway|import|install|mcp|plugin|plugins|project|\
setup-token|ultrareview|update|upgrade|help) decorate=0 ;;
  esac
  # Remote/background/print sessions must launch undecorated: --chrome needs the local
  # browser and --plugin-dir needs the local app bundle; neither exists remotely.
  for a in "$@"; do
    case "$a" in
      -p|--print|--bare|--safe-mode|--no-chrome|-v|--version|-h|--help|\
--remote-control|--teleport|--cloud|--bg|--background|--brief) decorate=0; break ;;
    esac
  done

  local -a extra
  if (( decorate )); then
    extra+=(--chrome)
    # Moves cwd/env/git-status out of the system prompt -> better prompt-cache reuse.
    extra+=(--exclude-dynamic-system-prompt-sections)
    local pd; pd="$(_claude_conductor_plugin_dir)" && extra+=(--plugin-dir "$pd")
  fi

  # Conductor strips these so auth is always the Max subscription, never API credits.
  # Scoped to this process; never unsets them in your shell.
  env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN "$bin" "${extra[@]}" "$@"
}

claude-plan() { claude --permission-mode plan "$@" }   # Conductor's default_plan_mode
claude-wt()   { claude --worktree "$@" }               # Conductor's worktree isolation
claude-raw()  { NO_CLAUDE_WRAPPER=1 command claude "$@" }
