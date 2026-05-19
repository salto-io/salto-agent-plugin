---
name: salto-explore
description: Read-only exploration of Salto workspaces and environments. List and inspect NACL elements, browse deployment history, preview change plans, and compare environments — without making any changes. Automatically loads adapter-specific NACL knowledge (Zendesk, Salesforce, Okta, etc.) based on what is configured in the workspace.
---

# Salto Explore

> [!NOTE]
>
> Usage: /salto-explore "<question>" [--workspace <path>] [--deployment-id <id>]

Answer questions about a Salto workspace without making any changes. Reads NACL files directly and uses `salto-cli deployment list/show/validate-local` for live data.

## Capabilities

- **List elements**: "what triggers exist?", "show me all macros in prod"
- **Inspect a specific element**: "show me the ai_review_test trigger"
- **Change preview**: "what would change if I deployed now?"
- **Deployment history**: "list my recent deployments", "show deployment abc123"
- **Environment compare**: "compare prod and staging for Zendesk triggers"
- **Workspace info**: "what adapters are configured?", "what environments do I have?"

## Requirements

- A valid Salto workspace (directory with `salto.config/workspace.nacl`)
- `SALTO_API_TOKEN` — required for deployment queries and `validate-local` with state fetch; **not required** for pure NACL browsing

## Usage Examples

```
/salto-explore "what Zendesk triggers exist in prod?"
/salto-explore "show me the ai_review_test trigger" --workspace ~/workspaces/prod
/salto-explore "list deployments"
/salto-explore "what would change if I deployed now?" --deployment-id abc123
/salto-explore "compare prod and staging"
```
