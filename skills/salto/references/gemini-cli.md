# Gemini CLI notes (read only in Gemini CLI)

SKILL.md tells Gemini CLI to read this file. Other agents don't need it. These notes add to SKILL.md and the workflow files, and they win where they differ.

- `<SKILL_DIR>` is this skill's folder: the absolute path Gemini showed under `<available_resources>` when it activated the skill. Copy that path exactly and read every bundled file by its full path under it (file tools don't expand `~`). A relative path such as `references/salto-deploy.md` resolves against the project, not the skill.
- `$ARGUMENTS` in the skill files means the user's request: the text sent with or after `/salto`, including flags such as `--workspace`, `--deployment-id` or `--branch-name`.
- Gemini file tools work only in folders the user allowed. If a tool says a path (for example `WORKTREE_PATH` or `STATE_DIR`) is not in the workspace, stop: end your turn and ask the user to run `/directory add <WORKTREE_PATH>,<STATE_DIR>` (with the real paths), then continue when they say so. Don't look for another way around it: never edit the user's working tree instead, and never write files in those folders with shell commands (heredoc, `echo`, `python`, ...).
- Gemini users should start Gemini inside the workspace folder rather than pass `--workspace`. Where a workflow says "Re-run with `--workspace <path>`", tell the user to start Gemini inside the workspace instead. If the user does pass `--workspace`, use it.
- In the DEPLOY workflow, make every NACL edit inside `WORKTREE_PATH` (from `salto-cli deployment prepare-worktree`), never in the user's workspace folder. If you can't find or run `salto-cli`, stop and ask the user; don't edit files without it.
- Never install or run `salto-cli` with `npx` or `npm`: Salto doesn't publish it on npm, so anyone could publish a package with that name. If `salto-cli` is missing, stop and ask the user.
