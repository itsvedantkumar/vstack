# shellcheck shell=bash
# Sourced by ui-gate/ui-gate.sh; not executed directly.
# The four families that need a running browser. Declared and skipped with a rule ID and a reason,
# which the contract requires and which keeps them visible in the accounting rather than quietly
# absent. A skip is not a pass, and the summary line reports them separately for that reason.
#
# Each carries the mutation it will need when it is implemented, from research-v1.7.0.md, so the
# falsifiability requirement is written down before the rule exists rather than after.
_ui_no_browser="playwright is not vendored here; run ui-gate against a project that has it"

skip A11Y-AXE      "$_ui_no_browser (mutation: remove an accessible name)"
skip A11Y-KEYBOARD "$_ui_no_browser (mutation: remove a focus outline, break modal focus return)"
skip COV-STATES    "$_ui_no_browser (mutation: delete an error-state fixture)"
skip COV-VIEWPORT  "$_ui_no_browser (mutation: force horizontal overflow at 375px)"
skip VIS-SNAPSHOT  "$_ui_no_browser (mutation: shift a component one pixel)"
skip PERF-LAB      "$_ui_no_browser (mutation: inject an 80ms busy loop)"
