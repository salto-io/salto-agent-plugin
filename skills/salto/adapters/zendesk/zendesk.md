# Zendesk Adapter — NACL Reference

This file is loaded automatically by salto-deploy and salto-explore when the workspace contains the `zendesk` adapter. It provides NACL element types, ID patterns, structural examples, and pitfalls specific to Zendesk.

---

## Element Types and NACL ID Pattern

Every Zendesk element uses the pattern:

```
zendesk.<type_name>.instance.<element_name>
```

`<element_name>` is derived from the element's display name: lowercase, spaces replaced by underscores, special characters stripped.

### Core element types

| NACL type name            | Zendesk concept                                            |
| ------------------------- | ---------------------------------------------------------- |
| `trigger`                 | Trigger                                                    |
| `trigger_category`        | Trigger category                                           |
| `trigger_order`           | Trigger rendering order (separate from the trigger itself) |
| `automation`              | Automation                                                 |
| `automation_order`        | Automation rendering order                                 |
| `view`                    | View                                                       |
| `view_order`              | View rendering order                                       |
| `macro`                   | Macro                                                      |
| `sla_policy`              | SLA Policy                                                 |
| `sla_policy_order`        | SLA Policy rendering order                                 |
| `webhook`                 | Webhook                                                    |
| `ticket_field`            | Ticket Field (custom or system)                            |
| `ticket_form`             | Ticket Form                                                |
| `ticket_form_order`       | Ticket Form rendering order                                |
| `user_field`              | User Field                                                 |
| `organization_field`      | Organization Field                                         |
| `user_segment`            | User Segment                                               |
| `dynamic_content_item`    | Dynamic Content Item                                       |
| `group`                   | Group                                                      |
| `brand`                   | Brand                                                      |
| `custom_role`             | Custom Role                                                |
| `workspace`               | Zendesk Workspace (agent interface layout)                 |
| `workspace_order`         | Workspace rendering order                                  |
| `routing_attribute`       | Routing Attribute (for Skills routing)                     |
| `routing_attribute_value` | Routing Attribute Value                                    |
| `business_hours_schedule` | Business Hours Schedule                                    |
| `sharing_agreement`       | Sharing Agreement                                          |
| `support_address`         | Support Address (email)                                    |
| `target`                  | Target (outbound webhook target)                           |

---

## NACL Structure Examples

### Trigger

```nacl
zendesk.trigger.instance.ai_review_test {
  title = "AI Review Test"
  active = true
  position = 1
  category_id = zendesk.trigger_category.instance.notifications
  conditions = {
    all = [
      {
        field = "status"
        operator = "is"
        value = "new"
      },
    ]
    any = []
  }
  actions = [
    {
      field = "add_tags"
      value = "ai_review pending_review"
    },
  ]
}
```

### Macro

```nacl
zendesk.macro.instance.close_and_redirect {
  title = "Close and Redirect"
  active = true
  actions = [
    {
      field = "status"
      value = "closed"
    },
  ]
  restriction = {
    type = "Group"
    id = zendesk.group.instance.support
  }
}
```

### Trigger order (must be updated when adding triggers)

```nacl
zendesk.trigger_order.instance.trigger_order {
  order = [
    {
      category = zendesk.trigger_category.instance.notifications
      triggers = [
        zendesk.trigger.instance.existing_trigger_1,
        zendesk.trigger.instance.ai_review_test,
      ]
    },
  ]
}
```

---

## Common Change Patterns

### Adding a new trigger

1. **Find the right file**: triggers live in `envs/<env>/zendesk/` — look for `triggers.nacl` or a file named by category. If no file exists yet, create one.
2. **Derive the instance name**: take the display title, lowercase it, replace spaces with underscores, strip special characters. Example: "AI Review Test" → `ai_review_test`.
3. **Required fields**: `title`, `active`, `conditions` (with both `all` and `any` sub-keys), `actions`.
4. **Check the category reference**: `category_id` must reference an existing `zendesk.trigger_category.instance.<name>`. Run:
   ```bash
   grep -rn "trigger_category.instance" "${WORKSPACE}/envs/<env>/zendesk/" --include="*.nacl"
   ```
   Use one of the found category names. Do not invent a category that doesn't exist.
5. **Update trigger order**: find the `zendesk.trigger_order.instance.trigger_order` element and add the new trigger to its category's `triggers` list.

### Adding a new automation

Same pattern as triggers, but:

- Type: `zendesk.automation.instance.<name>`
- Order element: `zendesk.automation_order.instance.automation_order`
- `conditions.all` and `conditions.any` are both required.

### Adding a macro

Macros do not have categories or order elements. Required fields: `title`, `active`, `actions`. The `restriction` field is optional (omit for unrestricted macros).

### Modifying conditions or actions

`conditions.all`, `conditions.any`, and `actions` are **full replacement** lists — reproduce the entire list including unchanged items. Partial patches are not supported in NACL.

---

## References and IDs

**Always use NACL references, never raw numeric IDs:**

```nacl
# Correct
category_id = zendesk.trigger_category.instance.notifications

# Wrong — raw IDs break environment compare and deploy
category_id = 12345678
```

Before referencing any element (category, group, webhook, etc.), verify it exists in the workspace:

```bash
grep -rn "zendesk.<type>.instance.<name>" "${WORKSPACE}/envs/<env>/zendesk/" --include="*.nacl"
```

---

## Validation Pitfalls

**Duplicate display names** — Zendesk does not enforce name uniqueness, but Salto derives the NACL element ID from the name. Two elements with the same name get the same NACL ID; one is silently dropped. Always check before creating:

```bash
grep -rn '"Your Trigger Name"' "${WORKSPACE}/envs/<env>/zendesk/" --include="*.nacl"
```

**Missing category reference** — a trigger referencing a non-existent `trigger_category` produces a reference error in `validate-local`. Always verify the category exists first.

**Stale order elements** — adding a trigger without updating `trigger_order` causes a `changeError` about missing order items. Always update the order element.

**Boolean quoting** — use `true`/`false` (unquoted). `"true"` is a string and will cause a type error.

**Tag value format** — in `add_tags` actions, the value is a single space-separated string:

```nacl
{ field = "add_tags", value = "tag1 tag2 tag3" }
```

**conditions structure** — both `all` and `any` must be present, even if empty:

```nacl
conditions = {
  all = []
  any = []
}
```

**Condition `field` values for common use cases**:

- Ticket status: `"status"` with values `"new"`, `"open"`, `"pending"`, `"solved"`, `"closed"`
- Ticket tags: `"tags"` with operator `"includes"` or `"not_includes"`
- Assignee: `"assignee_id"` with operator `"is"` or `"is_not"`
- Hours since created: `"hours_since_ticket_created"` with operator `"greater_than"` or `"less_than"`

---

## Deploy Considerations

- **Zendesk PUT-replaces whole resources** — the adapter sends the entire resource on update. If a trigger has 10 conditions and you change 1, all 10 are sent. This is safe but means unrelated fields in the same element are always in scope.
- **SLA policy order is separate** — `sla_policy_order` is a distinct element from `sla_policy`. Both must be clean before push.
- **Webhook ordering** — webhooks referenced by triggers must exist in the target environment before the trigger is deployed. Salto's planner handles this ordering automatically when both are in the same changeset.
- **Guide content requires Guide enabled** — if the workspace has `guide_*` elements but Guide is not enabled on the brand, `validate-local` will produce changeErrors. This is a workspace configuration issue, not a NACL error.
- **Ticket fields with custom options** — `ticket_field` elements with `custom_field_options` must include all options in the list; partial option lists are treated as deletions.
