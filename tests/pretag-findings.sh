# shellcheck shell=bash
# The one doctor finding a commit-triggered lane cannot be asked about.
#
# `bin/doctor`'s "declared release is fetchable" does a live `git ls-remote --tags origin` for the
# version the manifests declare. That is the right question asked of the right machine, and it is
# the fix for a catalogued defect where check 24 answered it from whatever tags the operator
# happened to have locally. Nothing here weakens it for a user.
#
# What it cannot do is answer inside a lane triggered by the COMMIT that declares the version.
# `verify.yml` runs on `push: branches: [main]`; the tag is a separate ref pushed seconds later,
# and `release.yml` is a separate event. So every ordinary release puts install-matrix and
# container-matrix inside the window where the manifests already say v1.N.0 and origin does not
# yet carry the tag. Those lanes then report a red that is true about this instant and says
# nothing about the candidate.
#
# On 2026-09-01 that red destroyed the v1.61.0 tag twice. `resolve` read `conclusion=failure` on
# install-alpine, which had started three seconds after the tag push and re-queried origin later
# still, called the gate decided, and `cleanup-on-failed-gate` deleted the tag whose absence was
# the entire finding. `require-checks-green.sh`'s staleness carve-out did not fire, correctly by
# its own rule: it excuses a run that STARTED before the candidate existed, and this one started
# after. The margin is not the bug. Asking a commit-triggered lane about a tag is the bug.
#
# So this finding, and only this finding, is a note in those two harnesses. Fetchability is still
# gated, in the only lane that can answer it without a race: `release.yml`'s `resolve` job exists
# because the tag was pushed, and `container-matrix` clones at the tag itself.
#
# One entry, by name. Check 62 of .claude/verify.sh fails if this list grows, if either harness
# stops reading it, or if `bin/doctor` stops treating the same finding as a hard failure for a
# user -- the carve-out is scoped to two test lanes and must not leak into the tool.
# shellcheck disable=SC2034  # read by the two harnesses that source this file, not by it
PRETAG_ALLOWED_FINDING='declared release is fetchable'
