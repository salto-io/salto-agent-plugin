---
name: salto
description: Single entry point for all Salto workflows. Type a natural-language request and the skill routes it internally — deploy (make changes), promote (copy an already-deployed deployment to another environment), explore (query/inspect), or migrate (CPQ→RLM rebuild) — and loads adapter-specific knowledge as needed. Use this for any task against a Salto NACL workspace.
---

# Salto

**Gemini CLI only (other agents, such as Claude Code, GitHub Copilot CLI and Codex CLI: skip this paragraph and that file):** you are Gemini CLI if this skill was loaded by `activate_skill` and its result said "Resources loaded from `<path>`" or listed `<available_resources>`. Then, before anything else, read `<path>/references/gemini-cli.md` by its full path and follow it.

**Codex CLI only (other agents, such as Claude Code, GitHub Copilot CLI and Gemini CLI: skip this paragraph and that file):** you are Codex CLI if this skill came to you in a `<skill>` block with `<name>` and `<path>` tags, or from a skills list with a "Skill roots" table. Then, before anything else, read `<SKILL_DIR>/references/codex-cli.md` by its full path and follow it (`<SKILL_DIR>` is the folder of this SKILL.md; see Step 1).

> [!NOTE]
>
> Usage: /salto "<natural language request>" [--workspace <path>] [--deployment-id <id> | --branch-name <name>]

The single Salto entry point. This skill is a thin router. Based on your request it loads the right internal workflow (`<SKILL_DIR>/references/salto-deploy.md` or `<SKILL_DIR>/references/salto-explore.md`) plus any adapter-specific knowledge (`<SKILL_DIR>/adapters/<adapter>/`) bundled with this skill (`<SKILL_DIR>` is this skill's folder; see Step 1), then executes those instructions with your original `$ARGUMENTS`.

> [!IMPORTANT]
> **Never use the Salesforce CLI (`sf` / `sfdx`).** This applies to every route below (DEPLOY, PROMOTE, EXPLORE, MIGRATE).
>
> - Never run `sf` or `sfdx`, not even read-only commands: no `sf data query`, `sf sobject describe`, `sf org ...`, `sf apex ...`, `sf project deploy/retrieve`, `sfdx force:...`. This holds even when the user says their `sf` CLI is logged in.
> - Don't call the org directly in any other way either. Use the commands and MCP tools the loaded workflow names (for example `salto-cli`, `salto`, `git` / `gh` / `az`) and NACL edits.
> - Why: `sf` goes straight to the org. It skips Salto's preview, conflict check, deployment record and audit trail, and it can change the org outside the PR and deployment flow.
> - If Salto can't do the task (the data isn't in the workspace, running Apex tests on demand outside a deploy, the deploy flow can't run here, ...), stop and tell the user that Salto can't do it and why. Don't fall back to `sf`, and don't offer to run it.

---

## Step 1: Locate skill files

This skill's workflow and adapter files live in this skill's folder: the folder that holds this SKILL.md. Your agent shows that folder's full path when it loads the skill (for example "Base directory for this skill: ..." in Claude Code and GitHub Copilot CLI, the skill's folder under `<available_resources>` in Gemini CLI, or the full path of this SKILL.md in Codex CLI). In this skill's files, `<SKILL_DIR>` means that full path. Read every bundled file by its full path under `<SKILL_DIR>`. A bare relative path such as `references/salto-deploy.md` resolves against the user's project, not this folder.

- Reference workflows: `<SKILL_DIR>/references/salto-deploy.md`, `<SKILL_DIR>/references/salto-explore.md`
- Adapter knowledge lives in a **per-adapter directory**: `<SKILL_DIR>/adapters/<adapter>/<adapter>.md` (e.g. `<SKILL_DIR>/adapters/zendesk/zendesk.md`, `<SKILL_DIR>/adapters/netsuite/netsuite.md`, `<SKILL_DIR>/adapters/salesforce/salesforce.md`).

No discovery needed.

### Salesforce sub-adapters (CPQ / RLM-RCA) and the migration workflow

The `salesforce` adapter directory holds extra files beyond `salesforce.md`:

- `<SKILL_DIR>/adapters/salesforce/cpq.md` — CPQ (SBQQ/sbaa) record knowledge.
- `<SKILL_DIR>/adapters/salesforce/rlm.md` — RLM record knowledge.
- `<SKILL_DIR>/adapters/salesforce/cpq-to-rlm-migration.md` — the CPQ→RLM migration workflow (loaded by the MIGRATE route, below).

> [!IMPORTANT]
> **RLM is now called RCA (Revenue Cloud Advanced).** Salesforce renamed the product. In **our code** (and therefore in the NACL object names, the adapter config, and the `rlm.md` filename) it is still **RLM** — but when talking to users, "RLM", "RCA", and "Revenue Cloud Advanced" all mean the same thing. Treat user mentions of RCA / Revenue Cloud Advanced as RLM.

CPQ and RLM are **flavors of the `salesforce` adapter**, distinguished by the workspace's `salesforce` **data** config (`fetch.data.includeObjects` in `salto.config/adapters/salesforce/salesforce.nacl`). Whenever a workflow loads `<SKILL_DIR>/adapters/salesforce/salesforce.md` for a Salesforce workspace, also load the matching sub-adapter file:

- `includeObjects` contains `SBQQ__` or `sbaa__` → additionally load `<SKILL_DIR>/adapters/salesforce/cpq.md` (CPQ).
- `includeObjects` contains RLM objects (e.g. `ProductClassification`, `AttributeDefinition`, `RateCard`, `ProductSellingModel`) → additionally load `<SKILL_DIR>/adapters/salesforce/rlm.md` (RLM/RCA).

---

## Step 2: Classify intent from `$ARGUMENTS`

**MIGRATE** — the user wants to migrate / rebuild a Salesforce **CPQ** configuration into **RLM / Revenue Cloud Advanced (RCA)**. Check this **first** — its specific phrasing outranks the generic DEPLOY verbs ("rebuild", "change", "move").

Keywords that signal MIGRATE: `migrate CPQ`, `CPQ to RLM`, `CPQ to RCA`, `CPQ to Revenue Cloud`, `rebuild CPQ`, `move from CPQ`, `convert CPQ`, or "migrate/rebuild" together with both CPQ and RLM/RCA/Revenue-Cloud tokens.

**PROMOTE** — the user wants to take a deployment that is already **deployed** in one environment and apply the same change to a **different** environment (e.g. sandbox → production), and asks for no new edit. Check this **before** DEPLOY — it names an existing deployment, not a change to make, so it must never be re-done as NACL edits.

Signals: `promote`, or `move` / `copy` / `push` / `deploy`, together with an existing deployment (its id, its name, "my last deployment") and a different target environment (`to production`, `to prod`, `to <env name>`). Count `promote` / `promotion` only when they refer to a deployment or an environment, not to a record (e.g. a NetSuite promotion code).

Not PROMOTE → DEPLOY: the request asks for an edit (even "push this fix to the sandbox deployment"), or it names no target environment and doesn't say promote (e.g. "deploy deployment abc123"). When a target env is named but you can't tell whether the deployment is already deployed, route to PROMOTE: Promote mode checks the status first, and a deployment that is not deployed yet is only previewed, never promoted.

Not PROMOTE → EXPLORE: a question about what a promote would do (e.g. "what would change if I promoted abc123 to prod?"). Answering a question must never create a deployment.

**DEPLOY** — the user wants to create, change, rename, delete, or fix a configuration element, or resume an existing deployment.

Keywords that signal DEPLOY: `add`, `create`, `rename`, `delete`, `remove`, `change`, `update`, `set`, `enable`, `disable`, `fix`, `deploy`.

**EXPLORE** — the user wants to read, list, inspect, or understand current state without making changes.

Keywords that signal EXPLORE: `what`, `show`, `list`, `which`, `how many`, `explain`, `find`, `status`, `history`, `does`, `is there`, `are there`. Single-environment "what's there" questions go here even if they mention "diff" loosely (e.g. "what would change if I deployed now?" — that's a plan preview, not an env compare).

**AMBIGUOUS** — intent cannot be determined.

### Examples

| Input                                                      | Route     |
| ---------------------------------------------------------- | --------- |
| "add Zendesk trigger ai_review_test that tags new tickets" | DEPLOY    |
| "what Zendesk triggers exist in my prod environment?"      | EXPLORE   |
| "rename the Okta group admins to platform-admins"          | DEPLOY    |
| "what would change if I deployed now?"                     | EXPLORE   |
| "fix the changeError on trigger ai_review_test"            | DEPLOY    |
| "list my deployments"                                      | EXPLORE   |
| "promote deployment abc123 to production"                  | PROMOTE   |
| "copy the label-cleanup deployment from sandbox to prod"   | PROMOTE   |
| "push this fix to the sandbox deployment"                  | DEPLOY    |
| "deploy deployment abc123"                                 | DEPLOY    |
| "create a promotion code SUMMER20 in NetSuite"             | DEPLOY    |
| "what would change if I promoted abc123 to prod?"          | EXPLORE   |
| "show me the ai_review_test trigger definition"            | EXPLORE   |
| "delete the old Zendesk macro close_ticket_legacy"         | DEPLOY    |
| "migrate our CPQ config to RLM"                            | MIGRATE   |
| "rebuild the CPQ bundles in Revenue Cloud Advanced"        | MIGRATE   |
| "Zendesk trigger ai_review_test"                           | AMBIGUOUS |

---

## Step 3: Act on classification

**If MIGRATE:**

1. Print: `Routing to cpq-to-rlm-migration workflow...`
2. Read `<SKILL_DIR>/adapters/salesforce/cpq-to-rlm-migration.md` into context.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged. That workflow loads both `<SKILL_DIR>/adapters/salesforce/cpq.md` and `<SKILL_DIR>/adapters/salesforce/rlm.md`, reads the CPQ source read-only, **stops to ask the user about lossy/ambiguous areas it can't decide from the data (a Clarification Gate — mandatory even in auto mode; never fabricate selling models/terms/prices/rule behavior)**, and stops again at a human gate before any real deploy.

**If PROMOTE:**

1. Print: `Routing to salto-deploy workflow (promote mode)...`
2. Read `<SKILL_DIR>/references/salto-deploy.md` into context.
3. Follow its **Promote mode** section with the full original `$ARGUMENTS` unchanged. It creates the new deployment with `salto-cli deployment create from-deployments`; never re-apply the change by editing NACLs.

**If DEPLOY:**

1. Print: `Routing to salto-deploy workflow...`
2. Read `<SKILL_DIR>/references/salto-deploy.md` into context.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged. The reference file uses `<SKILL_DIR>` for paths to adapter knowledge (e.g. `<SKILL_DIR>/adapters/zendesk/zendesk.md`).

**If EXPLORE:**

1. Print: `Routing to salto-explore workflow...`
2. Read `<SKILL_DIR>/references/salto-explore.md` into context.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged.

**If AMBIGUOUS:**
Ask exactly: "Do you want to (1) make a change and deploy it, (2) promote a deployment that is already deployed to another environment, or (3) explore/query the current state without making changes?"

- Answer deploy / change / 1 → DEPLOY path.
- Answer promote / 2 → PROMOTE path.
- Answer explore / query / read / 3 → EXPLORE path.

(A CPQ→RLM migration request is rarely ambiguous; route it to MIGRATE when both CPQ and RLM/RCA are named.)

---

## Usage Examples

```
/salto "add Zendesk trigger ai_review_test that tags new tickets as pending_review"
/salto "what Zendesk triggers exist in my prod environment?"
/salto "show me what would change if I deployed now" --deployment-id abc123
/salto "rename the Okta group admins to platform-admins"
/salto "promote deployment abc123 to production"
/salto "migrate our CPQ config to RLM" --source ~/develop/workspaces/cpq --target ~/develop/workspaces/sf1
```

All flags (`--workspace`, `--deployment-id`, `--branch-name`, etc.) are passed through to the inner workflow unchanged.
