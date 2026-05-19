# salto-cli-skills

Claude Code skills for automating [Salto](https://www.salto.io) NACL workflows: fast credential-free local validation, deploy orchestration, and end-to-end change loops against SaaS-managed Salto environments.

## What this plugin gives you

Three slash commands once installed:

- `/salto` — natural-language router. Type a request and it delegates to the right sub-skill.
- `/salto-deploy` — orchestrates a full NACL change end-to-end: edit → local-validate (with security checks) → push → SaaS preview → PR + deployment.
- `/salto-explore` — read-only inspection of a workspace: list elements, browse deployment history, preview what would change, compare environments. No writes.

Adapter-specific knowledge (currently Zendesk) is loaded automatically based on what your workspace uses.

## Prerequisites

- **`salto-cli` on `$PATH`** — the skills call `salto-cli` for all SaaS-side work. Until a public installer is published, contact your Salto representative for the binary.
- **`gh` CLI authenticated** — used by `/salto-deploy` to open PRs. Run `gh auth login` once.
- **`git`** — standard.

## Install in Claude Code

```
/plugin marketplace add salto-io/salto-claude-plugin
/plugin install salto-cli-skills@salto-claude-plugin
```

The plugin is hosted in a private GitHub repo, so Claude Code needs your GitHub credentials to fetch it. Either:
- Be authenticated via `gh auth login` (Claude Code picks this up automatically), or
- Export `GITHUB_TOKEN` with a PAT that has `repo:read` on `salto-io/salto-claude-plugin`.

## Required environment variables

For all SaaS-touching skills:

```bash
export SALTO_API_TOKEN=<your-token>     # generate in the Salto UI: Settings → API Tokens
```

For non-production targets (staging, local stack):

```bash
export GRAPHQL_URL=<env-specific>       # default: https://graphql.salto.io/graphql
export SALTO_URL=<env-specific>         # default: https://app.salto.io
export AUTH0_DOMAIN=<env-specific>      # default: auth.salto.io
export AUTH0_CLIENT_ID=<env-specific>   # default: prod CLI client
```

Add these to `~/.zshrc` (or your shell's rc) so they're set before Claude Code starts.

## Quick start

From inside a Salto workspace directory:

```
/salto-deploy "add a Zendesk trigger named welcome_message that tags new tickets with 'welcome'"
```

Or, from anywhere with `--workspace`:

```
/salto-deploy "rename the Okta group admins to platform-admins" --workspace ~/path/to/your/salto-workspace
```

To inspect without changing anything:

```
/salto-explore "what Zendesk triggers exist in my production env?"
```

## Updates

Claude Code re-fetches `marketplace.json` from this repo on every session start. When we publish a new version (bump `version` in `plugin.json` + tag), your **next** Claude Code session automatically uses the new skill — no `/plugin reinstall` needed.

A running session keeps the version it loaded at startup. To force-pick-up an update mid-day, restart Claude Code.

If the skills detect a `salto-cli` version older than the minimum they require, they'll refuse to run and tell you which version to upgrade to.

## Reporting issues

Open an issue at https://github.com/salto-io/salto-claude-plugin/issues, or contact Salto support.

## License

Proprietary — see [LICENSE](./LICENSE).
