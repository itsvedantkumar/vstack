#!/usr/bin/env bash
# setup-machine.sh — install the tools vstack and its agents expect, on a machine that has
# nothing. Idempotent: every tool is checked before it is installed, so a second run is a
# fast no-op rather than a reinstall.
#
#   ./setup-machine.sh                 core + claude
#   ./setup-machine.sh --with-deploy   also vercel and wrangler
#   ./setup-machine.sh --with-security also trivy, gitleaks, nmap, nuclei
#   ./setup-machine.sh --with-plugins  also frontend-design, typescript-lsp (below)
#   ./setup-machine.sh --check         report what is present, install nothing
#   ./setup-machine.sh --dry-run       print what would be installed
#
# What each tier is for:
#   core      git, jq, ripgrep, fd, gh, node, bun, uv   — the agent tooling and this installer
#   bundled   npm, npx, pnpm, yarn, python3              — verified, not installed: they come
#                                                          with node or the Xcode tools
#   claude    the Claude Code CLI itself
#   conductor the Conductor Mac app, several agents in parallel (macOS only)
#   deploy    vercel, wrangler                          — opt-in. Someone who wants better
#                                                          Claude behaviour does not need this
#                                                          author's deployment stack, and
#                                                          installing it by default made a
#                                                          personal toolchain look like a
#                                                          requirement of the product.
#   security  trivy, gitleaks, nmap, nuclei             — the /security command
#   plugins   frontend-design, typescript-lsp — opt-in. Neither is vstack's code; both come
#                                                          from anthropics/claude-plugins-official
#                                                          and update on their own schedule. A
#                                                          headline curl-pipe command installing
#                                                          software from outside this repo with no
#                                                          flag and no mention in the README was a
#                                                          consent problem, not a documentation
#                                                          one. VSTACK_PLUGINS=1 opts in the same
#                                                          way for the bootstrap.sh one-liner,
#                                                          which cannot take flags meant for this
#                                                          script.
#
# This script installs software. It never removes any, and it never touches your dotfiles or any
# file it does not ship.
set -uo pipefail

WITH_SECURITY=0; WITH_DEPLOY=0; WITH_PLUGINS=0; CHECK=0; DRY=0; APT_UPDATED=0
for a in "$@"; do
  case "$a" in
    --with-security) WITH_SECURITY=1 ;;
    --with-deploy)   WITH_DEPLOY=1 ;;
    --with-plugins)  WITH_PLUGINS=1 ;;
    --check)         CHECK=1 ;;
    --dry-run)       DRY=1 ;;
    -h|--help)       sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done
# VSTACK_PLUGINS=1 is the env-var form of --with-plugins, for callers that cannot pass this
# script a flag of its own — the bootstrap.sh one-liner forwards its arguments to install.sh,
# not to this script, so a flag here would never reach it from that entrypoint.
[ "${VSTACK_PLUGINS:-0}" = 1 ] && WITH_PLUGINS=1

# Absolute path first: a stripped-down PATH (cron, launchd, a bare sandbox) may not carry it,
# and guessing the platform wrong would pick the wrong package manager.
OS=$(/usr/bin/uname -s 2>/dev/null || uname -s 2>/dev/null || echo unknown)
INSTALLED=""; SKIPPED=""; FAILED=""
note(){ printf '%s\n' "$*"; }
mark(){ # mark <list-name> <tool>
  case "$1" in
    ok)   INSTALLED="$INSTALLED $2" ;;
    have) SKIPPED="$SKIPPED $2" ;;
    fail) FAILED="$FAILED $2" ;;
  esac
}

# --- package manager -------------------------------------------------------------------------
PM=""
setup_pm(){
  if [ "$OS" = "Darwin" ]; then
    # Xcode command line tools carry git and the compilers Homebrew needs. The installer is a
    # GUI prompt, so it cannot be automated. Say so and keep going.
    if ! xcode-select -p >/dev/null 2>&1; then
      note "!! Xcode command line tools are missing. Run: xcode-select --install"
      note "   Accept the dialog, wait for it to finish, then re-run this script."
    fi
    if command -v brew >/dev/null; then PM=brew; return 0; fi
    [ "$CHECK" = 1 ] && { note "-- homebrew: missing"; return 1; }
    [ "$DRY" = 1 ]   && { note "would install homebrew"; PM=brew; return 0; }
    note ">> installing homebrew (may prompt for your password)"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { note "!! homebrew install failed — install it manually from https://brew.sh"; return 1; }
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$p" ] && eval "$("$p" shellenv)"
    done
    command -v brew >/dev/null && PM=brew
  else
    for c in apt-get dnf apk; do command -v "$c" >/dev/null && { PM="$c"; break; }; done
    [ -z "$PM" ] && note "!! no supported package manager found"
  fi
  [ -n "$PM" ]
}

pm_install(){ # pm_install <package>
  case "$PM" in
    brew)    brew install "$1" ;;
    apt-get)
      if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
        return 1
      fi
      if [ "$EUID" -ne 0 ]; then
        sudo apt-get install -y -qq "$1"
      else
        apt-get install -y -qq "$1"
      fi
      ;;
    dnf)
      if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
        return 1
      fi
      if [ "$EUID" -ne 0 ]; then
        sudo dnf install -y -q "$1"
      else
        dnf install -y -q "$1"
      fi
      ;;
    apk)
      if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
        return 1
      fi
      if [ "$EUID" -ne 0 ]; then
        sudo apk add --quiet "$1"
      else
        apk add --quiet "$1"
      fi
      ;;
    *)       return 1 ;;
  esac
}

apt_update_guard(){
  [ "$PM" != "apt-get" ] && return 0
  [ "$APT_UPDATED" = 1 ] && return 0
  if [ "$DRY" = 1 ]; then
    note "would run: apt-get update"; return 0
  fi
  if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    note "!! cannot run apt-get update: not root and sudo not available"
    return 1
  fi
  if [ "$EUID" -ne 0 ]; then
    sudo apt-get update -qq >/dev/null 2>&1 || return 1
  else
    apt-get update -qq >/dev/null 2>&1 || return 1
  fi
  APT_UPDATED=1
}

# ensure <command> <package-brew> <package-apt> [label]
# on apt systems, uses package-apt; on brew, uses package-brew; others use package-brew
ensure(){
  cmd="$1"; pkg_brew="$2"; pkg_apt="${3:-$2}"; label="${4:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    note "-- $label: present ($(command -v "$cmd"))"; mark have "$label"; return 0
  fi
  [ "$CHECK" = 1 ] && { note "-- $label: MISSING"; mark fail "$label"; return 1; }

  pkg="$pkg_brew"
  [ "$PM" = "apt-get" ] && pkg="$pkg_apt"

  [ "$DRY" = 1 ] && { note "would install $label ($pkg)"; mark ok "$label"; return 0; }
  note ">> installing $label"
  if pm_install "$pkg" >/dev/null 2>&1 && command -v "$cmd" >/dev/null 2>&1; then
    mark ok "$label"
  else
    note "!! $label failed to install"; mark fail "$label"
  fi
}

# ensure_npm <command> <npm-package>
ensure_npm(){
  cmd="$1"; pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    note "-- $cmd: present"; mark have "$cmd"; return 0
  fi
  [ "$CHECK" = 1 ] && { note "-- $cmd: MISSING"; mark fail "$cmd"; return 1; }
  [ "$DRY"   = 1 ] && { note "would install $cmd (npm -g $pkg)"; mark ok "$cmd"; return 0; }
  command -v npm >/dev/null || { note "!! $cmd needs npm, which is missing"; mark fail "$cmd"; return 1; }
  note ">> installing $cmd"
  if npm install -g "$pkg" >/dev/null 2>&1 && command -v "$cmd" >/dev/null 2>&1; then
    mark ok "$cmd"
  else
    note "!! $cmd failed to install"; mark fail "$cmd"
  fi
}

# ensure_remote <command> <installer-url> [label]
# For tools like bun and uv that provide curl installers outside package managers
ensure_remote(){
  cmd="$1"; url="$2"; label="${3:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    note "-- $label: present ($(command -v "$cmd"))"; mark have "$label"; return 0
  fi
  [ "$CHECK" = 1 ] && { note "-- $label: MISSING"; mark fail "$label"; return 1; }
  [ "$DRY"   = 1 ] && { note "would install $label (via curl)"; mark ok "$label"; return 0; }
  note ">> installing $label"
  if curl -fsSL "$url" | bash >/dev/null 2>&1 && command -v "$cmd" >/dev/null 2>&1; then
    mark ok "$label"
  else
    note "!! $label failed to install"; mark fail "$label"
  fi
}

# --- run -----------------------------------------------------------------------------------
note "== platform: $OS"
setup_pm || note "!! continuing without a package manager; most installs will fail"
[ -n "$PM" ] && note "== package manager: $PM"

note ""
note "== core"
apt_update_guard

ensure git      git         git
ensure jq       jq          jq
ensure rg       ripgrep     ripgrep  rg
ensure fd       fd          fd-find  fd
ensure gh       gh          gh
ensure node     node        nodejs   node
ensure_remote bun "https://bun.sh/install.sh"
ensure_remote uv  "https://astral.sh/uv/install.sh"

note ""
note "== bundled with node"
# npm, npx and corepack arrive with node. Installing them separately fights the node install,
# so this section verifies rather than installs. It exists because ensure_npm below needs npm,
# and "vercel needs npm, which is missing" is a confusing way to learn that node is broken.
for c in npm npx; do
  if command -v "$c" >/dev/null 2>&1; then
    note "-- $c: present ($(command -v "$c"))"; mark have "$c"
  else
    note "!! $c: missing, which means the node install is incomplete"; mark fail "$c"
  fi
done

# corepack turns on pnpm and yarn without downloading either. Plenty of repos assume one of
# them and fail their install step without it.
if ! command -v corepack >/dev/null 2>&1; then
  note "-- corepack: not available, skipping pnpm and yarn"
elif [ "$CHECK" = 1 ]; then
  command -v pnpm >/dev/null 2>&1 && note "-- pnpm: present" || note "-- pnpm: MISSING (corepack enable pnpm)"
elif [ "$DRY" = 1 ]; then
  note "would enable pnpm and yarn through corepack"
else
  if corepack enable pnpm yarn >/dev/null 2>&1; then
    note ">> enabled pnpm and yarn (corepack)"; mark ok "pnpm/yarn"
  else
    note "!! corepack enable failed; run it yourself if a repo needs pnpm or yarn"
  fi
fi

# python3 ships with the Xcode command line tools on macOS, and uv manages versions and venvs
# from there. Checked, not installed.
if command -v python3 >/dev/null 2>&1; then
  note "-- python3: present ($(command -v python3))"; mark have python3
else
  note "!! python3: missing, install the Xcode command line tools"; mark fail python3
fi

note ""
note "== claude code"
if command -v claude >/dev/null 2>&1; then
  note "-- claude: present ($(command -v claude))"; mark have claude
elif [ "$CHECK" = 1 ]; then
  note "-- claude: MISSING"; mark fail claude
elif [ "$DRY" = 1 ]; then
  note "would install claude code"; mark ok claude
else
  note ">> installing claude code"
  if curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1; then
    export PATH="$HOME/.local/bin:$PATH"
    command -v claude >/dev/null && mark ok claude || { note "!! installed but not on PATH — add \$HOME/.local/bin"; mark fail claude; }
  else
    note "!! claude install failed — see https://claude.ai/install"; mark fail claude
  fi
fi

note ""
note "== conductor"
# Conductor runs several Claude Code agents in parallel, each in its own git worktree. It is a
# Mac app, so a cask install is the only sane route and Linux skips it. Detection looks for the
# app bundle rather than asking brew: it is commonly installed by download, and brew would
# then report it missing and try to install it again.
if [ "$OS" != "Darwin" ]; then
  note "-- conductor: skipped (macOS only)"
elif [ -d "/Applications/Conductor.app" ]; then
  note "-- conductor: present (/Applications/Conductor.app)"; mark have conductor
elif [ "$CHECK" = 1 ]; then
  note "-- conductor: MISSING"; mark fail conductor
elif [ "$DRY" = 1 ]; then
  note "would install conductor (brew cask)"; mark ok conductor
elif [ "$PM" = brew ]; then
  note ">> installing conductor"
  if brew install --cask conductor >/dev/null 2>&1 && [ -d "/Applications/Conductor.app" ]; then
    mark ok conductor
  else
    note "!! conductor failed to install; download it from https://conductor.build"; mark fail conductor
  fi
else
  note "!! conductor needs homebrew; download it from https://conductor.build"; mark fail conductor
fi

note ""
note "== claude plugins"
# Plugins carry the language tooling. Neither is claimed by name in settings.json's
# enabledPlugins any more -- a name there means nothing until the marketplace is added and the
# plugin actually installed, and typescript-lsp reproduced that defect the moment this script
# stopped installing it by default. install.sh's settings merge strips an enabledPlugins entry
# that is not actually present on disk (see the del(.enabledPlugins[...]) calls there), so a
# claim only survives a reinstall when the plugin really is installed. Installing them here by
# default without the same restraint would put this script back in the business install.sh
# already opted out of, from a headline curl-pipe command that never asked. --with-plugins (or
# VSTACK_PLUGINS=1) is the opt-in; the default path names what it is skipping.
#
# claude-mem was the third entry here until 1.46.0 and is gone. It was measured injecting
# nothing: its only UserPromptSubmit hook returns {} and the context builder it ships is
# reachable from no hook at all. See CHANGELOG.md 1.46.0.
if ! command -v claude >/dev/null 2>&1; then
  note "-- plugins: skipped (claude not installed)"
elif [ "$WITH_PLUGINS" != 1 ]; then
  present=""
  for pl in frontend-design typescript-lsp; do
    claude plugin list 2>/dev/null | grep -qi "$pl" && present="$present $pl"
  done
  [ -n "$present" ] && note "-- plugins: already present:$present"
  note "-- plugins: skipped frontend-design, typescript-lsp (opt in with --with-plugins or VSTACK_PLUGINS=1)"
elif [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then
  note "${DRY:+would install }plugins: frontend-design, typescript-lsp"
else
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 || true
  for pl in frontend-design@claude-plugins-official typescript-lsp@claude-plugins-official; do
    if claude plugin list 2>/dev/null | grep -q "${pl%@*}"; then
      note "-- ${pl%@*}: present"; mark have "${pl%@*}"
    elif claude plugin install "$pl" >/dev/null 2>&1; then
      note ">> installed ${pl%@*}"; mark ok "${pl%@*}"
    else
      note "!! ${pl%@*} failed (add it later with: claude plugin install $pl)"; mark fail "${pl%@*}"
    fi
  done
fi

note ""
if [ "$WITH_DEPLOY" = 1 ]; then
note "== deploy"
ensure_npm vercel   vercel
ensure_npm wrangler wrangler
else
note "== deploy (skipped — pass --with-deploy for vercel and wrangler)"
fi

if [ "$WITH_SECURITY" = 1 ]; then
  note ""
  note "== security"
  ensure trivy    trivy
  ensure gitleaks gitleaks
  ensure nmap     nmap
  ensure nuclei   nuclei
  note "   OWASP ZAP is not installed here: it is a large Java app. Get it from zaproxy.org."
fi

# --- report ----------------------------------------------------------------------------------
note ""
note "== summary"
[ -n "$SKIPPED" ]   && note "already present:$SKIPPED"
[ -n "$INSTALLED" ] && note "installed:$INSTALLED"
[ -n "$FAILED" ]    && note "missing:$FAILED"

# Only the tools vstack cannot work without decide the exit code. A missing nuclei is not a
# broken machine; a missing jq or git is.
#
# `claude` belongs on that list and was not on it, which made this report success for a machine
# that cannot run the product at all. bootstrap.sh treats a zero exit as "tools are fine" and
# carries on to modify config and shell startup files, so a stranger could be told everything
# worked and then find there is no agent to run. The README promises a working setup including
# the CLI; this is the check that has to mean it.
REQUIRED="git jq claude"
missing=""
for r in $REQUIRED; do command -v "$r" >/dev/null 2>&1 || missing="$missing $r"; done
if [ -n "$missing" ] && [ "$DRY" = 0 ]; then
  note ""
  note "REQUIRED TOOLS MISSING:$missing"
  case "$missing" in
    *claude*) note "  the Claude Code CLI is the product this configures; without it the install"
              note "  would leave you config for an agent you cannot run."
              note "  install: npm install -g @anthropic-ai/claude-code" ;;
  esac
  exit 1
fi

note ""
if [ "$CHECK" = 1 ]; then
  note "check complete."
elif [ "${VSTACK_CHAINED:-0}" = 1 ]; then
  # Set by bootstrap.sh, which runs this script and then execs install.sh itself in the same
  # invocation. "Next: ./install.sh" was stale there -- it reads as a manual step still to do,
  # for a step that is about to happen automatically one line later.
  note "done. continuing to install.sh..."
else
  note "done. Next: ./install.sh"
fi
exit 0
