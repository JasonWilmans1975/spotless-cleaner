# Cleaner app — Claude Code handoff (for Liam)

1. Copy this whole folder into the cleaner app repo as `design/handoff/` and commit it on a new branch (e.g. `feat/redesign`).
2. Add one line to the repo's CLAUDE.md: `UI redesign in progress — follow design/handoff/HANDOFF.md for any UI work.`
3. Open Claude Code in the repo and paste the prompts from PROMPTS.md one at a time (Step 0 in Plan mode). `/clear` between steps.
4. After each step: hot-reload on the simulator, compare against `screens/NN-*.png`, ask for fixes, commit.

Contents: HANDOFF.md (brief + rules + tokens), PROMPTS.md (step prompts), screens/ (PNG targets, full-length PNGs, exact-value HTML, per-screen specs), spotless_theme.dart.
