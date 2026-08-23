#!/usr/bin/env bash
set -uo pipefail

TMPDIR="/tmp/vstack-mandate-breadth-$$"
mkdir -p "$TMPDIR"
export TMPDIR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/claude/hooks/skill-mandate.sh"

# Test 1: 5 writes to one directory, same extension (fixtures), 0 Task → NOT block
cat > "$TMPDIR/tr1.jsonl" << 'EOF'
{"type":"user","message":{"role":"user","content":"generate test fixtures"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"fixtures/case1.json","content":"{}"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"fixtures/case2.json","content":"{}"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"fixtures/case3.json","content":"{}"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"fixtures/case4.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Write","input":{"file_path":"fixtures/case5.json","content":"{}"}}]}}
{"type":"user","message":{"role":"user","content":"done"}}
EOF

# Test 2: 4 files across 4 directories with 3 extensions, 0 Task → BLOCK
# hook.sh (.), test/hook.test.sh (test), doc/HOOK.md (doc), manifest.json (.)
cat > "$TMPDIR/tr2.jsonl" << 'EOF'
{"type":"user","message":{"role":"user","content":"add hook and tests"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}}]}}
{"type":"user","message":{"role":"user","content":"done"}}
EOF

# Test 3: Same as test 2 but with 1 Task call → NOT block
cat > "$TMPDIR/tr3.jsonl" << 'EOF'
{"type":"user","message":{"role":"user","content":"add hook and tests"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Task","input":{"skill":"code-reviewer"}}]}}
{"type":"user","message":{"role":"user","content":"done"}}
EOF

# Test 4: 6 writes across 6 directories, all .md, 0 Task → NOT block
cat > "$TMPDIR/tr4.jsonl" << 'EOF'
{"type":"user","message":{"role":"user","content":"write documentation"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"docs1/README.md","content":"# README"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"docs2/CONFIG.md","content":"# Config"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"docs3/API.md","content":"# API"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"docs4/SETUP.md","content":"# Setup"}},{"type":"tool_use","id":"5","name":"Write","input":{"file_path":"docs5/GUIDE.md","content":"# Guide"}},{"type":"tool_use","id":"6","name":"Write","input":{"file_path":"docs6/NOTES.md","content":"# Notes"}}]}}
{"type":"user","message":{"role":"user","content":"done"}}
EOF

echo "=== PROOF 1: 5 fixtures (1 dir, 1 ext, 0 Task) → must NOT block ==="
echo '{"transcript_path":"'"$TMPDIR/tr1.jsonl"'","session_id":"proof1","stop_hook_active":false}' | bash "$hook"
result=$?
[ $result -eq 0 ] && echo "(no output - correctly passed)" || echo "(ERROR: exit $result)"
echo ""

echo "=== PROOF 2: Multi-dir/ext (4 dirs, 3 ext, 0 Task) → must BLOCK ==="
echo '{"transcript_path":"'"$TMPDIR/tr2.jsonl"'","session_id":"proof2","stop_hook_active":false}' | bash "$hook"
echo ""

echo "=== PROOF 3: Same as PROOF 2 + 1 Task → must NOT block ==="
echo '{"transcript_path":"'"$TMPDIR/tr3.jsonl"'","session_id":"proof3","stop_hook_active":false}' | bash "$hook"
result=$?
[ $result -eq 0 ] && echo "(no output - correctly passed)" || echo "(ERROR: exit $result)"
echo ""

echo "=== PROOF 4: Wide sweep (6 dirs, 1 ext .md, 0 Task) → must NOT block ==="
echo '{"transcript_path":"'"$TMPDIR/tr4.jsonl"'","session_id":"proof4","stop_hook_active":false}' | bash "$hook"
result=$?
[ $result -eq 0 ] && echo "(no output - correctly passed)" || echo "(ERROR: exit $result)"

rm -rf "$TMPDIR"
