---
name: salto
description: Smart router for Salto skills. Type a natural language request — the skill classifies intent and delegates to salto-deploy (make changes) or salto-explore (query/inspect without changes). Use this when you're unsure which sub-skill to call.
---

# Salto

> [!NOTE]
>
> Usage: /salto "<natural language request>" [--workspace <path>] [--deployment-id <id>]

A thin router that classifies your request and delegates to the right Salto skill:

- **Deploy intent** (add, rename, delete, fix, change): delegates to `salto-deploy`, which runs the full edit → validate → push → SaaS preview loop.
- **Explore intent** (what, list, show, compare, history): delegates to `salto-explore`, which reads NACL files and queries CLI without making any changes.
- **Ambiguous**: asks one clarifying question before routing.

You can also invoke sub-skills directly: `/salto-deploy` and `/salto-explore`.

## Usage Examples

```
/salto "add Zendesk trigger ai_review_test that tags new tickets as pending_review"
/salto "what Zendesk triggers exist in my prod environment?"
/salto "show me what would change if I deployed now" --deployment-id abc123
/salto "compare prod and staging Zendesk triggers"
/salto "rename the Okta group admins to platform-admins"
```
