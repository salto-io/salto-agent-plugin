> [!IMPORTANT]
> **Gemini CLI notes** (this copy of the skill is built for Gemini CLI):
>
> - `<SKILL_DIR>` below means this skill's folder: the absolute path Gemini showed under `<available_resources>` when it activated the skill. Copy that path exactly and read every bundled file by its full path under it (file tools don't expand `~`). A relative path such as `references/...` resolves against the project, not the skill.
> - `$ARGUMENTS` means the user's request: the text sent with or after `/salto`, including flags such as `--workspace`, `--deployment-id` or `--branch-name`.
> - Gemini file tools work only in folders the user allowed. If a tool says a path (for example `WORKTREE_PATH` or `STATE_DIR`) is not in the workspace, stop: end your turn and ask the user to run `/directory add <WORKTREE_PATH>,<STATE_DIR>` (with the real paths), then continue when they say so. Don't look for another way around it: never edit the user's working tree instead, and never write NACL or PR-body content with shell commands (heredoc, `echo`, `python`, ...).
