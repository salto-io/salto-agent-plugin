# Jira Adapter — NACL Reference

This file is loaded automatically by salto-deploy and salto-explore when the workspace contains the `jira` adapter. It provides NACL element types, ID patterns, structural examples, and pitfalls specific to Jira (Cloud and Server/DC).

---

## Element Types and NACL ID Pattern

Every Jira element uses the pattern:

```
jira.<type_name>.instance.<element_name>
```

`<element_name>` is derived from the element's name or key: lowercase, spaces → underscores, special characters stripped. For elements that have a stable Jira-side key (project keys like `PLAT`, custom field IDs like `customfield_10001`), Salto often uses the key directly to keep diff diffs stable across rename.

### Core element types

| NACL type name                  | Jira concept                                                            |
| ------------------------------- | ----------------------------------------------------------------------- |
| `Project`                       | Project                                                                 |
| `ProjectCategory`               | Project category                                                        |
| `ProjectRole`                   | Project role definition                                                 |
| `IssueType`                     | Issue type                                                              |
| `IssueTypeScheme`               | Issue type scheme (which issue types a project allows)                  |
| `IssueTypeScreenScheme`         | Mapping of issue type → screen scheme                                   |
| `Screen`                        | Screen (which fields appear on a view)                                  |
| `ScreenScheme`                  | Screen scheme (mapping of screen → operation: view/create/edit)         |
| `Workflow`                      | Workflow definition (states + transitions)                              |
| `WorkflowScheme`                | Mapping of issue type → workflow within a project                       |
| `Status`                        | Workflow status (e.g. To Do, In Progress, Done)                         |
| `Priority`                      | Priority value                                                          |
| `Resolution`                    | Resolution value                                                        |
| `Field`                         | Custom field (any type — see subtypes)                                  |
| `FieldConfiguration`            | Field configuration (which fields are required / hidden per scheme)     |
| `FieldConfigurationScheme`      | Mapping of issue type → field configuration                             |
| `Permission`                    | Permission grant                                                        |
| `PermissionScheme`              | Permission scheme                                                       |
| `NotificationScheme`            | Notification scheme                                                     |
| `SecurityScheme`                | Issue security scheme                                                   |
| `SecurityLevel`                 | Security level inside a security scheme                                 |
| `Role` / `ProjectRoleActor`     | Project role actor (who fills a role on a project)                      |
| `Group`                         | User group                                                              |
| `Filter`                        | Saved JQL filter                                                        |
| `Dashboard`                     | Dashboard                                                               |
| `Automation` / `AutomationRule` | Automation rule (Cloud only)                                            |
| `Board` / `Sprint`              | Agile board / sprint (Cloud only)                                       |
| `CustomFieldContext`            | Context defining which projects + issue types a custom field applies to |
| `WebhookConfiguration`          | Webhook (server-side)                                                   |
| `ApplicationLink`               | Application link (DC/Server)                                            |

---

## NACL Structure Examples

### Project

```nacl
jira.Project.instance.platform_team {
  key = "PLAT"
  name = "Platform"
  projectTypeKey = "software"
  projectTemplateKey = "com.pyxis.greenhopper.jira:gh-scrum-template"
  lead = jira.User.instance.alice_admin
  workflowScheme = jira.WorkflowScheme.instance.engineering_default
  issueTypeScheme = jira.IssueTypeScheme.instance.engineering
  permissionScheme = jira.PermissionScheme.instance.engineering
  notificationScheme = jira.NotificationScheme.instance.engineering
  description = "Platform team's project"
  url = "https://example.com/platform"
}
```

### Issue type

```nacl
jira.IssueType.instance.story {
  name = "Story"
  description = "User-facing story"
  iconUrl = "https://example.atlassian.net/.../story.png"
  hierarchyLevel = 0
  avatarId = 10316
}
```

### Workflow

```nacl
jira.Workflow.instance.engineering_review {
  name = "Engineering Review"
  description = "Workflow with mandatory engineering review step"
  statuses = [
    { name = "To Do", category = "new" },
    { name = "In Review", category = "indeterminate" },
    { name = "Done", category = "done" },
  ]
  transitions = [
    {
      name = "Start review"
      from = "To Do"
      to = "In Review"
    },
    {
      name = "Complete"
      from = "In Review"
      to = "Done"
    },
  ]
}
```

### Custom field

```nacl
jira.Field.instance.customfield_10042 {
  id = "customfield_10042"
  name = "Risk Score"
  type = "com.atlassian.jira.plugin.system.customfieldtypes:float"
  description = "1.0 – 10.0 risk rating"
  searcherKey = "com.atlassian.jira.plugin.system.customfieldtypes:exactnumber"
}
```

### Permission scheme

```nacl
jira.PermissionScheme.instance.engineering {
  name = "Engineering Permissions"
  description = "Default permissions for engineering projects"
  permissions = [
    {
      permission = "ADMINISTER_PROJECTS"
      holder = { type = "projectRole", parameter = jira.ProjectRole.instance.administrators }
    },
    {
      permission = "EDIT_ISSUES"
      holder = { type = "projectRole", parameter = jira.ProjectRole.instance.developers }
    },
  ]
}
```

---

## Common Change Patterns

### Adding a custom field

1. Create `jira.Field.instance.customfield_<id>`. The numeric id can be left as `customfield_NEW` if Jira will auto-assign on deploy; Salto re-maps after fetch.
2. Required: `name`, `type` (the full plugin-prefixed key, e.g. `com.atlassian.jira.plugin.system.customfieldtypes:textfield`).
3. **A custom field is not visible anywhere until you also create a `CustomFieldContext`** binding it to the relevant projects + issue types. Without a context, the field exists but doesn't appear on any screen.
4. If the field should be on existing screens, also update the appropriate `Screen` elements to include it.
5. For select-list fields, define the options via the corresponding `CustomFieldContext` — options are scoped per-context, not field-global.

### Adding a project

1. Create `jira.Project.instance.<key_lower>`. The `key` field must match the projected Jira project key (uppercase, 2–10 chars).
2. **Reference, don't inline, all schemes** — `workflowScheme`, `issueTypeScheme`, `permissionScheme`, `notificationScheme`, `fieldConfigurationScheme` should all be references to existing scheme elements. Creating a project that references not-yet-existing schemes makes Salto's planner unhappy.
3. The project lead must be a real user reference; Jira rejects projects without a valid lead.
4. After create, the project shows up in subsequent fetches with auto-generated stuff (default board, default issue type screen scheme bindings). Don't try to predict these in your NACL — let the post-deployment fetch surface them.

### Modifying a workflow

Workflows are the most fragile element type in Jira. Adding a status or transition typically requires:

1. Modifying the `Workflow` itself.
2. Updating the `Screen` for the transition (if it has a custom screen).
3. Confirming the new status exists at the top level (`jira.Status.instance.<status_name>` — these are global, not per-workflow).
4. The new status's `category` must be one of `"new"`, `"indeterminate"`, `"done"` — Jira's three valid status categories.

The Jira backend is strict about workflow correctness. A workflow with an unreachable status or a transition to a non-existent status will be rejected.

### Renaming a status

You can't truly rename a status in Jira — the rename is treated as add+remove. To avoid orphan transitions:

1. Add the new status.
2. Update all transitions to point to the new status.
3. Update all workflows to use the new status.
4. Remove the old status (only after every workflow has been migrated).

Salto's planner may collapse these into a single planItem if you do them in one change — review the detailedChanges carefully.

---

## References and IDs

**Use NACL references for cross-element pointers:**

```nacl
# Correct
workflowScheme = jira.WorkflowScheme.instance.engineering_default

# Wrong — string lookup won't survive a rename
workflowScheme = "engineering_default"
```

Custom field references inside automations or filters often live as string literals (`"customfield_10042"`) because the Jira API itself uses that format. That's acceptable when the target is a stable Jira-assigned identifier; just be aware those won't be tracked by Salto's reference graph.

---

## Validation Pitfalls

**Status category enum** — Jira allows exactly `"new"`, `"indeterminate"`, `"done"`. Anything else is rejected.

**Workflow scheme draft vs. published** — Jira maintains a draft of any scheme that's been modified but not yet published to projects. Salto deploys to the published version directly; if a draft exists, the deploy may fail with "scheme has a draft". Discard the draft in the Jira UI before deploying.

**Custom field type strings are plugin-prefixed** — `text`, `select`, `number`, etc. are NOT valid `type` values. The actual values look like `com.atlassian.jira.plugin.system.customfieldtypes:textfield`. Reuse types from existing fields if unsure.

**Project key length** — Jira project keys are 2–10 uppercase chars (some Cloud orgs allow letters/digits). Don't change keys after project creation; the rename is not supported by the API.

**Permission grants for project roles vs. users** — `holder.type` must be one of `user`, `group`, `projectRole`, `applicationRole`, `reporter`, `currentAssignee`, etc. Mismatched holder types are a common deploy error.

**Cloud vs. Server / DC differences** — automation rules (`AutomationRule`) are Cloud-only. Application links (`ApplicationLink`) are mostly Server/DC. If the source env is Cloud and target is Server (or vice versa), filter the diff carefully — most cross-deploy attempts fail at the type level.

**Sprints and Boards are agile-only** — they require Jira Software (not just Jira Core). Don't expect them on a Service Desk-only env.

---

## Deploy Considerations

- **Order matters across schemes** — Jira's API enforces dependency ordering: you cannot reference a workflow scheme from a project until the workflow scheme exists. Salto's planner usually handles this within a single deploy, but cross-deploy edits (e.g. delete workflow scheme in one PR, delete its project in another) can race.

- **Atlassian Cloud rate limits** — Cloud REST APIs are aggressively rate-limited. Bulk changes (dozens of automations, large permission scheme rewrites) can stall. Salto retries with backoff; if you see deploys taking 10+ minutes, that's likely rate-limiting, not Salto being slow.

- **Workflow editing requires inactive projects** — modifying an active workflow with running issues in transition is restricted. Many workflow changes need the workflow's projects to be temporarily quiesced; review the deploy output for "active issues" warnings.

- **Audit log signal** — Atlassian Cloud's audit log captures every change Salto makes. The "deployed by" user is whoever's API token Salto used. Tag your `SALTO_API_TOKEN` user appropriately if compliance is sensitive.

- **Server / DC quirks** — older Jira Server / Data Center versions return slightly different field shapes than Cloud. Don't assume the same NACL deploys cleanly to both; verify against each target env's adapter version.
