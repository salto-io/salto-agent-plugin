---
name: salto
description: Single entry point for all Salto workflows. Type a natural-language request and the skill routes it internally — deploy (make changes), explore (query/inspect), or migrate (CPQ→RLM rebuild) — and loads adapter-specific knowledge as needed. Use this for any task against a Salto NACL workspace.
---

# Salto

> [!NOTE]
>
> Usage: /salto "<natural language request>" [--workspace <path>] [--deployment-id <id> | --branch-name <name>]

The single Salto entry point. This skill is a thin router. Based on your request it loads the right internal workflow (`references/salto-deploy.md` or `references/salto-explore.md`) plus any adapter-specific knowledge (`adapters/<adapter>/`) bundled with this skill, then executes those instructions with your original `$ARGUMENTS`.

---

## Step 1: Locate skill files

This skill's workflow and adapter files are bundled alongside it. Load any sibling file by its path under `{{SKILL_ROOT}}`:

- Reference workflows: `{{SKILL_ROOT}}/references/salto-deploy.md`, `{{SKILL_ROOT}}/references/salto-explore.md`
- Adapter knowledge lives in a **per-adapter directory**: `{{SKILL_ROOT}}/adapters/<adapter>/<adapter>.md` (e.g. `adapters/zendesk/zendesk.md`, `adapters/netsuite/netsuite.md`, `adapters/salesforce/salesforce.md`).

No discovery needed.

### Salesforce sub-adapters (CPQ / RLM-RCA) and the migration workflow

The `salesforce` adapter directory holds extra files beyond `salesforce.md`:

- `{{SKILL_ROOT}}/adapters/salesforce/cpq.md` — CPQ (SBQQ/sbaa) record knowledge.
- `{{SKILL_ROOT}}/adapters/salesforce/rlm.md` — RLM record knowledge.
- `{{SKILL_ROOT}}/adapters/salesforce/cpq-to-rlm-migration.md` — the CPQ→RLM migration workflow (loaded by the MIGRATE route, below).

> [!IMPORTANT]
> **RLM is now called RCA (Revenue Cloud Advanced).** Salesforce renamed the product. In **our code** (and therefore in the NACL object names, the adapter config, and the `rlm.md` filename) it is still **RLM** — but when talking to users, "RLM", "RCA", and "Revenue Cloud Advanced" all mean the same thing. Treat user mentions of RCA / Revenue Cloud Advanced as RLM.

CPQ and RLM are **flavors of the `salesforce` adapter**, distinguished by the workspace's `salesforce` **data** config (`fetch.data.includeObjects` in `salto.config/adapters/salesforce/salesforce.nacl`). Whenever a workflow loads `adapters/salesforce/salesforce.md` for a Salesforce workspace, also load the matching sub-adapter file:

- `includeObjects` contains `SBQQ__` or `sbaa__` → additionally load `{{SKILL_ROOT}}/adapters/salesforce/cpq.md` (CPQ).
- `includeObjects` contains RLM objects (e.g. `ProductClassification`, `AttributeDefinition`, `RateCard`, `ProductSellingModel`) → additionally load `{{SKILL_ROOT}}/adapters/salesforce/rlm.md` (RLM/RCA).

---

## Step 2: Classify intent from `$ARGUMENTS`

**MIGRATE** — the user wants to migrate / rebuild a Salesforce **CPQ** configuration into **RLM / Revenue Cloud Advanced (RCA)**. Check this **first** — its specific phrasing outranks the generic DEPLOY verbs ("rebuild", "change", "move").

Keywords that signal MIGRATE: `migrate CPQ`, `CPQ to RLM`, `CPQ to RCA`, `CPQ to Revenue Cloud`, `rebuild CPQ`, `move from CPQ`, `convert CPQ`, or "migrate/rebuild" together with both CPQ and RLM/RCA/Revenue-Cloud tokens.

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
| "show me the ai_review_test trigger definition"            | EXPLORE   |
| "delete the old Zendesk macro close_ticket_legacy"         | DEPLOY    |
| "migrate our CPQ config to RLM"                            | MIGRATE   |
| "rebuild the CPQ bundles in Revenue Cloud Advanced"        | MIGRATE   |
| "Zendesk trigger ai_review_test"                           | AMBIGUOUS |

---

## Step 3: Act on classification

**If MIGRATE:**

1. Print: `Routing to cpq-to-rlm-migration workflow...`
2. Read `{{SKILL_ROOT}}/adapters/salesforce/cpq-to-rlm-migration.md` into context.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged. That workflow loads both `adapters/salesforce/cpq.md` and `adapters/salesforce/rlm.md`, reads the CPQ source read-only, **stops to ask the user about lossy/ambiguous areas it can't decide from the data (a Clarification Gate — mandatory even in auto mode; never fabricate selling models/terms/prices/rule behavior)**, and stops again at a human gate before any real deploy.

**If DEPLOY:**

1. Print: `Routing to salto-deploy workflow...`
2. Read `{{SKILL_ROOT}}/references/salto-deploy.md` into context.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged. The reference file uses `{{SKILL_ROOT}}` for paths to adapter knowledge (e.g. `{{SKILL_ROOT}}/adapters/zendesk/zendesk.md`).

**If EXPLORE:**

1. Print: `Routing to salto-explore workflow...`
2. Read `{{SKILL_ROOT}}/references/salto-explore.md` into context.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged.

**If AMBIGUOUS:**
Ask exactly: "Do you want to (1) make a change and deploy it, or (2) explore/query the current state without making changes?"

- Answer deploy / change / 1 → DEPLOY path.
- Answer explore / query / read / 2 → EXPLORE path.

(A CPQ→RLM migration request is rarely ambiguous; route it to MIGRATE when both CPQ and RLM/RCA are named.)

---

## Usage Examples

```
/salto "add Zendesk trigger ai_review_test that tags new tickets as pending_review"
/salto "what Zendesk triggers exist in my prod environment?"
/salto "show me what would change if I deployed now" --deployment-id abc123
/salto "rename the Okta group admins to platform-admins"
/salto "migrate our CPQ config to RLM" --source ~/develop/workspaces/cpq --target ~/develop/workspaces/sf1
```

All flags (`--workspace`, `--deployment-id`, `--branch-name`, etc.) are passed through to the inner workflow unchanged.
