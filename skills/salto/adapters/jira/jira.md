# Jira Adapter — NACL Reference

This file is loaded automatically by salto-deploy and salto-explore when the workspace contains the `jira` adapter. It provides NACL element types, ID patterns, structural examples, and pitfalls specific to Jira (Cloud and Server/DC).

---

## Element Types and NACL ID Pattern

An element is **declared** as `jira.<type_name> <element_name> { ... }` and **referenced** as:

```
jira.<type_name>.instance.<element_name>
```

`<element_name>` is the element's name, case kept. A name made only of letters, digits and `_` is used as-is (`Story`). Otherwise every other character is replaced by `_` and an `@` suffix lists one code per escaped character, underscores included: `s` space, `f` colon, `b` hyphen, `v` dot, `d` slash, `u` underscore. When every escaped character is the same, the code appears only once. For example, `Engineering Review` becomes `Engineering_Review@s`, `Waiting for Support` becomes `Waiting_for_Support@s` (not `@ss`), and `Sales: Lead Workflow` becomes `Sales__Lead_Workflow@fss`. Two types differ:

- **Status** ids are lowercased: `In Progress` → `jira.Status.instance.in_progress@s`.
- **Custom field** ids are `<name>__<type>__c`, escaped as one string: `Risk Score` (type `…:float`) → `jira.Field.instance.Risk_Score__float__c@suuuu`. Salto doesn't use `customfield_10001` as the element id. System fields have no `__c`: `Status__status`, `Summary__string`.

When in doubt, copy the id from an existing fetched element rather than deriving it.

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
| `WorkflowConfiguration`         | Workflow definition (statuses + transitions) — **Cloud**                |
| `Workflow`                      | Workflow definition (statuses + transitions) — **Server / DC**          |
| `WorkflowScheme`                | Mapping of issue type → workflow within a project                       |
| `Status`                        | Workflow status (e.g. To Do, In Progress, Done)                         |
| `StatusCategory`                | Status category (To Do, In Progress, Done) — referenced by `Status`     |
| `Priority`                      | Priority value                                                          |
| `Resolution`                    | Resolution value                                                        |
| `Field`                         | Custom field (any type — see subtypes)                                  |
| `FieldConfiguration`            | Field configuration (which fields are required / hidden per scheme)     |
| `FieldConfigurationScheme`      | Mapping of issue type → field configuration                             |
| `PermissionScheme`              | Permission scheme (holds the permission grants)                         |
| `NotificationScheme`            | Notification scheme                                                     |
| `SecurityScheme`                | Issue security scheme                                                   |
| `SecurityLevel`                 | Security level inside a security scheme                                 |
| `Group`                         | User group                                                              |
| `Filter`                        | Saved JQL filter                                                        |
| `Dashboard`                     | Dashboard                                                               |
| `Automation`                    | Automation rule                                                         |
| `Board`                         | Agile board                                                             |
| `CustomFieldContext`            | Context defining which projects + issue types a custom field applies to |
| `CustomFieldContextOption`      | Option of a select-list field, scoped to one `CustomFieldContext`       |
| `FieldContextOptionsOrder`      | Order of a context's options (must list every option)                   |
| `Webhook`                       | Webhook                                                                 |
| `IssueLinkType`                 | Issue link type (inward / outward descriptions)                         |
| `ProjectComponent`              | Project component (child of a project)                                  |
| `IssueLayout`                   | Issue view layout of a project's screen (child of a project)            |
| `DashboardGadget`               | Gadget on a dashboard (child of a `Dashboard`)                          |
| `PriorityScheme`                | Priority scheme                                                         |
| `FieldScheme`                   | Field scheme (Cloud sites on the newer field configuration model)       |

### Jira Service Management, Assets and Forms

Only fetched when the workspace's Jira adapter config enables them: `fetch.enableJSM` for Service Management and Forms, plus `fetch.enableJSMPremium` for Assets. The project-level ones are children of the service project (see below).

| NACL type name              | Jira concept                                                  | Parent         |
| --------------------------- | ------------------------------------------------------------- | -------------- |
| `RequestType`               | Request type (portal form, issue type, statuses shown)         | `Project`      |
| `Queue`                     | Agent queue (JQL + columns)                                    | `Project`      |
| `SLA`                       | SLA goals and start / stop conditions                          | `Project`      |
| `Calendar`                  | Working hours and holidays used by SLAs                        | `Project`      |
| `PortalGroup`               | Group of request types on the portal                           | `Project`      |
| `PortalSettings`            | Portal name, description and announcements                     | `Project`      |
| `Form`                      | Form (layout and questions in `design`)                        | `Project`      |
| `ObjectSchema`              | Assets object schema                                           | —              |
| `ObjectType`                | Assets object type                                             | `ObjectSchema` |
| `ObjectTypeAttribute`       | Attribute of an object type, linked by its `objectType` field  | —              |
| `ObjectSchemaStatus`        | Assets status                                                  | `ObjectSchema` |
| `ObjectSchemaReferenceType` | Assets reference type                                          | `ObjectSchema` |

### Project-scoped elements

The Service Management types above, plus `Form`, `ProjectComponent` and `IssueLayout`, belong to one project through `_parent = [jira.Project.instance.<project>]`. Keep `_parent` when creating one. Their ids include the project:

- `RequestType`, `Queue`, `SLA`, `Calendar`, `PortalGroup`: `<name>_<PROJECT KEY>`, escaped as one string. Queue `All open` in project `ITSD` → `All_open_ITSD@su`.
- `Form`: `<PROJECT KEY>_<form name>`. The form's name is at `design.settings.name`.
- `PortalSettings`: the project's name.

An id that starts with a digit is quoted where it's declared: `jira.Queue "1st_Line_ITSD@su" { ... }`.

---

## NACL Structure Examples

### Project

```nacl
jira.Project Platform {
  key = "PLAT"
  name = "Platform"
  projectTypeKey = "software"
  projectTemplateKey = "com.pyxis.greenhopper.jira:gh-scrum-template"
  leadAccountId = {
    id = "5b10ac8d82e05b22cc7d4ef5"
  }
  workflowScheme = jira.WorkflowScheme.instance.Engineering_Default@s
  issueTypeScheme = jira.IssueTypeScheme.instance.Engineering
  permissionScheme = jira.PermissionScheme.instance.Engineering_Permissions@s
  notificationScheme = jira.NotificationScheme.instance.Engineering
  description = "Platform team's project"
  url = "https://example.com/platform"
}
```

### Issue type

```nacl
jira.IssueType Story {
  name = "Story"
  description = "User-facing story"
  hierarchyLevel = 0
}
```

### Workflow (Cloud: `WorkflowConfiguration`)

Statuses are references to global `Status` elements. Transitions are a **map**, not a list, keyed `<name>__From__<from status>__<Type>` (the escaped form of `<name>::From: <from status>::<Type>`; initial transitions use `none`, global ones use `any status`).

```nacl
jira.WorkflowConfiguration Engineering_Review@s {
  scope = {
    type = "GLOBAL"
  }
  name = "Engineering Review"
  description = "Workflow with mandatory engineering review step"
  statuses = [
    {
      statusReference = jira.Status.instance.to_do@s
      name = "To Do"
    },
    {
      statusReference = jira.Status.instance.in_review@s
      name = "In Review"
    },
    {
      statusReference = jira.Status.instance.done
      name = "Done"
    },
  ]
  transitions = {
    Create__From__none__Initial@fffsff = {
      type = "INITIAL"
      toStatusReference = jira.Status.instance.to_do@s
      name = "Create"
    }
    Start_review__From__To_Do__Directed@sfffssff = {
      type = "DIRECTED"
      toStatusReference = jira.Status.instance.in_review@s
      links = [
        {
          fromStatusReference = jira.Status.instance.to_do@s
        },
      ]
      name = "Start review"
    }
    Complete__From__In_Review__Directed@fffssff = {
      type = "DIRECTED"
      toStatusReference = jira.Status.instance.done
      links = [
        {
          fromStatusReference = jira.Status.instance.in_review@s
        },
      ]
      name = "Complete"
    }
  }
}
```

**Server / DC** uses `jira.Workflow` with the same transition map but different field names: statuses are `{ id = jira.Status.instance.<status>, name = "..." }`, a transition's target is `to`, its sources are `from = [{ id = jira.Status.instance.<status> }]`, and `type` is lowercase (`"initial"`, `"global"`, and `"common"` or `"ordinary"` for directed transitions).

A status's category belongs to the `Status` element, not the workflow:

```nacl
jira.Status in_review@s {
  name = "In Review"
  statusCategory = jira.StatusCategory.instance.In_Progress@s
}
```

### Custom field

```nacl
jira.Field Risk_Score__float__c@suuuu {
  name = "Risk Score"
  type = "com.atlassian.jira.plugin.system.customfieldtypes:float"
  description = "1.0 – 10.0 risk rating"
  searcherKey = "com.atlassian.jira.plugin.system.customfieldtypes:exactnumber"
}
```

### Service Management queue

```nacl
jira.Queue All_open_ITSD@su {
  name = "All open"
  jql = "${ jira.Field.instance.Status__status } != ${ jira.Status.instance.done.name } AND ${ jira.Field.instance.Assignee__user } is EMPTY"
  columns = [
    jira.Field.instance.Key,
    jira.Field.instance.Summary__string,
    jira.Field.instance.Status__status,
  ]
  canBeHidden = false
  favourite = false
  _parent = [
    jira.Project.instance.IT_Service_Desk@s,
  ]
}
```

### Permission scheme

```nacl
jira.PermissionScheme Engineering_Permissions@s {
  name = "Engineering Permissions"
  description = "Default permissions for engineering projects"
  permissions = [
    {
      permission = "ADMINISTER_PROJECTS"
      holder = { type = "projectRole", parameter = jira.ProjectRole.instance.Administrators }
    },
    {
      permission = "EDIT_ISSUES"
      holder = { type = "projectRole", parameter = jira.ProjectRole.instance.Developers }
    },
  ]
}
```

---

## Common Change Patterns

### Adding a custom field

1. Create `jira.Field <name>__<type>__c { ... }` (see the naming rules above). Don't set an `id`; Jira assigns the `customfield_<n>` id on deploy.
2. Required: `name`, `type` (the full plugin-prefixed key, e.g. `com.atlassian.jira.plugin.system.customfieldtypes:textfield`).
3. **A custom field is not visible anywhere until you also create a `CustomFieldContext`** binding it to the relevant projects + issue types. Without a context, the field exists but doesn't appear on any screen.
4. If the field should be on existing screens, also update the appropriate `Screen` elements to include it.
5. For select-list fields, options are separate `jira.CustomFieldContextOption` elements, each with `value`, `disabled` and `_parent = [jira.CustomFieldContext.instance.<context>]`. Options are scoped per context, not per field. Each context also has one `jira.FieldContextOptionsOrder` element (`_parent` = the context) whose `options` list must reference every option; otherwise Salto blocks the deploy.

### Adding a project

1. Create `jira.Project <project name> { ... }` (the element id comes from the project's name, not its key). The `key` field holds the Jira project key (uppercase, 2–10 chars).
2. **Reference, don't inline, all schemes** — `workflowScheme`, `issueTypeScheme`, `permissionScheme`, `notificationScheme`, `fieldConfigurationScheme` should all be references to existing scheme elements. Creating a project that references not-yet-existing schemes makes Salto's planner unhappy.
3. The project lead is `leadAccountId = { id = "<accountId>" }` (Cloud account id; on Server / DC, the username). Jira rejects projects without a valid lead.
4. After create, the project shows up in subsequent fetches with auto-generated stuff (default board, default issue type screen scheme bindings). Don't try to predict these in your NACL — let the post-deployment fetch surface them.

### Modifying a workflow

Workflows are the most fragile element type in Jira. Adding a status or transition typically requires:

1. Modifying the workflow itself (`WorkflowConfiguration` on Cloud, `Workflow` on Server / DC).
2. Updating the `Screen` for the transition (if it has a custom screen).
3. Confirming the new status exists at the top level (`jira.Status.instance.<status_id>`, lowercased; statuses are global, not per-workflow).
4. Setting the new status's category on the `Status` element: `statusCategory = jira.StatusCategory.instance.To_Do@s`, `In_Progress@s` or `Done`.

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
workflowScheme = jira.WorkflowScheme.instance.Engineering_Default@s

# Wrong — string lookup won't survive a rename
workflowScheme = "Engineering Default"
```

**JQL is stored as a template.** In `Filter` and `Queue` `jql`, fields appear as `${ jira.Field.instance.<field> }` and values as `${ jira.Status.instance.<status>.name }` (wrapped in `\"…\"` when the name has spaces). Keep that form when editing JQL. A plain name in its place isn't tracked as a reference.

Custom field references inside automations often live as string literals (`"customfield_10042"`) because the Jira API itself uses that format. That's acceptable when the target is a stable Jira-assigned identifier; just be aware those won't be tracked by Salto's reference graph.

---

## Validation Pitfalls

**Status category** — a status belongs to To Do, In Progress or Done (Jira keys `new`, `indeterminate`, `done`). In NACL a `Status` references the `StatusCategory` element (`To_Do@s`, `In_Progress@s` or `Done`) rather than using these strings.

**Workflow scheme draft vs. published** — Jira maintains a draft of any scheme that's been modified but not yet published to projects. Salto deploys to the published version directly; if a draft exists, the deploy may fail with "scheme has a draft". Discard the draft in the Jira UI before deploying.

**Custom field type strings are plugin-prefixed** — `text`, `select`, `number`, etc. are NOT valid `type` values. The actual values look like `com.atlassian.jira.plugin.system.customfieldtypes:textfield`. Reuse types from existing fields if unsure.

**Project key length** — Jira project keys are 2–10 uppercase chars (some Cloud orgs allow letters/digits). Don't change keys after project creation; the rename is not supported by the API.

**Permission grants for project roles vs. users** — `holder.type` must be one of `user`, `group`, `projectRole`, `applicationRole`, `reporter`, `currentAssignee`, etc. Mismatched holder types are a common deploy error.

**Cloud vs. Server / DC differences** — workflows are `WorkflowConfiguration` on Cloud and `Workflow` on Server / DC, with different field names (see the Workflow example). If the source env is Cloud and target is Server (or vice versa), filter the diff carefully — most cross-deploy attempts fail at the type level.

**Boards are agile-only** — they require Jira Software (not just Jira Core). Don't expect them on a Service Desk-only env.

---

## Deploy Considerations

- **Order matters across schemes** — Jira's API enforces dependency ordering: you cannot reference a workflow scheme from a project until the workflow scheme exists. Salto's planner usually handles this within a single deploy, but cross-deploy edits (e.g. delete workflow scheme in one PR, delete its project in another) can race.

- **Atlassian Cloud rate limits** — Cloud REST APIs are aggressively rate-limited. Bulk changes (dozens of automations, large permission scheme rewrites) can stall. Salto retries with backoff; if you see deploys taking 10+ minutes, that's likely rate-limiting, not Salto being slow.

- **Workflow editing requires inactive projects** — modifying an active workflow with running issues in transition is restricted. Many workflow changes need the workflow's projects to be temporarily quiesced; review the deploy output for "active issues" warnings.

- **Audit log signal** — Atlassian Cloud's audit log captures every change Salto makes. The "deployed by" user is whoever's API token Salto used. Tag your `SALTO_API_TOKEN` user appropriately if compliance is sensitive.

- **Server / DC quirks** — older Jira Server / Data Center versions return slightly different field shapes than Cloud. Don't assume the same NACL deploys cleanly to both; verify against each target env's adapter version.
