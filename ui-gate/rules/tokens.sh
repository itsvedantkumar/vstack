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

# TOK-TYPE-SCALE: font sizes off the scale, and anything under 12px, which is not readable body text.
if ! _ui_have; then
  skip TOK-TYPE-SCALE "no component or stylesheet files under $TARGET"
else
  bad=""
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    px=$(printf '%s' "$hit" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    case "$px" in 12|14|16|20|24|32|48) ;; *) bad="$bad $hit" ;; esac
  done <<EOF
$(_ui_files | xargs grep -hEo 'font-size:[[:space:]]*[0-9]+(\.[0-9]+)?px' 2>/dev/null | head -20)
EOF
  [ -z "$bad" ] && pass TOK-TYPE-SCALE "font sizes are on the 12/14/16/20/24/32/48 scale" \
    || fail TOK-TYPE-SCALE "off-scale font sizes:$(printf '%s' "$bad" | head -c 120)"
fi
