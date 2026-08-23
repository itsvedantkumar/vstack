# shellcheck shell=bash
# Sourced by ui-gate/ui-gate.sh; not executed directly.
# Token conformance. No browser needed, so this family is enforced rather than declared.
#
# Scoped to files the target actually ships. A raw colour in a token definition file is the token;
# a raw colour in a component is the drift.
_ui_files() {
  find "$TARGET" \( -name node_modules -o -name .git -o -name dist -o -name build -o -name ui-gate \) -prune -o \
       -type f \( -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' -o -name '*.css' \) -print 2>/dev/null \
    | grep -viE '(tokens|theme|globals|variables|tailwind\.config)\.' || true
}

_ui_have() { [ -n "$(_ui_files | head -1)" ]; }

# TOK-RAW-COLOR: a literal colour outside the files that define colour.
if ! _ui_have; then
  skip TOK-RAW-COLOR "no component or stylesheet files under $TARGET"
else
  hits=$(_ui_files | xargs grep -nEo '#[0-9a-fA-F]{3,8}\b|rgba?\([0-9]|hsla?\([0-9]' 2>/dev/null | head -20)
  [ -z "$hits" ] && pass TOK-RAW-COLOR "no raw colour outside token sources" \
    || fail TOK-RAW-COLOR "raw colour literals: $(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
fi

# TOK-ARBITRARY: Tailwind arbitrary values, which are a design decision inlined past the system.
if ! _ui_have; then
  skip TOK-ARBITRARY "no component or stylesheet files under $TARGET"
else
  hits=$(_ui_files | xargs grep -nEo '\b(m|p)[trblxy]?-\[[^]]+\]|\b(w|h|gap|top|left|right|bottom)-\[[^]]+\]|text-\[[0-9]' 2>/dev/null | head -20)
  [ -z "$hits" ] && pass TOK-ARBITRARY "no arbitrary spacing or size values" \
    || fail TOK-ARBITRARY "arbitrary values: $(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
fi

# TOK-TYPE-SCALE: font sizes off the project's scale.
#
# The scale used to be the literal list 12|14|16|20|24|32|48, typed into this file. Nobody derived
# it, no project agreed to it, and a project whose display face steps 1.333 from 18px hits it on
# every heading. A gate that fails correct work trains people to switch the gate off, which is
# worse than not having one.
#
# It reads .impeccable/brand.json now when the target ships one, so the scale a project measured
# is the scale enforced. The old list survives as the fallback for projects that declare nothing,
# stated as a default rather than presented as a standard.
_ui_scale() {
  local bj="$TARGET/.impeccable/brand.json"
  if [ -f "$bj" ] && command -v jq >/dev/null 2>&1; then
    local declared
    declared=$(jq -r '(.type.scale // [])[]' "$bj" 2>/dev/null | tr '\n' ' ')
    if [ -n "${declared// /}" ]; then printf '%s' "$declared"; return 0; fi
  fi
  printf '12 14 16 20 24 32 48'
}

if ! _ui_have; then
  skip TOK-TYPE-SCALE "no component or stylesheet files under $TARGET"
else
  _scale=$(_ui_scale)
  _src=$([ -f "$TARGET/.impeccable/brand.json" ] && echo "declared in .impeccable/brand.json" || echo "default scale, no .impeccable/brand.json in this target")
  bad=""
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    px=$(printf '%s' "$hit" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    case " $_scale " in *" $px "*) ;; *) bad="$bad $hit" ;; esac
  done <<EOF
$(_ui_files | xargs grep -hEo 'font-size:[[:space:]]*[0-9]+(\.[0-9]+)?px' 2>/dev/null | head -20)
EOF
  [ -z "$bad" ] && pass TOK-TYPE-SCALE "font sizes are on the scale [$_scale] ($_src)" \
    || fail TOK-TYPE-SCALE "off the scale [$_scale] ($_src):$(printf '%s' "$bad" | head -c 110)"
fi
