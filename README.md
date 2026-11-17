# salto-cli-skills

Claude Code skills for automating [Salto](https://www.salto.io) NACL workflows: fast credential-free local validation, deploy orchestration, and end-to-end change loops against SaaS-managed Salto environments.

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

## Install in Gemini CLI

```
gemini skills install https://github.com/salto-io/salto-agent-plugin --path dist/gemini/skills
```

This installs the `salto` skill for your user (all projects) in `~/.gemini/skills/salto`. Check it with `gemini skills list`. To update, run the same install command again. Gemini CLI does not update skills automatically.

### Start Gemini CLI for Salto

Gemini CLI limits the agent more than Claude Code does. For deploy requests, `salto-cli` creates the change worktree next to your workspace folder and keeps temp files in `TMPDIR`. Gemini edits files only in folders you allow, and it reads allowed folders without asking. So:

1. Keep each Salto workspace (its git folder) in its own parent folder, for example `~/salto/<workspace>`. Never put it directly in your home folder.
2. Start Gemini inside the workspace (don't use `--workspace`), and allow only that parent folder:

   ```
   mkdir -p "$HOME/salto/tmp"
   cd "$HOME/salto/<workspace>"
   TMPDIR="$HOME/salto/tmp" gemini --include-directories ..
   ```

   Gemini asks whether to trust `..`; choose Yes. If you start Gemini another way, the skill asks you to add the folder it needs with `/directory add <path>`.
3. Pushing: Gemini CLI turns off git credential helpers for the commands it runs, so `git push` over HTTPS fails ("could not read Username").
   - An SSH remote usually works when your key is loaded in `ssh-agent`. Gemini ignores `core.sshCommand` and can't ask for a key passphrase.
   - GitHub over HTTPS: start Gemini with your `gh` login turned back on for git:

     ```
     GIT_CONFIG_PARAMETERS="'credential.https://github.com.helper=!gh auth git-credential'" \
       TMPDIR="$HOME/salto/tmp" gemini --include-directories ..
     ```

     This lets the git commands the agent runs in this session use your `gh` GitHub login. It needs `gh` installed and logged in (`gh auth login`). Don't combine it with `--yolo` or auto-approve.
   - Azure DevOps or other git hosts over HTTPS: deploys from Gemini CLI are not supported yet. Use an SSH remote.
4. If your admin turned on `security.environmentVariableRedaction`, add `SALTO_API_TOKEN` (and `SSH_AUTH_SOCK` for SSH) to `security.environmentVariableRedaction.allowed` in your Gemini settings.

Then use it the same way: `/salto "<request>"`, or ask in plain words (for example, "use salto to list my Zendesk triggers"). Gemini asks you to approve the skill and the commands it runs.

## Required environment variables

For all SaaS-touching skills:

```bash
export SALTO_API_TOKEN=<your-token>     # generate in the Salto UI: Settings → API Tokens
```

Add this to `~/.zshrc` (or your shell's rc) so it's set before Claude Code or Gemini CLI starts.

## Quick start

From inside a Salto workspace directory:

```
/salto "add a Zendesk trigger named welcome_message that tags new tickets with 'welcome'"
```

Or, from anywhere with `--workspace`:

```
/salto "rename the Okta group admins to platform-admins" --workspace ~/path/to/your/salto-workspace
```

To inspect without changing anything (routed to explore internally):

```
/salto "what Zendesk triggers exist in my production env?"
```

## Updates

Claude Code re-fetches `marketplace.json` from this repo on every session start. When we publish a new version (bump `version` in `plugin.json` + tag), your **next** Claude Code session automatically uses the new skill — no `/plugin reinstall` needed.

A running session keeps the version it loaded at startup. To force-pick-up an update mid-day, restart Claude Code.

If the skills detect a `salto-cli` version older than the minimum they require, they'll refuse to run and tell you which version to upgrade to.

## Reporting issues

Open an issue at https://github.com/salto-io/salto-agent-plugin/issues, or contact Salto support.

## License

Proprietary — see [LICENSE](./LICENSE).
