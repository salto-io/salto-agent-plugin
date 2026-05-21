---
name: salto
description: Single entry point for all Salto workflows. Type a natural-language request and the skill routes it internally — deploy (make changes) or explore (query/inspect) — and loads adapter-specific knowledge as needed. Use this for any task against a Salto NACL workspace.
---

# Salto

> [!NOTE]
>
> Usage: /salto "<natural language request>" [--workspace <path>] [--deployment-id <id> | --branch-name <name>]

The only Salto command exposed in Claude Code. This skill is a thin router. Based on your request it loads the right internal workflow (`references/salto-deploy.md` or `references/salto-explore.md`) plus any adapter-specific knowledge (`adapters/<adapter>.md`) from this plugin, then executes those instructions with your original `$ARGUMENTS`.

---

## Step 1: Plugin root

Claude Code automatically sets `${CLAUDE_PLUGIN_ROOT}` to this plugin's absolute path. Use it directly for any sibling file:

- Reference workflows: `${CLAUDE_PLUGIN_ROOT}/references/salto-deploy.md`, `${CLAUDE_PLUGIN_ROOT}/references/salto-explore.md`
- Adapter knowledge: `${CLAUDE_PLUGIN_ROOT}/adapters/<adapter>.md`

No discovery needed.

---

## Step 2: Classify intent from `$ARGUMENTS`

**DEPLOY** — the user wants to create, change, rename, delete, or fix a configuration element, or resume an existing deployment.

Keywords that signal DEPLOY: `add`, `create`, `rename`, `delete`, `remove`, `change`, `update`, `set`, `enable`, `disable`, `fix`, `deploy`.

**EXPLORE** — the user wants to read, list, compare, inspect, or understand current state without making changes.

Keywords that signal EXPLORE: `what`, `show`, `list`, `which`, `how many`, `compare`, `diff`, `explain`, `find`, `status`, `history`, `does`, `is there`, `are there`.

**AMBIGUOUS** — intent cannot be determined.

### Examples

| Input | Route |
|-------|-------|
| "add Zendesk trigger ai_review_test that tags new tickets" | DEPLOY |
| "what Zendesk triggers exist in my prod environment?" | EXPLORE |
| "rename the Okta group admins to platform-admins" | DEPLOY |
| "what would change if I deployed now?" | EXPLORE |
| "fix the changeError on trigger ai_review_test" | DEPLOY |
| "list my deployments" | EXPLORE |
| "compare prod and staging" | EXPLORE |
| "show me the ai_review_test trigger definition" | EXPLORE |
| "delete the old Zendesk macro close_ticket_legacy" | DEPLOY |
| "Zendesk trigger ai_review_test" | AMBIGUOUS |

---

## Step 3: Act on classification

**If DEPLOY:**
1. Print: `Routing to salto-deploy workflow...`
2. Read `${CLAUDE_PLUGIN_ROOT}/references/salto-deploy.md` using the Read tool.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged. The reference file uses `${CLAUDE_PLUGIN_ROOT}` for paths to adapter knowledge (e.g. `${CLAUDE_PLUGIN_ROOT}/adapters/zendesk.md`).

**If EXPLORE:**
1. Print: `Routing to salto-explore workflow...`
2. Read `${CLAUDE_PLUGIN_ROOT}/references/salto-explore.md` using the Read tool.
3. Execute the instructions with the full original `$ARGUMENTS` unchanged.

**If AMBIGUOUS:**
Ask exactly: "Do you want to (1) make a change and deploy it, or (2) explore/query the current state without making changes?"
- Answer deploy / change / 1 → DEPLOY path.
- Answer explore / query / read / 2 → EXPLORE path.

---

## Usage Examples

```
/salto "add Zendesk trigger ai_review_test that tags new tickets as pending_review"
/salto "what Zendesk triggers exist in my prod environment?"
/salto "show me what would change if I deployed now" --deployment-id abc123
/salto "compare prod and staging Zendesk triggers"
/salto "rename the Okta group admins to platform-admins"
```

All flags (`--workspace`, `--deployment-id`, `--branch-name`, etc.) are passed through to the inner workflow unchanged.
