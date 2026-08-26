# Select the authoritative check-run for one ($n, $s) pair out of the stream gh returns.
#
# This file exists as a separate jq program, rather than inline in require-checks-green.sh, so
# that tests/require-checks-green.sh can run the real selection logic against fixtures instead
# of a re-implementation of it. A test that re-implements the thing it tests agrees with itself
# forever. There is deliberately no environment seam in the shell script for injecting fake
# check-run JSON: a release gate with a bypass is not a gate.
#
# The rule is recency, and the fields it needs must survive the projection in the caller. The
# first version of this selection was `sort_by(.name) | last` applied to an array already
# filtered to a single name -- a stable sort on a constant key, so it returned whatever the API
# happened to put last, and the caller's --jq projection had already discarded every timestamp,
# so no fix was possible in place. A manual re-run to green could therefore be read as the
# earlier failure, or an earlier success read over a later failure.
#
# Recency is started_at, then id. NOT completed_at first: a run still in progress has no
# completed_at, and ordering on it put an in-flight re-run BELOW the finished older run it was
# re-running, so the gate would have read the stale finished result and published while the real
# check was still going. That was written here as a fallback chain and was wrong; the test in
# tests/require-checks-green.sh caught it, which is the only reason it is not still wrong.
# started_at exists on every run GitHub returns, in flight or finished, which is what makes it
# the right primary key.
# Anything with no usable ordering key at all sorts first, so it can never win by accident.
[ .[] | select(.name == $n and .head_sha == $s) ]
| if length == 0 then null
  else
    ( sort_by([ (.started_at // ""), (.id // 0) ]) ) as $ordered
    | ( $ordered | last ) as $latest
    | $latest
      + { attempts: ($ordered | length)
        , earlier_conclusions: ( $ordered[:-1] | map(.conclusion // "null") )
        }
  end
