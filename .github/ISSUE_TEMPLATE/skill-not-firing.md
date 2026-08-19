---
name: A skill is not firing
about: A situation that should trigger a skill does not
labels: routing
---

Skill dispatch is a model decision, so start by establishing it is not just variance.

**Which skill, and what did you say to trigger it?**
Paste the prompt verbatim. The wording is the whole mechanism.

**Did it ever fire?**
Try three times. `tests/auto-trigger.sh` allows three attempts per case because one sample is a
coin flip.

**Output of `./.claude/verify.sh`**
Check 3 catches a description that has grown past the listing cap, which silently truncates the
trigger phrases and stops the skill matching.

**Output of `bin/doctor`**
Confirms the skill is actually installed and the routing hook is wired.

**Is the skill listed in your session?**
If it appears as a bare name with no description, an override has it in `name-only` mode. If it
comes from a plugin, note that `skillOverrides` cannot reach it at all — see
docs/how-skills-fire.md.
