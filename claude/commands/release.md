---
name: release
description: Coordinate a release via the release-manager subagent.
---

Coordinate a release. **$ARGUMENTS**

Release decisions are made by the release-manager subagent (UNITY), which is wired into the `/team` command's phase 7 (Ship). This is not a standalone release command; it is a phase within the full engineering workflow.

1. **Use the `/team` command to run a release goal.** Example: `/team Release patch 1.2.3` or `/team Release with semantic versioning based on commits since 1.2.2`. The `/team` command will:
   a. Route the goal to the product-owner (phase 1: Spec) to confirm the release intent.
   b. Route to the planner (phase 2: Plan) if multiple systems are affected.
   c. Route to the build phase (phase 3), which for a release means updating version files, tags, and changelog.
   d. Route to QA (phase 4: Verify) to confirm the release artifact is deployable.
   e. Route to reviewers (phase 5: Review) to audit the changes.
   f. Route to the release-manager subagent (phase 7: Ship), which:
      - Bumps the version (patch/minor/major based on conventional commits if no explicit level was given).
      - Updates CHANGELOG.md from commit history.
      - Creates a git tag with the new version.
      - Pushes the tag and the updated main branch.

2. **The release-manager subagent reads commit history.** If your commits follow the conventional commit format (`feat:`, `fix:`, `feat!:`, etc.), the subagent auto-detects whether this is a patch, minor, or major release. If you specified the level explicitly (in your `/team` goal), the subagent uses that.

3. **After release-manager finishes,** the deploy command (phase 8, separate from `/team`) will deploy the tagged version.

See `/team` for the full workflow and how each phase works.
