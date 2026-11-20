# salto-cli-skills

Agent skills for Claude Code, GitHub Copilot CLI, Gemini CLI and OpenAI Codex CLI that automate [Salto](https://www.salto.io) NACL workflows: fast credential-free local validation, deploy orchestration, and end-to-end change loops against SaaS-managed Salto environments.

## What this plugin gives you

A single slash command — `/salto "<natural language request>"` — that routes your request to the right workflow: **Explore** or **Deploy**. (In Codex CLI, type `$salto-cli-skills:salto <request>` instead; see [Install in Codex CLI](#install-in-codex-cli).)

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
- **Promote a deployment** — "promote deployment abc123 to production". Creates a Promote deployment in the target environment from what was already deployed (no NACL edits, no PR). You review and apply it in the Salto UI.
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

## Install in Codex CLI

```
codex plugin marketplace add salto-io/salto-agent-plugin
codex plugin add salto-cli-skills@salto-claude-plugin
```

Check it with `codex plugin list`. Codex updates the plugin to the latest commit on `main` by itself when it starts. To update now, run `codex plugin marketplace upgrade salto-claude-plugin`, then restart Codex.

### Start Codex for Salto

Start Codex inside the workspace folder (the root of its git repo, the usual Salto setup):

```
cd ~/path/to/your/salto-workspace
codex
```

If Codex asks whether you trust the folder, choose Yes, but only for your own workspace repo. Trusting a folder also loads its `.codex/` settings, which can change approvals, so first check that the repo has no `.codex/` folder you don't know. Codex then runs commands in its sandbox: they can write only in this folder and the temp folder, they can't use the network, and the `.git` folder stays read-only. When a command needs more, Codex asks you first. Keep these approvals: don't start Codex with `--yolo`, `--dangerously-bypass-approvals-and-sandbox`, `--sandbox danger-full-access` or `--approve-for-me` for Salto, don't set `sandbox_mode = "danger-full-access"` or `approval_policy = "never"` in `~/.codex/config.toml`, keep `approvals_reviewer = "user"` (the default), and don't pick Full Access in `/permissions`. With `--ask-for-approval never` (and in `codex exec`) Codex can't ask you, so deploys stop at the first `salto-cli` command; only questions answered from the workspace files still work.

Then ask: `$salto-cli-skills:salto <request>` (type `$` to pick the skill), or ask in plain words (for example, "use salto to list my Zendesk triggers").

Codex asks you to approve each command that needs the network or writes the `.git` folder, because it runs them outside the sandbox, with full network and disk access. Read each command before you approve it, and approve with "Yes, proceed" (this time only). Never choose "don't ask again". Expect only:

- `salto-cli deployment preflight`, `prepare-worktree`, `validate-local`, `ship`, `preview`, `list`, `show` or `create from-pull-request` (explore requests may ask for some of these too)
- `gh auth status`
- `git add` or `commit` in the `../<workspace>-salto-...` change worktree, and `git push` to `origin`, branch `salto/...`, from the change worktree
- Azure DevOps remotes: `az repos` commands (the `az repos -h` check, and creating or finding the PR)
- `acli jira ...`, the `jira` CLI or `az boards ...` commands that read or comment on your ticket, when your request names a ticket (a key such as SALTO-1234, or `--ticket`)
- CPQ→RLM migration requests only: `salto element list` and `salto deploy --preview`
- at the end of a deploy, `rm -rf` of the skill's temp folder (`.../salto-state-...` in your temp folder)

Decline anything else (for example `gh api`, `gh repo`, `git push --force`, `git pull` in your workspace, or `rm` of any other folder) and tell Codex to stop. If you chose "don't ask again" in an earlier Codex session, check `~/.codex/rules/` for allow rules: Codex runs matching commands without asking. Never approve `npx` or `npm` commands that install or run `salto-cli`: Salto doesn't publish it on npm, so anyone could publish a package with that name. If `salto-cli` is missing, the skill should stop and ask you.

For deploy requests, Codex also asks you to approve the NACL edits. `salto-cli` puts the change worktree next to your workspace (`../<workspace>-salto-...`), outside the folder Codex may write. Approve edits only in that worktree, and never files written with `python`, `cp` or `echo`. Codex doesn't ask before it edits files in your workspace folder itself. The skill must not edit there; if you see it do that, stop it (Esc).

Codex passes your environment variables (including `SALTO_API_TOKEN`) to the commands it runs. If your Codex config filters them (`shell_environment_policy`), keep `SALTO_API_TOKEN`.

## Required environment variables

For all SaaS-touching skills:

```bash
export SALTO_API_TOKEN=<your-token>     # generate in the Salto UI: Settings → API Tokens
```

Add this to `~/.zshrc` (or your shell's rc) so it's set before Claude Code, Copilot CLI, Gemini CLI or Codex CLI starts.

## Quick start

From inside a Salto workspace directory:

```
/salto "add a Zendesk trigger named welcome_message that tags new tickets with 'welcome'"
```

In Codex CLI, type `$salto-cli-skills:salto` instead of `/salto` (for example `$salto-cli-skills:salto add a Zendesk trigger ...`).

Or, from anywhere with `--workspace` (Claude Code and Copilot; in Gemini CLI and Codex CLI, start inside the workspace, see [Start Gemini CLI for Salto](#start-gemini-cli-for-salto) and [Start Codex for Salto](#start-codex-for-salto)):

```
/salto "rename the Okta group admins to platform-admins" --workspace ~/path/to/your/salto-workspace
```

To inspect without changing anything (routed to explore internally):

```
/salto "what Zendesk triggers exist in my production env?"
```

## Updates

Each install section above says how to update. Claude Code and Copilot CLI get a new copy only when we change the plugin's `version`. A Gemini extension installed from GitHub updates to every new commit on `main` (Gemini compares commits, not versions). The Gemini skill-only install changes only when you run the install command again. Codex CLI updates to every new commit on `main` when it starts, or when you run `codex plugin marketplace upgrade salto-claude-plugin`. A running session keeps the skill it loaded at start, so restart the agent after an update.

If the skills detect a `salto-cli` version older than the minimum they require, they'll refuse to run and tell you which version to upgrade to.

## For maintainers

- `skills/salto/` is the only copy of the skill. Claude Code, Copilot CLI, Gemini CLI and Codex CLI all use it as it is, with no build step. The repo root is the plugin (`.claude-plugin/plugin.json`, which Copilot and Codex read too), the Gemini extension (`gemini-extension.json`) and the marketplace (`.claude-plugin/marketplace.json` for Claude Code and Codex, `.github/plugin/marketplace.json` for Copilot). Don't add a Codex manifest (`.codex-plugin/plugin.json`, `.agents/plugins/marketplace.json` or a root `plugin.json`): Codex can read it instead (`scripts/check.sh` fails on all three).
- In the skill files, write paths to bundled files as `<SKILL_DIR>/...` (SKILL.md, Step 1 explains it). Don't use agent-specific tokens such as `${CLAUDE_PLUGIN_ROOT}`. Put Gemini-only guidance in `skills/salto/references/gemini-cli.md` and Codex-only guidance in `skills/salto/references/codex-cli.md`.
- To release, change the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `gemini-extension.json` and `skills/salto/VERSION`, then run `./scripts/check.sh`. CI runs the same check, and on merge to `main` it publishes the zips to S3.

## Reporting issues

Open an issue at https://github.com/salto-io/salto-agent-plugin/issues, or contact Salto support.

## License

Proprietary — see [LICENSE](./LICENSE).
