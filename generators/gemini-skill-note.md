> [!IMPORTANT]
> **Gemini CLI notes** (this copy of the skill is built for Gemini CLI):
>
> - `<SKILL_DIR>` below means this skill's folder: the absolute path Gemini showed under `<available_resources>` when it activated the skill. Copy that path exactly and read every bundled file by its full path under it (file tools don't expand `~`). A relative path such as `references/...` resolves against the project, not the skill.
> - `$ARGUMENTS` means the user's request: the text sent with or after `/salto`, including flags such as `--workspace`, `--deployment-id` or `--branch-name`.
> - Gemini file tools work only in folders the user allowed. If a tool says a path (for example `WORKTREE_PATH` or `STATE_DIR`) is not in the workspace, stop and ask the user to run `/directory add <path>` (comma-separate several paths), then continue. Never edit the user's working tree instead, and don't write files with shell commands.
