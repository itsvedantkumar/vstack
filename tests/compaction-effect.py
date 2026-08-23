#!/usr/bin/env python3
"""compaction-effect.py -- extraction engine for tests/compaction-effect.sh.

Reads local Claude Code transcript JSONL files, finds compact_boundary records, and computes
before/after-boundary rates for four cheap proxies of degraded post-compaction behaviour.

CAUSAL LIMIT (read this before reading a number below): this is observational, not an experiment.
A session that reaches the ~230K-token auto-compaction trigger is not a random draw from the same
population as one that never does -- it ran longer, touched more files, and is more likely to be
doing something that was already going badly before any boundary fired. A rate difference here is
evidence of an association between compaction and a proxy metric, and it is not evidence that
compaction CAUSED the difference. The auto-vs-manual split narrows but does not close this gap:
manual compactions are still selected by whatever made the user decide to compact right then.
Anyone citing this script's output as "compaction causes X" is misreading it.

Pre-registered thresholds (fixed before this file was run against real data; see
tests/compaction-effect.sh header for the full pre-registration and the order of operations):
  TURN_WINDOW=15          tool-calls counted on each side of a boundary
  MIN_WINDOW_CALLS=3      a boundary must have >=3 resolved tool-calls on EACH side to be pooled
  DUP_RATIO=0.6           difflib.SequenceMatcher.ratio() floor to call two user turns near-dup
  ABANDON_CALLS=3         fewer than this many tool-calls after a session's LAST boundary before
                          the transcript ends counts as abandonment
  SIGNAL_RATIO=1.5        post/pre rate ratio at/above this is the pre-registered "signal" line
  MIN_BOUNDARIES_FOR_SIGNAL=3     pooled boundaries required before a ratio is reported as signal
  MIN_POOLED_CALLS_FOR_SIGNAL=15  pooled tool-calls required (same floor)
All of these are overridable by environment variable of the same name, for reruns at a different
window; the values above are what this run used unless the report says otherwise.

Definitions, stated precisely because a proxy is only as good as its definition:
  is_error rate      -- fraction of resolved tool_result blocks with is_error == true. A
                         tool_result missing the is_error key entirely is treated as success
                         (verified against this corpus: absent-key results are Write/Edit/Read/
                         Agent/Skill/SendMessage calls that completed normally).
  re-read rate        -- fraction of Read calls, plus Grep calls that carry an explicit "path"
                         input, whose target was already the target of an earlier Read/Grep
                         (with path) anywhere earlier in the SAME session. Grep calls with no
                         "path" (repo-wide search) are excluded: they are not "a file path
                         already touched", they are a fresh search.
  near-duplicate turn -- a user-authored text message (not a tool_result) whose difflib ratio
                         against any EARLIER user text message in the same session is >= DUP_RATIO.
  abandonment          -- restricted to a session's LAST boundary only (an earlier boundary being
                         followed by another compaction is not abandonment, it is more work).
                         True if fewer than ABANDON_CALLS tool-calls occur between that boundary
                         and the end of the transcript.

Streaming: files are read one line at a time and only small extracted fields (tool name, a path
string, is_error, a truncated user-text string) are retained; the full parsed JSON object for a
line is dropped before the next line is read. This bounds peak memory by the largest single
line, not by transcript size -- some transcripts here approach 1M tokens and must not be slurped.
"""

import difflib
import json
import math
import os
import sys

WINDOW = int(os.environ.get("TURN_WINDOW", "15"))
MIN_WINDOW_CALLS = int(os.environ.get("MIN_WINDOW_CALLS", "3"))
DUP_RATIO = float(os.environ.get("DUP_RATIO", "0.6"))
ABANDON_CALLS = int(os.environ.get("ABANDON_CALLS", "3"))
SIGNAL_RATIO = float(os.environ.get("SIGNAL_RATIO", "1.5"))
MIN_BOUNDARIES_FOR_SIGNAL = int(os.environ.get("MIN_BOUNDARIES_FOR_SIGNAL", "3"))
MIN_POOLED_CALLS_FOR_SIGNAL = int(os.environ.get("MIN_POOLED_CALLS_FOR_SIGNAL", "15"))
USER_TEXT_CAP = (
    4000  # chars kept per user message for difflib; bounds memory, not correctness
)


def wilson_interval(k, n, z=1.96):
    """95% Wilson score interval. n==0 returns the maximally uninformative (0.0, 1.0)."""
    if n == 0:
        return (0.0, 1.0)
    phat = k / n
    denom = 1 + z * z / n
    center = (phat + z * z / (2 * n)) / denom
    half = (z * math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n))) / denom
    return (max(0.0, center - half), min(1.0, center + half))


def read_target(tool_name, tool_input):
    if not isinstance(tool_input, dict):
        return None
    if tool_name == "Read":
        return tool_input.get("file_path")
    if tool_name == "Grep":
        p = tool_input.get("path")
        return p if p else None
    return None


def extract_session(path):
    """Stream one transcript. Returns a dict describing boundaries and windowed events, or
    None if the file has no compact_boundary at all (caller should not have opened it)."""
    tool_events = []  # (line_idx, name, target, is_error_or_None)
    user_events = []  # (line_idx, text)
    boundaries = []  # (line_idx, trigger, preTokens, postTokens)
    pending = {}  # tool_use_id -> index into tool_events

    line_idx = 0
    last_line_idx = 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line_idx += 1
            raw = raw.strip()
            if not raw:
                continue
            try:
                d = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                continue
            last_line_idx = line_idx
            t = d.get("type")
            if t == "assistant":
                content = d.get("message", {}).get("content")
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "tool_use":
                            name = c.get("name")
                            target = read_target(name, c.get("input"))
                            tool_events.append([line_idx, name, target, None])
                            tuid = c.get("id")
                            if tuid:
                                pending[tuid] = len(tool_events) - 1
            elif t == "user":
                content = d.get("message", {}).get("content")
                if isinstance(content, str):
                    user_events.append((line_idx, content[:USER_TEXT_CAP]))
                elif isinstance(content, list):
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        if c.get("type") == "tool_result":
                            idx = pending.get(c.get("tool_use_id"))
                            if idx is not None:
                                tool_events[idx][3] = bool(c.get("is_error", False))
                        elif c.get("type") == "text":
                            txt = c.get("text")
                            if isinstance(txt, str):
                                user_events.append((line_idx, txt[:USER_TEXT_CAP]))
            elif t == "system" and d.get("subtype") == "compact_boundary":
                meta = d.get("compactMetadata", {}) or {}
                boundaries.append(
                    {
                        "line_idx": line_idx,
                        "trigger": meta.get("trigger", "?"),
                        "pre_tokens": meta.get("preTokens"),
                        "post_tokens": meta.get("postTokens"),
                        "dropped_tokens": meta.get("cumulativeDroppedTokens"),
                    }
                )
            # every other type (queue-operation, attachment, mode, last-prompt, pr-link) carries
            # nothing this script measures; the object is dropped here, not retained.
            del d

    if not boundaries:
        return None
    return {
        "path": path,
        "tool_events": tool_events,
        "user_events": user_events,
        "boundaries": boundaries,
        "last_line_idx": last_line_idx,
    }


def window_slice(events, boundary_line, before):
    """Up to WINDOW tool_events strictly before/after boundary_line, by line order."""
    if before:
        cands = [e for e in events if e[0] < boundary_line]
        return cands[-WINDOW:]
    cands = [e for e in events if e[0] > boundary_line]
    return cands[:WINDOW]


def analyze_boundary(sess, b_idx):
    tool_events = sess["tool_events"]
    boundary = sess["boundaries"][b_idx]
    bline = boundary["line_idx"]

    pre = window_slice(tool_events, bline, before=True)
    post = window_slice(tool_events, bline, before=False)

    def resolved(evts):
        return [e for e in evts if e[3] is not None]

    pre_resolved, post_resolved = resolved(pre), resolved(post)
    pre_err = sum(1 for e in pre_resolved if e[3])
    post_err = sum(1 for e in post_resolved if e[3])

    # Re-reads: "target already touched earlier in the session" using each call's OWN position,
    # not the boundary, so the same yardstick applies to both windows.
    seen = set()
    reread_by_line = {}
    for e in tool_events:
        _, name, target, _ = e
        if name not in ("Read", "Grep") or not target:
            continue
        reread_by_line[e[0]] = target in seen
        seen.add(target)

    def reread_stats(evts):
        rel = [e for e in evts if e[1] in ("Read", "Grep") and e[2]]
        hits = sum(1 for e in rel if reread_by_line.get(e[0], False))
        return hits, len(rel)

    pre_reread_hits, pre_reread_n = reread_stats(pre)
    post_reread_hits, post_reread_n = reread_stats(post)

    # Near-duplicate user turns within the same line ranges as the tool windows. When a window
    # is TRUNCATED (fewer than WINDOW tool-calls exist on that side) the bound extends all the
    # way to session start/end rather than to the last tool-call line -- otherwise a user turn
    # that arrives after the last captured tool-call but before the session actually ends (the
    # exact shape a post-boundary abandonment takes) is silently dropped from the count. Bug
    # found and fixed against a hand-built synthetic transcript before this ran on real data.
    pre_lo = pre[0][0] if len(pre) == WINDOW else 0
    post_hi = post[-1][0] if len(post) == WINDOW else sess["last_line_idx"]
    all_user = sess["user_events"]

    def is_near_dup(i):
        _, text = all_user[i]
        if not text.strip():
            return False
        for j in range(i):
            if difflib.SequenceMatcher(None, text, all_user[j][1]).ratio() >= DUP_RATIO:
                return True
        return False

    pre_dup = post_dup = pre_user_n = post_user_n = 0
    for i, (lidx, _) in enumerate(all_user):
        if pre_lo <= lidx < bline:
            pre_user_n += 1
            if is_near_dup(i):
                pre_dup += 1
        elif bline < lidx <= post_hi:
            post_user_n += 1
            if is_near_dup(i):
                post_dup += 1

    return {
        "trigger": boundary["trigger"],
        "pre_tokens": boundary["pre_tokens"],
        "post_tokens": boundary["post_tokens"],
        "pre_window_calls": len(pre),
        "post_window_calls": len(post),
        "pre_err": pre_err,
        "pre_err_n": len(pre_resolved),
        "post_err": post_err,
        "post_err_n": len(post_resolved),
        "pre_reread": pre_reread_hits,
        "pre_reread_n": pre_reread_n,
        "post_reread": post_reread_hits,
        "post_reread_n": post_reread_n,
        "pre_dup": pre_dup,
        "pre_user_n": pre_user_n,
        "post_dup": post_dup,
        "post_user_n": post_user_n,
        "qualifies": len(pre_resolved) >= MIN_WINDOW_CALLS
        and len(post_resolved) >= MIN_WINDOW_CALLS,
    }


def pool(rows, key_hits, key_n):
    hits = sum(r[key_hits] for r in rows)
    n = sum(r[key_n] for r in rows)
    return hits, n


def rate_report(label, hits, n):
    if n == 0:
        return f"{label}: n=0 (no qualifying tool-calls)"
    lo, hi = wilson_interval(hits, n)
    return f"{label}: {hits}/{n} = {hits / n:.3f}  (95% CI {lo:.3f}-{hi:.3f})"


def signal_verdict(pre_hits, pre_n, post_hits, post_n, n_boundaries):
    if n_boundaries < MIN_BOUNDARIES_FOR_SIGNAL:
        return f"NOT EVALUATED -- only {n_boundaries} qualifying boundaries, need >= {MIN_BOUNDARIES_FOR_SIGNAL}"
    if pre_n < MIN_POOLED_CALLS_FOR_SIGNAL or post_n < MIN_POOLED_CALLS_FOR_SIGNAL:
        return f"NOT EVALUATED -- pooled calls pre={pre_n} post={post_n}, need >= {MIN_POOLED_CALLS_FOR_SIGNAL} each"
    pre_rate = pre_hits / pre_n if pre_n else 0.0
    post_rate = post_hits / post_n if post_n else 0.0
    if pre_rate == 0:
        ratio_desc = (
            "pre-rate is 0; any post-rate > 0 cannot be expressed as a finite ratio"
        )
        signal = post_hits > 0
    else:
        ratio = post_rate / pre_rate
        ratio_desc = f"ratio={ratio:.2f}x"
        signal = ratio >= SIGNAL_RATIO
    return f"{'SIGNAL' if signal else 'no signal'} ({ratio_desc}, threshold {SIGNAL_RATIO}x)"


def main():
    file_list_path = sys.argv[1] if len(sys.argv) > 1 else None
    total_sessions = int(os.environ.get("TOTAL_SESSIONS", "0"))
    if file_list_path:
        with open(file_list_path) as fh:
            candidates = [line.strip() for line in fh if line.strip()]
    else:
        candidates = []

    declared = len(candidates)
    ran = 0
    skipped = 0
    sessions = []
    for path in candidates:
        try:
            sess = extract_session(path)
        except OSError as e:
            print(f"skip  {path}: {e}", file=sys.stderr)
            skipped += 1
            continue
        if sess is None:
            skipped += 1
            continue
        sessions.append(sess)
        ran += 1

    print("=== compaction-effect: bucketing ===")
    print(f"total local transcripts scanned for candidacy: {total_sessions}")
    print(f"transcripts containing >=1 compact_boundary:    {declared}")
    auto_sessions = sum(
        1 for s in sessions if any(b["trigger"] == "auto" for b in s["boundaries"])
    )
    manual_sessions = sum(
        1 for s in sessions if any(b["trigger"] == "manual" for b in s["boundaries"])
    )
    both_sessions = sum(
        1
        for s in sessions
        if any(b["trigger"] == "auto" for b in s["boundaries"])
        and any(b["trigger"] == "manual" for b in s["boundaries"])
    )
    print(f"  sessions with >=1 auto-trigger boundary:      {auto_sessions}")
    print(f"  sessions with >=1 manual-trigger boundary:    {manual_sessions}")
    print(f"  sessions with both:                           {both_sessions}")
    total_boundaries = sum(len(s["boundaries"]) for s in sessions)
    auto_boundaries_n = sum(
        1 for s in sessions for b in s["boundaries"] if b["trigger"] == "auto"
    )
    manual_boundaries_n = sum(
        1 for s in sessions for b in s["boundaries"] if b["trigger"] == "manual"
    )
    print(
        f"total compact_boundary records: {total_boundaries}  (auto={auto_boundaries_n}, manual={manual_boundaries_n})"
    )

    if ran == 0:
        print()
        print(
            "INCONCLUSIVE: zero sessions with a compact_boundary were found on this machine."
        )
        print(
            "No before/after rate can be computed. This is not a passing result and must not"
        )
        print("be read as one.")
        print(f"accounting: {declared} declared / {ran} ran / {skipped} skipped")
        return 1

    rows = []
    for sess in sessions:
        for b_idx in range(len(sess["boundaries"])):
            r = analyze_boundary(sess, b_idx)
            r["session"] = os.path.basename(sess["path"])
            r["is_last_boundary"] = b_idx == len(sess["boundaries"]) - 1
            r["last_line_idx"] = sess["last_line_idx"]
            r["boundary_line"] = sess["boundaries"][b_idx]["line_idx"]
            rows.append(r)

    print()
    print("=== per-boundary detail ===")
    print(
        f"{'session':<40} {'trig':<7} {'preW':>4} {'postW':>5} {'preErr':>7} {'postErr':>8} {'preRR':>6} {'postRR':>7} {'preDup':>7} {'postDup':>8} qual"
    )
    for r in rows:
        print(
            f"{r['session']:<40} {r['trigger']:<7} "
            f"{r['pre_window_calls']:>4} {r['post_window_calls']:>5} "
            f"{r['pre_err']}/{r['pre_err_n']:<5} {r['post_err']}/{r['post_err_n']:<6} "
            f"{r['pre_reread']}/{r['pre_reread_n']:<4} {r['post_reread']}/{r['post_reread_n']:<5} "
            f"{r['pre_dup']}/{r['pre_user_n']:<5} {r['post_dup']}/{r['post_user_n']:<6} "
            f"{'Y' if r['qualifies'] else 'n'}"
        )

    print()
    print(
        f"boundaries analyzed: {len(rows)}  (qualifying for pooled rates -- both windows >= {MIN_WINDOW_CALLS} resolved calls: {sum(1 for r in rows if r['qualifies'])})"
    )

    for trig in ("auto", "manual"):
        trig_rows = [r for r in rows if r["trigger"] == trig and r["qualifies"]]
        print()
        print(
            f"--- {trig}-trigger, pooled across {len(trig_rows)} qualifying boundaries (of {sum(1 for r in rows if r['trigger'] == trig)} total {trig} boundaries) ---"
        )
        if not trig_rows:
            print("  no qualifying boundaries for this trigger; nothing pooled.")
            continue
        pre_e, pre_en = pool(trig_rows, "pre_err", "pre_err_n")
        post_e, post_en = pool(trig_rows, "post_err", "post_err_n")
        print("  " + rate_report("is_error pre ", pre_e, pre_en))
        print("  " + rate_report("is_error post", post_e, post_en))
        print(
            "  verdict: "
            + signal_verdict(pre_e, pre_en, post_e, post_en, len(trig_rows))
        )

        pre_r, pre_rn = pool(trig_rows, "pre_reread", "pre_reread_n")
        post_r, post_rn = pool(trig_rows, "post_reread", "post_reread_n")
        print("  " + rate_report("re-read pre  ", pre_r, pre_rn))
        print("  " + rate_report("re-read post ", post_r, post_rn))
        print(
            "  verdict: "
            + signal_verdict(pre_r, pre_rn, post_r, post_rn, len(trig_rows))
        )

        pre_d, pre_dn = pool(trig_rows, "pre_dup", "pre_user_n")
        post_d, post_dn = pool(trig_rows, "post_dup", "post_user_n")
        print("  " + rate_report("near-dup pre ", pre_d, pre_dn))
        print("  " + rate_report("near-dup post", post_d, post_dn))
        print(
            "  verdict: "
            + signal_verdict(pre_d, pre_dn, post_d, post_dn, len(trig_rows))
        )

    print()
    print(
        f"--- abandonment (last boundary per session only, < {ABANDON_CALLS} tool-calls before transcript ends) ---"
    )
    last_rows = [r for r in rows if r["is_last_boundary"]]
    abandoned = [r for r in last_rows if r["post_window_calls"] < ABANDON_CALLS]
    for r in abandoned:
        print(
            f"  {r['session']} ({r['trigger']}): only {r['post_window_calls']} tool-call(s) after boundary before transcript ends"
        )
    lo, hi = (
        wilson_interval(len(abandoned), len(last_rows)) if last_rows else (0.0, 1.0)
    )
    if last_rows:
        print(
            f"  {len(abandoned)}/{len(last_rows)} = {len(abandoned) / len(last_rows):.3f}  (95% CI {lo:.3f}-{hi:.3f})  n={len(last_rows)} sessions"
        )
    else:
        print("  n=0 sessions")
    print(
        "  NOTE: 'transcript ends shortly after' is also what a session that simply finished"
    )
    print(
        "  successfully looks like. This proxy cannot distinguish abandonment from completion"
    )
    print(
        "  without reading message content, which this script does not attempt to judge."
    )

    print()
    print(f"accounting: {declared} declared / {ran} ran / {skipped} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
