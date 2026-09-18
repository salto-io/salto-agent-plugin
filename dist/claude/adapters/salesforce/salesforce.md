# Salesforce Adapter — NACL Reference

This file is loaded automatically by salto-deploy and salto-explore when the workspace contains the `salesforce` adapter. It provides NACL element types, ID patterns, structural examples, and pitfalls specific to Salesforce.

---

## Element Types and NACL ID Pattern

Salesforce in Salto uses **two distinct shapes** for element IDs:

- **Custom objects and standard objects** (themselves types): `salesforce.<ObjectApiName>` — e.g. `salesforce.Account`, `salesforce.MyCustom__c`.
- **Metadata instances** (everything else: profiles, flows, layouts, etc.): `salesforce.<MetadataType>.instance.<api_name>` — e.g. `salesforce.Profile.instance.System_Administrator`.

The naming convention for the instance segment is the element's **API name** with dots replaced by underscores (so `Account.MyField` → `Account_MyField` if that ever appeared as part of a full-name path).

### Core element types

| NACL type name        | Salesforce concept                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `<ObjectName>`        | Custom or standard object (top-level type — fields live as nested `field.<FieldApiName>`) |
| `Profile`             | Permission profile (`*.profile-meta.xml`)                                                 |
| `PermissionSet`       | Permission set                                                                            |
| `PermissionSetGroup`  | Permission set group                                                                      |
| `Role`                | User role                                                                                 |
| `Flow`                | Flow (auto-launched, screen, or record-triggered)                                         |
| `Layout`              | Page layout                                                                               |
| `FlexiPage`           | Lightning App Builder page                                                                |
| `RecordType`          | Record type definition                                                                    |
| `ValidationRule`      | Custom validation rule                                                                    |
| `Workflow`            | Workflow rule container                                                                   |
| `WorkflowRule`        | Workflow rule                                                                             |
| `WorkflowFieldUpdate` | Workflow field update                                                                     |
| `EmailTemplate`       | Email template                                                                            |
| `CustomMetadata`      | Custom metadata record                                                                    |
| `CustomLabel`         | Custom label                                                                              |
| `CustomApplication`   | App in App Manager                                                                        |
| `ApexClass`           | Apex class source                                                                         |
| `ApexTrigger`         | Apex trigger                                                                              |
| `StandardValueSet`    | Picklist global value set (e.g. `LeadStatus`)                                             |
| `GlobalValueSet`      | Custom global picklist value set                                                          |
| `AssignmentRules`     | Lead / case assignment rules container                                                    |
| `Queue`               | Queue                                                                                     |
| `Group`               | Public group                                                                              |
| `Territory2`          | Enterprise territory                                                                      |

### Field nesting

Object fields are nested **inside** the object element under `fields.<FieldApiName>`. They are not separate top-level NACL elements:

```nacl
salesforce.Account {
  ...
  fields = {
    Industry__c = {
      type = "Picklist"
      label = "Industry"
      ...
    }
  }
}
```

This matters when diffing: a "field change" is a path-level modification of its parent object, not a separate planItem.

---

## NACL Structure Examples

### Custom object

```nacl
salesforce.MyCustom__c {
  metadataType = "CustomObject"
  apiName = "MyCustom__c"
  label = "My Custom"
  pluralLabel = "My Customs"
  sharingModel = "ReadWrite"
  fields = {
    Name = {
      type = "Text"
      label = "Name"
      required = true
    }
    OwnerId = {
      type = "Lookup"
      label = "Owner"
      referenceTo = ["User"]
    }
  }
}
```

### Profile (object permissions)

```nacl
salesforce.Profile.instance.System_Administrator {
  userPermissions = [
    { name = "ApiEnabled", enabled = true },
    { name = "ViewAllData", enabled = true },
  ]
  objectPermissions = [
    {
      object = salesforce.Account
      allowCreate = true
      allowDelete = true
      allowEdit = true
      allowRead = true
      modifyAllRecords = true
      viewAllRecords = true
    },
  ]
}
```

### Flow

```nacl
salesforce.Flow.instance.My_Lead_Routing {
  apiVersion = 58.0
  label = "My Lead Routing"
  processType = "AutoLaunchedFlow"
  status = "Active"
  start = {
    locationX = 50
    locationY = 50
    connector = { targetReference = "Decision_1" }
  }
  decisions = [...]
}
```

### Validation rule

```nacl
salesforce.ValidationRule.instance.Account_RequireWebsite {
  fullName = "Account.RequireWebsite"
  active = true
  errorConditionFormula = "ISBLANK(Website)"
  errorMessage = "Website is required."
  errorDisplayField = "Website"
}
```

---

## Common Change Patterns

### Adding a custom field to an existing object

1. Find the parent object file: `envs/<env>/salesforce/Objects/<ObjectApiName>.nacl` (or under `Records/CustomObject/<ObjectApiName>.nacl` depending on adapter version).
2. Add the field inside the existing `fields = { ... }` block — do **not** create a new top-level element.
3. Required attributes: `type`, `label`. For lookups/master-detail also `referenceTo`. For picklists also `valueSet` (or reference to a `GlobalValueSet`).
4. Custom fields **must end with `__c`**. The adapter enforces this; deploy will fail otherwise.
5. If the object is referenced by Profiles or Permission Sets, those will also need updates to grant field-level access (FLS) — Salto's planner usually flags the gap as a changeError, but consider whether you also want to add the new field to `fieldPermissions[]`.

### Modifying a profile

Profiles in Salto are **full-replacement** elements — when you edit one entry in `objectPermissions`, the whole block is sent to Salesforce. This is safe but means the validate-local plan will show the entire object permission row as "modified" even if only one boolean flipped.

### Renaming an element

Salesforce metadata API does **not** support rename for most types. To "rename" you must add a new element with the new name and remove the old one. The adapter surfaces this as a paired add+remove in the plan. Watch out for references — anything that pointed at the old name (lookup fields, formulas hardcoding the API name, etc.) must be updated in the same change.

### Adding a record type

```nacl
salesforce.RecordType.instance.Account_Customer {
  fullName = "Account.Customer"
  label = "Customer"
  active = true
  description = "Live customer accounts"
}
```

The `fullName` must be `<ParentObject>.<RecordTypeName>`. The parent object must already exist (managed packages excluded).

---

## References and IDs

**Always use NACL references for object pointers, never raw API names as strings:**

```nacl
# Correct — object reference resolves at deploy time
object = salesforce.Account

# Wrong — string literal won't be tracked for renames or dependency ordering
object = "Account"
```

The same applies to references to other metadata instances (profiles, queues, etc.):

```nacl
# Correct
queue = salesforce.Queue.instance.Tier1_Support

# Wrong
queue = "Tier1_Support"
```

---

## Validation Pitfalls

**`__c` suffix on custom fields** — every custom field, custom object, and custom metadata API name MUST end with `__c`. Forgetting it is the #1 source of deploy errors.

**Managed package elements are read-only** — anything with a namespace prefix (e.g. `npsp__Donor__c`) is owned by an installed managed package. Salto's planner will refuse to modify these and surface a changeError. Don't try to bypass — you cannot deploy modifications to packaged metadata from outside the package.

**StandardValueSet vs GlobalValueSet** — standard pre-defined picklists (LeadStatus, CaseStatus, etc.) are `StandardValueSet`. Custom global picklists are `GlobalValueSet`. Don't mix.

**FLS (field-level security) is a dual write** — adding a field to an object doesn't automatically grant access. The Profile/PermissionSet elements have their own `fieldPermissions[]` list that must be updated. Validate-local can surface the gap; honor its warnings.

**Profile size** — System Administrator and other broad profiles can be 50,000+ lines of NACL. Don't try to read them entirely; grep for the specific permission or object you care about. The adapter loads them lazily on validate-local.

**Layouts reference fields by API name** — if you rename a field, every Layout that referenced it must be updated too. Salto's planner usually surfaces this as a separate plan item per layout; review them carefully before deploy.

**Apex compiles server-side** — adding/modifying an `ApexClass` or `ApexTrigger` runs Salesforce's Apex compiler on deploy. Local validate-local only checks the NACL is structurally valid; compile errors only show up in SaaS preview.

**Test coverage requirement on prod** — Salesforce production orgs require 75% Apex test coverage to deploy. If your change touches Apex, the deploy may fail at the org level even when Salto's preview is clean. This is enforced by Salesforce, not Salto.

---

## Deploy Considerations

- **Two deploy paths**: Salesforce supports both metadata-API deploy and SFDX (Salesforce DX) deploy. Salto uses the appropriate path based on the env configuration — for SFDX-mode envs, the workspace structure under `envs/<env>/salesforce/` follows SFDX layout (force-app/main/default) rather than classic metadata-format.
- **Validation deploy vs. full deploy** — Salto's "preview" performs a Salesforce validation deploy (`checkOnly=true`), which catches most issues without committing changes. The actual "apply" then re-deploys with `checkOnly=false`. If you see a preview-clean → apply-failed gap, the cause is almost always a race (someone changed the org between preview and apply) or a test that ran on apply but not on preview.
- **Sandbox vs. prod** — sandbox envs allow many things prod does not (Apex test coverage, profile changes, etc.). A deploy that's clean against sandbox may still fail against prod for org-policy reasons.
- **Long-running deploys** — a large Salesforce deploy (especially with Apex tests) can take 30+ minutes. The `salto-cli deployment deploy` call exits when Salto's side is done; the Salesforce-side job continues asynchronously and is reflected in the deployment's `serviceDeploymentUrl`.
