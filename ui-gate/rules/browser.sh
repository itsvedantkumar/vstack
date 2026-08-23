# shellcheck shell=bash
# Sourced by ui-gate/ui-gate.sh; not executed directly.
#
# The families that need a running browser. Until 1.22.0 all six were unconditional `skip` calls
# carrying the reason "playwright is not vendored here". That reason was false: nothing here ever
# checked for a browser, and vstack ships the agent-browser skill, which is a headless browser
# built for exactly this and already on PATH. Six rules were dead for a stated cause that had
# stopped being true, which is the same defect as a check whose anchor moved -- the difference
# being that this one announced itself in every run and nobody read it.
#
# Two are implemented now. The other four still skip, with the real reason rather than the old
# one, because each needs something this repository does not have yet and saying so is cheaper
# than a rule that pretends.
#
# Browser rules need a URL, not a directory. UI_GATE_URL supplies it; without one there is
# nothing to open and the skip is honest.

_ui_ab() { npx --no-install agent-browser "$@" 2>/dev/null; }

if ! command -v npx >/dev/null 2>&1 || ! npx --no-install agent-browser --version >/dev/null 2>&1; then
  _ui_no_browser="agent-browser is not installed (npm i -g agent-browser), so nothing can be opened"
elif [ -z "${UI_GATE_URL:-}" ]; then
  _ui_no_browser="no UI_GATE_URL set; browser rules need a running dev server, not a directory"
else
  _ui_no_browser=""
fi

# --- COV-VIEWPORT: horizontal overflow at 375px -----------------------------------------------
# The cheapest real failure in this family and the one that catches the most shipped bugs: a page
# that scrolls sideways on a phone. Deterministic, no network beyond the target, no baseline to
# maintain. scrollWidth exceeding clientWidth by more than a rounding pixel is overflow.
if [ -n "$_ui_no_browser" ]; then
  skip COV-VIEWPORT "$_ui_no_browser (mutation: force horizontal overflow at 375px)"
else
  _ui_ab set viewport 375 812 >/dev/null
  _ui_ab open "$UI_GATE_URL" >/dev/null
  _ov=$(_ui_ab eval 'document.documentElement.scrollWidth - document.documentElement.clientWidth' | tr -dc '0-9-')
  if [ -z "$_ov" ]; then
    skip COV-VIEWPORT "the page did not answer; $UI_GATE_URL may not be serving"
  elif [ "$_ov" -gt 1 ]; then
    fail COV-VIEWPORT "horizontal overflow at 375px: content is ${_ov}px wider than the viewport"
  else
    pass COV-VIEWPORT "no horizontal overflow at 375px"
  fi
fi

# --- A11Y-KEYBOARD: focus is visible ----------------------------------------------------------
# Tab to the first focusable element and require that it be visibly marked. A focus ring removed
# for looks is the single most common accessibility regression in a polished interface, and it is
# invisible to anyone testing with a mouse. Checked as computed style rather than by reading CSS,
# because outline:none in one rule and a box-shadow in another is a pass.
if [ -n "$_ui_no_browser" ]; then
  skip A11Y-KEYBOARD "$_ui_no_browser (mutation: remove a focus outline)"
else
  _ui_ab open "$UI_GATE_URL" >/dev/null
  _ui_ab press Tab >/dev/null
  _fx=$(_ui_ab eval '(() => {
      const e = document.activeElement;
      if (!e || e === document.body) return "NOFOCUS";
      const s = getComputedStyle(e);
      const ring = (s.outlineStyle !== "none" && parseFloat(s.outlineWidth) > 0)
                || (s.boxShadow && s.boxShadow !== "none")
                || (parseFloat(s.borderWidth) > 0 && s.borderStyle !== "none");
      return ring ? "RING" : "BARE:" + e.tagName.toLowerCase();
    })()' | tr -d '"' | tr -d ' ')
  case "$_fx" in
    *RING*)    pass A11Y-KEYBOARD "the first tab stop is visibly focused" ;;
    *NOFOCUS*) fail A11Y-KEYBOARD "Tab moved focus nowhere: no reachable focusable element" ;;
    *BARE*)    fail A11Y-KEYBOARD "the first tab stop has no visible focus indicator (${_fx#*BARE:})" ;;
    *)         skip A11Y-KEYBOARD "the page did not answer; $UI_GATE_URL may not be serving" ;;
  esac
fi

# --- A11Y-AXE: axe-core, offline ---------------------------------------------------------------
# Written off in the first draft of this file as "axe-core is not vendored", which was wrong for
# the same reason the playwright line was wrong: nobody checked. agent-browser ships axe-core
# 4.12.1 and runs it as a private partial audit across the frame tree with no network request. The
# skip reason was false within minutes of being written, which is the argument for capability
# probes over remembered facts.
#
# Scoped to WCAG A and AA. Only critical and serious violations fail; moderate and minor are
# reported by axe but are judgement calls, and a gate that fails on them gets switched off.
if [ -n "$_ui_no_browser" ]; then
  skip A11Y-AXE "$_ui_no_browser (mutation: remove an accessible name)"
else
  _ax=$(_ui_ab a11y "$UI_GATE_URL" --tags wcag2a,wcag2aa)
  if [ -z "$_ax" ]; then
    skip A11Y-AXE "the audit returned nothing; $UI_GATE_URL may not be serving"
  else
    _sev=$(printf '%s' "$_ax" | grep -cE '^\[(critical|serious)\]')
    if [ "$_sev" -gt 0 ]; then
      fail A11Y-AXE "$_sev critical or serious violation(s): $(printf '%s' "$_ax" | grep -oE '^\[(critical|serious)\] [a-z-]+' | head -3 | tr '\n' ' ')"
    else
      pass A11Y-AXE "no critical or serious WCAG A/AA violations ($(printf '%s' "$_ax" | grep -oE 'axe-core: [0-9.]+' | head -1))"
    fi
  fi
fi

# --- Still declared, still skipped, with the reason that is actually true ----------------------
# Each names what it needs. A rule that skips for a stated cause somebody can act on is worth
# keeping declared; a rule that skips for a cause that expired is the thing this file just fixed.
skip COV-STATES  "no state fixture convention exists yet: nothing declares what the error and empty states of a component are (mutation: delete an error-state fixture)"
skip VIS-SNAPSHOT "no baseline image store exists yet, so there is nothing to diff against (mutation: shift a component one pixel)"
skip PERF-LAB    "no lab budget is declared for any target (mutation: inject an 80ms busy loop)"
