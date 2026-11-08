# Salto Explore (reference, loaded by the `/salto` router)

This is reference content. It is not registered as a slash command. The `/salto` router reads it when intent is classified as EXPLORE, then follows the instructions below with the user's original `$ARGUMENTS`.

> [!NOTE]
>
> Invoked via: /salto "<question>" [--workspace <path>] [--deployment-id <id>]

Answer questions about a Salto workspace without making any changes. Reads NACL files directly and uses `salto-cli deployment list/show/validate-local` for live data.

## Capabilities

- **List elements**: "what triggers exist?", "show me all macros in prod"
- **Inspect a specific element**: "show me the ai_review_test trigger"
- **Change preview**: "what would change if I deployed now?"
- **Deployment history**: "list my recent deployments", "show deployment abc123"
- **Workspace info**: "what adapters are configured?", "what environments do I have?"

## Rules

- Answer only from the NACL files and `salto-cli`.
- Never run `sf` or `sfdx` (the Salesforce CLI) to query or inspect the org: no `sf data query`, `sf sobject describe`, `sf org ...`, `sf apex ...`. This holds even when the user says their `sf` CLI is logged in.
- If the workspace doesn't hold the answer (for example, records of an object that is not in the Salesforce `fetch.data.includeObjects`), say so and stop. You may explain how to bring the data into Salto (add the object to the fetch config through the DEPLOY route, then fetch in the Salto app), but don't make that change here, and don't offer to run `sf` instead.

## Requirements

- A valid Salto workspace (directory with `salto.config/workspace.nacl`)
- `SALTO_API_TOKEN` — required for deployment queries and `validate-local` with state fetch; **not required** for pure NACL browsing

## Usage Examples

```
/salto-explore "what Zendesk triggers exist in prod?"
/salto-explore "show me the ai_review_test trigger" --workspace ~/workspaces/prod
/salto-explore "list deployments"
/salto-explore "what would change if I deployed now?" --deployment-id abc123
```
