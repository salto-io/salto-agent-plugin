# salto-cli-skills

Claude Code skills for automating [Salto](https://www.salto.io) NACL workflows: fast credential-free local validation, deploy orchestration, and end-to-end change loops against SaaS-managed Salto environments.

## What this plugin gives you

A single slash command:

- `/salto "<natural language request>"` — single entry point. Internally routes between workflows based on what you ask:
  - **Deploy** (add / rename / delete / change / fix): orchestrates a full NACL change end-to-end — edit → local-validate (with security checks) → push → SaaS preview → PR + deployment.
  - **Explore** (what / show / list): read-only inspection of a workspace. Lists elements, browses deployment history, previews what would change. No writes.
  - **Migrate** (CPQ → RLM/RCA): semantic rebuild of a Salesforce CPQ configuration into RLM (Revenue Cloud Advanced), read-only on the source, with human review gates.

Adapter-specific knowledge is loaded automatically based on what your workspace uses, from a per-adapter directory (`adapters/<adapter>/`). The Salesforce directory also carries CPQ, RLM, and the CPQ→RLM migration knowledge. The plugin ships those workflow definitions and adapter knowledge as reference content; only `/salto` shows up in your command list.

## Prerequisites

- **`salto-cli` on `$PATH`** — the skills call `salto-cli` for all SaaS-side work. Until a public installer is published, contact your Salto representative for the binary.
- **`git`** — required.
- **`gh` CLI authenticated** *(optional)* — if installed and authenticated (`gh auth login`), the deploy workflow opens PRs for you. Otherwise it just pushes the branch and prints a GitHub compare URL for you to open manually.

## Install in Claude Code

```
/plugin marketplace add salto-io/salto-agent-plugin
/plugin install salto-cli-skills@salto-claude-plugin
```

The plugin is hosted in a private GitHub repo, so Claude Code needs your GitHub credentials to fetch it. Either:
- Be authenticated via `gh auth login` (Claude Code picks this up automatically), or
- Export `GITHUB_TOKEN` with a PAT that has `repo:read` on `salto-io/salto-agent-plugin`.

## Required environment variables

For all SaaS-touching skills:

```bash
export SALTO_API_TOKEN=<your-token>     # generate in the Salto UI: Settings → API Tokens
```

Add this to `~/.zshrc` (or your shell's rc) so it's set before Claude Code starts.

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
