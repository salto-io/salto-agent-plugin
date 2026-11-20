# salto-cli-skills

Agent skills for Claude Code, GitHub Copilot CLI and Gemini CLI that automate [Salto](https://www.salto.io) NACL workflows: fast credential-free local validation, deploy orchestration, and end-to-end change loops against SaaS-managed Salto environments.

## What this plugin gives you

A single slash command — `/salto "<natural language request>"` — that routes your request to the right workflow: **Explore** or **Deploy**.

Adapter-specific knowledge is loaded automatically based on what your workspace uses, from a per-adapter directory (`adapters/<adapter>/`). The Salesforce directory also carries CPQ and RLM knowledge. The plugin ships those workflow definitions and adapter knowledge as reference content; only `/salto` shows up in your command list.

### Explore (read-only)

Ask questions. Nothing is changed.

- **List elements** — "what Zendesk triggers exist in prod?"
- **Inspect an element** — "show me the `welcome_message` trigger"
- **Preview changes** — "what would change if I deployed now?"
- **Deployment history** — "list my recent deployments"
- **Workspace info** — "which adapters and environments do I have?"

### Deploy (make changes)

Describe the change (add, change, rename, delete, enable, disable, fix). The plugin runs the full flow:

1. **Pre-flight checks** — workspace, git, auth, target environment.
2. **Edit** — changes NACL files in a separate git branch and worktree. Your working folder is never touched.
3. **Validate locally** — fast, no app credentials needed. Fixes its own errors automatically.
4. **Security scan** — stops and asks you on Critical/High issues.
5. **Open a PR** — on GitHub or Azure DevOps, with a clear summary.
6. **Create a Salto deployment** from the PR and run the Salto preview. Fixes remaining errors automatically.
7. **Report** — PR link, deployment link, list of changes, and validation status (🟢 / 🟡 / 🔴).

More:

- **Continue an existing deployment** — `--deployment-id <id>` or `--branch-name <name>`.
- **Ticket-driven work** — put a ticket in the request (Jira, Azure DevOps, and others). The plugin can read the task from the ticket, and comments back with the PR, deployment, and decisions you made.
- **Focus on your change only** — old, unrelated errors in the workspace do not block your change.
- **You stay in control** — the plugin never applies the deployment. You approve it in the Salto UI.

### Supported applications

Works with any Salto-supported application, including:

- **Salesforce** (including CPQ and Revenue Cloud Advanced)
- **NetSuite**
- **Zendesk**
- **Jira**
- **Okta**

### Safety

- All edits happen on a separate `salto/...` branch.
- Nothing is pushed until local validation is clean.
- Never force-pushes outside `salto/...` branches.
- Stops immediately on authentication errors.
- Fix attempts are limited (5 local, 3 in Salto), then it stops and asks you.
- Never applies a deployment or pulls changes into your workspace by itself.

### Limitations

- Automatic PR + deployment creation works with **GitHub** and **Azure DevOps**. For other git hosts, open the PR manually and re-run with `--deployment-id`.
- The PR must target the branch your Salto environment tracks.

## Prerequisites

- **`salto-cli` on `$PATH`** — the skills call `salto-cli` for all SaaS-side work. Until a public installer is published, contact your Salto representative for the binary.
- **`git`** — required.
- **`gh` CLI authenticated** *(optional)* — if installed and authenticated (`gh auth login`), the deploy workflow opens PRs for you. Otherwise it just pushes the branch and prints a GitHub compare URL for you to open manually.
- **Azure DevOps access** *(optional)* — for Azure DevOps repos, export `AZURE_DEVOPS_EXT_PAT` (a PAT with Code Read & Write scope), or install the `az` CLI with the `azure-devops` extension, so the deploy workflow opens PRs for you. Otherwise it prints a PR-create URL for you to open manually.

## Install in Claude Code

```
/plugin marketplace add salto-io/salto-agent-plugin
/plugin install salto-cli-skills@salto-claude-plugin
```

The repo is public, so no GitHub credentials are needed to install it.

To update, run `claude plugin marketplace update salto-claude-plugin` and then `claude plugin update salto-cli-skills@salto-claude-plugin`, and restart Claude Code. Or turn on auto-update for the `salto-claude-plugin` marketplace in `/plugin` (Marketplaces tab).

## Install in GitHub Copilot CLI

```
copilot plugin marketplace add salto-io/salto-agent-plugin
copilot plugin install salto-cli-skills@salto-claude-plugin
```

To update, run `copilot plugin update salto-cli-skills`.

## Install in Gemini CLI

Choose one of these two options, not both (each one adds a `salto` skill).

**Option 1: extension (can update itself)**

```
gemini extensions install https://github.com/salto-io/salto-agent-plugin --auto-update
```

Gemini asks you to confirm. Check it with `gemini extensions list`. `--auto-update` turns on Gemini's automatic updates for this extension. To update now, run `gemini extensions update salto-cli-skills` (Gemini asks you to confirm), then restart Gemini.

**Option 2: skill only**

```
gemini skills install https://github.com/salto-io/salto-agent-plugin --path skills
```

This installs the `salto` skill for your user (all projects) in `~/.gemini/skills/salto`. Check it with `gemini skills list`. To update, run the same install command again. Gemini CLI does not update skills automatically.

### Start Gemini CLI for Salto

Gemini CLI limits the agent more than Claude Code does. For deploy requests, `salto-cli` creates the change worktree next to your workspace's git folder and keeps temp files in `TMPDIR`. Gemini edits files only in folders you allow, and it reads allowed folders without asking. So:

1. Put the workspace (its git folder) in a parent folder that holds only your Salto workspaces, for example `~/salto/<workspace>`. Gemini can read everything in that parent folder, so never use your home folder (or any folder with other files) as the parent. These steps assume the workspace folder is the root of its git repo (the usual Salto setup).
2. Start Gemini inside the workspace (don't use `--workspace`). Allow only the parent folder, and keep temp files in it:

   ```
   cd ~/salto/<workspace>
   mkdir -p ../tmp
   TMPDIR="$(cd .. && pwd)/tmp" gemini --include-directories ..
   ```

   Gemini asks whether to trust `..`; choose Yes. If you start Gemini without these folders, Gemini should stop and ask you to add the folder it needs with `/directory add <path>` (the skill tells it to). Weaker models sometimes try to get around this instead, for example by writing files with `python` or `cp`, or by editing your workspace folder directly. So only approve file writes inside the change worktree (`../<workspace>-salto-...`) and the temp folder (`../tmp`). Never approve edits in your workspace folder itself, or files written with `python`, `cp` or `echo`. This rule is about file edits and other shell commands that write files; the skill's own `salto-cli` commands (for example `prepare-worktree` and `ship`) are fine. Never approve `npx` or `npm` commands that install or run `salto-cli`: Salto doesn't publish it on npm, so anyone could publish a package with that name. If `salto-cli` is missing, the skill should stop and ask you.

   Gemini reads the whole parent folder, so from time to time remove old change worktrees (`git worktree remove ../<workspace>-salto-...`) and old `../tmp/salto-state-*` folders and `../tmp/gemini-client-error-*.json` files.
3. Git login: Gemini CLI turns off git credential helpers for the commands it runs, so git can't log in over HTTPS: pushing fails, and so does fetching a private repo ("could not read Username").
   - An SSH remote usually works when your key is loaded in `ssh-agent`. Gemini ignores `core.sshCommand` and can't ask for a key passphrase.
   - GitHub over HTTPS: start Gemini with your `gh` login turned back on for git. Copy the command exactly; the quotes stop your shell from changing the `!`:

     ```
     GIT_CONFIG_PARAMETERS=\''credential.https://github.com.helper=!gh auth git-credential'\' \
       TMPDIR="$(cd .. && pwd)/tmp" gemini --include-directories ..
     ```

     This lets the git commands the agent runs in this session use your `gh` GitHub login. It needs `gh` installed and logged in (`gh auth login`). Don't combine it with `--yolo` or auto-approve, and don't answer "Allow for this session" or "Allow for all future sessions" for `git` or `gh` commands: a later `git credential fill` or `gh auth token` could then run without asking and put your GitHub token into the chat.
   - Azure DevOps or other git hosts over HTTPS: deploys from Gemini CLI are not supported yet. Use an SSH remote.
4. If `security.environmentVariableRedaction.enabled` is on in your Gemini settings (for example, set by your admin), Gemini CLI 0.68 removes `SALTO_API_TOKEN`, `SSH_AUTH_SOCK` and `GH_TOKEN` from the commands it runs, even when they are listed in `security.environmentVariableRedaction.allowed`. `salto-cli` then can't log in, and SSH pushes can't reach `ssh-agent`. So Salto doesn't work from Gemini CLI with redaction on; ask your admin to turn it off. Gemini also turns this redaction on by itself when `GITHUB_SHA` is set or `SURFACE=Github` (for example in GitHub Actions).
5. Model and approvals: for deploys, use the default model (`auto`) or a Pro model (Pro needs a paid API key; free-tier keys get 429 errors), not Flash-Lite. In our tests Flash-Lite sometimes ignored the skill's stop rules. Don't use `--yolo` or `--approval-mode auto_edit`, and treat starting without the folders above only as a fallback.

Then use it like in Claude Code: `/salto "<request>"` with the skill-only install, or `/salto-cli-skills:salto "<request>"` with the extension (Gemini adds the extension name to the command). You can also ask in plain words (for example, "use salto to list my Zendesk triggers"). Gemini asks you to approve the skill and the commands it runs.

## Required environment variables

For all SaaS-touching skills:

```bash
export SALTO_API_TOKEN=<your-token>     # generate in the Salto UI: Settings → API Tokens
```

Add this to `~/.zshrc` (or your shell's rc) so it's set before Claude Code, Copilot CLI or Gemini CLI starts.

## Quick start

From inside a Salto workspace directory:

```
/salto "add a Zendesk trigger named welcome_message that tags new tickets with 'welcome'"
```

Or, from anywhere with `--workspace` (Claude Code and Copilot; in Gemini CLI, start inside the workspace, see [Start Gemini CLI for Salto](#start-gemini-cli-for-salto)):

```
/salto "rename the Okta group admins to platform-admins" --workspace ~/path/to/your/salto-workspace
```

To inspect without changing anything (routed to explore internally):

```
/salto "what Zendesk triggers exist in my production env?"
```

## Updates

Each install section above says how to update. You get a new version only when we change the plugin's `version`. A running session keeps the skill it loaded at start, so restart the agent after an update.

If the skills detect a `salto-cli` version older than the minimum they require, they'll refuse to run and tell you which version to upgrade to.

## For maintainers

- `skills/salto/` is the only copy of the skill. Claude Code, Copilot CLI and Gemini CLI all use it as it is, with no build step. The repo root is the plugin (`.claude-plugin/plugin.json`, which Copilot reads too), the Gemini extension (`gemini-extension.json`) and the marketplace (`.claude-plugin/marketplace.json` for Claude Code, `.github/plugin/marketplace.json` for Copilot).
- In the skill files, write paths to bundled files as `<SKILL_DIR>/...` (SKILL.md, Step 1 explains it). Don't use agent-specific tokens such as `${CLAUDE_PLUGIN_ROOT}`. Put Gemini-only guidance in `skills/salto/references/gemini-cli.md`.
- To release, change the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `gemini-extension.json` and `skills/salto/VERSION`, then run `./scripts/check.sh`. CI runs the same check, and on merge to `main` it publishes the zips to S3.

## Reporting issues

Open an issue at https://github.com/salto-io/salto-agent-plugin/issues, or contact Salto support.

## License

Proprietary — see [LICENSE](./LICENSE).
