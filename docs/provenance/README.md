# Provenance

Design history salvaged from `conductor-setup`, the private incubator repo this project was
extracted from (now archived at `github.com/itsvedantkumar/conductor-setup`). These documents
explain why vstack is shaped the way it is; nothing here is load-bearing at runtime.

- [`pstack-audit.md`](pstack-audit.md) — the Fit/Benefit scoring of every pstack skill against
  6,334 claude-mem observations, which decided the 18 skills ported in v1.0. The adoption
  sequence and porting-cost rules live here.
- [`conductor-e2e-audit.md`](conductor-e2e-audit.md) — the end-to-end audit rubric (R1–R8)
  run against a live Conductor session, with evidence and the residual risks left open.
- [`plans/`](plans/) — the working plans that survive publication: the global-CLAUDE.md
  overhaul audit, the vstack hardening plan (the G1–G7 gate-defect findings), and the plan
  that finished phases 3–4 and merged the incubator into this repo.

The plans that reverse-engineered this machine's Conductor parity and the phone/Remote
Control dispatch lane stay out of the public tree on purpose: they are wall-to-wall local
machine internals (dotfile layout, credential store locations), which no reader needs and
this repo's own gate exists to keep out. They are preserved locally, outside version control.

Counts and claims inside these documents were true when written and are not maintained;
`.claude/verify.sh` check 12 deliberately does not scan this directory.
