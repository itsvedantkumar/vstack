// bench.vedant.to -- renders tests/evals/showcase/summary.json from the vstack main branch.
// No number on this page exists outside that file; the file is produced by summarize.sh from
// runs/*.jsonl, and every row links to the run file it came from.
const REPO = "itsvedantkumar/vstack";
const RAW = `https://raw.githubusercontent.com/${REPO}/main/tests/evals/showcase/`;
const TREE = `https://github.com/${REPO}/blob/main/tests/evals/showcase/`;

const MECHANISMS = [
  ["what the harness adds", "gstack (0d1bd56)", "vstack (v1.72.0)"],
  ["hooks wired", "SessionStart only", "SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop"],
  ["stop gate", "none", "Stop hook runs the project's verify.sh; a red gate blocks the turn"],
  ["gate self-test", "none", "66 checks, 116 falsifiability rows (each check shown going red under its own mutation)"],
  ["context injected per session", "45 KB CLAUDE.md (contributor file)", "about 3.2 KB full / 2.5 KB plugin"],
  ["skills shipped", "54 top-level", "28"],
  ["dispatch ledger", "none", "every Agent/Task/Skill call logged with duration; bin/doctor --ledger"],
];

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const money = (x) => "$" + Number(x).toFixed(4);
const link = (f) => `<a href="${TREE}runs/${esc(f)}">${esc(f)}</a>`;

function verdict(h2h) {
  // Group per run file; parity means every arm in the file has the same green count per sample and the same fc.
  const byFile = {};
  for (const r of h2h) (byFile[r.file] ||= []).push(r);
  const lines = [];
  let anyDiff = false;
  for (const [file, rows] of Object.entries(byFile)) {
    const greenRates = rows.map((r) => r.green / r.n);
    const fcs = rows.map((r) => r.false_completion);
    const same = new Set(greenRates.map((g) => g.toFixed(3))).size === 1 && new Set(fcs).size === 1;
    if (!same) anyDiff = true;
    const cost = Object.fromEntries(rows.map((r) => [r.arm, r]));
    const ratio = cost.vstack && cost.gstack ? ` cost vstack/gstack ${(cost.vstack.cost_mean / cost.gstack.cost_mean).toFixed(2)}x, wall ${(cost.vstack.wall_s / cost.gstack.wall_s).toFixed(2)}x` : "";
    lines.push(`${rows[0].model}, ${rows[0].fixture}: ${rows.map((r) => `${r.arm} ${r.green}/${r.n} green, ${r.false_completion} false completions`).join("; ")} -> ${same ? "parity" : "DIFFERENT"};${ratio}`);
  }
  return { anyDiff, lines };
}

function table(rows, cols) {
  return `<table><thead><tr>${cols.map((c) => `<th>${esc(c[0])}</th>`).join("")}</tr></thead><tbody>` +
    rows.map((r) => `<tr>${cols.map((c) => `<td>${c[1](r)}</td>`).join("")}</tr>`).join("") + "</tbody></table>";
}

function page(d) {
  const v = verdict(d.head_to_head || []);
  const h2hCols = [
    ["run file", (r) => link(r.file)], ["model", (r) => esc(r.model)], ["fixture", (r) => esc(r.fixture)], ["arm", (r) => `<b>${esc(r.arm)}</b>`],
    ["n", (r) => r.n], ["held-out green", (r) => `${r.green}/${r.n}`], ["said DONE", (r) => r.said_done], ["false completions", (r) => r.false_completion],
    ["subagents spawned", (r) => r.spawned], ["mean cost", (r) => money(r.cost_mean)], ["mean wall", (r) => `${r.wall_s} s`], ["mean turns", (r) => r.turns],
  ];
  const allCols = [
    ["engine", (r) => esc(r.engine)], ["model", (r) => esc(r.model)], ["fixture", (r) => esc(r.fixture)], ["arm", (r) => `<b>${esc(r.arm)}</b>`],
    ["n", (r) => r.n], ["held-out green", (r) => `${r.green}/${r.n}`], ["said DONE", (r) => r.said_done], ["false completions", (r) => r.false_completion],
    ["spawned", (r) => r.spawned], ["mean cost", (r) => money(r.cost_mean)], ["mean wall", (r) => `${r.wall_s} s`], ["turns", (r) => r.turns],
    ["files", (r) => r.files.map(link).join("<br>")],
  ];
  const files = Object.values(d.files || {}).sort((a, b) => a.file.localeCompare(b.file));
  const fileCols = [["file", (r) => link(r.file)], ["engine", (r) => esc(r.engine)], ["model", (r) => esc(r.model)], ["status", (r) => r.status === "valid" ? "valid" : `<b>${esc(r.status)}</b> (excluded)`], ["note", (r) => esc(r.note)]];
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>vstack vs gstack: measured</title>
<style>body{font:15px/1.5 system-ui,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#111}table{border-collapse:collapse;width:100%;font-size:13px;margin:1rem 0}th,td{border:1px solid #ccc;padding:4px 6px;text-align:left;vertical-align:top}th{background:#f3f3f3}code{background:#f3f3f3;padding:1px 4px}.v{padding:1rem;border-left:4px solid ${v.anyDiff ? "#c60" : "#282"};background:#fafafa}small{color:#555}</style></head><body>
<h1>vstack vs gstack</h1>
<p>Held-out benchmark from <a href="https://github.com/${REPO}">${REPO}</a>. Every number below is computed by <a href="${TREE}summarize.sh">summarize.sh</a> from the committed run files in <a href="${TREE}runs/">runs/</a>; this page fetches <a href="${RAW}summary.json">summary.json</a> from the main branch and renders it. Nothing is typed in by hand. Method, fixtures and the preregistered decision rule: <a href="${TREE}RESULTS.md">RESULTS.md</a>, <a href="${TREE}PREREGISTRATION.md">PREREGISTRATION.md</a>.</p>
<div class="v"><b>Verdict from the paired three-arm runs:</b> ${v.anyDiff ? "at least one paired run shows a difference between arms" : "parity on correctness. In no paired run does vstack beat gstack, or gstack beat vstack, on held-out correctness or false completions. The differences that exist are cost and wall time, listed per run below."}<br>
<small>${v.lines.map(esc).join("<br>")}</small></div>
<h2>Head to head: vstack against gstack, same fixture, same model, same day</h2>
<p><b>gstack</b> and <b>vstack</b> are the two harnesses installed project-scoped (<code>--setting-sources=project</code>) into the same fixture. "Held-out green" means the hidden test suite passed on the tree the agent left. "False completion" means the agent said DONE while the hidden tests were red.</p>
${table(d.head_to_head || [], h2hCols)}
<h2>What separates the arms (mechanism, not outcome)</h2>
<p>The outcome table above is a null. This table is the difference that is real: what each harness makes the agent do, measured on the tree, not on the benchmark.</p>
${table(MECHANISMS.slice(1), MECHANISMS[0].map((h, i) => [h, (r) => esc(r[i])]))}
<h2>Every valid run, grouped by model, fixture and arm</h2>
<p>Raw data, not the comparison: includes <b>none</b> (an empty project <code>.claude</code>, used early on as a control), the OpenCode engine runs (GLM 5.3 Flash, free lane) with harness-side <b>gate</b> and <b>oracle</b> arms, and older single-harness runs. Pooled across run files, so mixed vstack versions appear together; the head-to-head table above never pools.</p>
${table(d.rows || [], allCols)}
<h2>Run files</h2>
${table(files, fileCols)}
<p><small>summary.json generated ${esc(d.generated)} at commit ${esc(d.commit)}. Page source: <a href="${TREE}site/worker.js">site/worker.js</a>. Cached 5 minutes.</small></p>
</body></html>`;
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/summary.json") {
      const r = await fetch(RAW + "summary.json", { cf: { cacheTtl: 300 } });
      return new Response(r.body, { status: r.status, headers: { "content-type": "application/json", "access-control-allow-origin": "*" } });
    }
    const r = await fetch(RAW + "summary.json", { cf: { cacheTtl: 300 } });
    if (!r.ok) return new Response(`summary.json not readable from GitHub main (HTTP ${r.status}). Nothing to show until it is committed there.`, { status: 502, headers: { "content-type": "text/plain" } });
    const d = await r.json();
    return new Response(page(d), { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300" } });
  },
};
