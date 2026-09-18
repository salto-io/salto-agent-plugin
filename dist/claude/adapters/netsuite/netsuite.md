# NetSuite Adapter — NACL Reference

This file is loaded automatically by salto-deploy and salto-explore when the workspace contains the `netsuite` adapter. It provides NACL element types, ID patterns, structural examples, and pitfalls specific to NetSuite.

---

## Element Types and NACL ID Pattern

NetSuite has two distinct deployment surfaces — **SDF** (SuiteCloud Development Framework) for customizations and **SuiteApp** records data — and Salto handles both. The NACL shape mirrors SDF's XML:

```
netsuite.<element_type>.instance.<scriptid>
```

`<scriptid>` is the customer-set unique identifier on the NetSuite element (e.g. `customrecord_mytype`, `customfield_invoice_region`). Element types follow the SDF naming convention exactly.

### Core element types

| NACL type name                 | NetSuite concept                                                      |
| ------------------------------ | --------------------------------------------------------------------- |
| `customrecordtype`             | Custom Record Type definition                                         |
| `customrecord_<scriptid>`      | Records of a specific custom record type (type itself, fields nested) |
| `customlist`                   | Custom List                                                           |
| `customfield`                  | Custom field (any kind — see subtypes)                                |
| `transactionbodycustomfield`   | Custom field on transaction body                                      |
| `transactioncolumncustomfield` | Custom field on transaction line                                      |
| `entitycustomfield`            | Custom field on entities (customer/vendor/employee)                   |
| `itemcustomfield`              | Custom field on items                                                 |
| `othercustomfield`             | Custom field on other record types                                    |
| `crmcustomfield`               | Custom field on CRM records                                           |
| `transactionForm`              | Transaction form layout                                               |
| `entryForm`                    | Entry form layout                                                     |
| `subtab`                       | Subtab                                                                |
| `workflow`                     | NetSuite workflow                                                     |
| `script`                       | SuiteScript record (Client, User Event, Scheduled, etc.)              |
| `scriptdeployment`             | Script deployment binding                                             |
| `customsegment`                | Custom segment (custom dimension)                                     |
| `customtransactiontype`        | Custom transaction type                                               |
| `savedsearch`                  | Saved search                                                          |
| `dataset`                      | Dataset (SuiteAnalytics)                                              |
| `workbook`                     | Workbook (SuiteAnalytics)                                             |
| `kpiscorecard`                 | KPI scorecard                                                         |
| `bundle`                       | SuiteApp bundle reference                                             |
| `role`                         | Role with permissions                                                 |
| `emailtemplate`                | Email template                                                        |
| `customrecord_translation`     | Custom record translation                                             |
| `centertab` / `centerlink`     | Custom center tab / link                                              |
| `addressForm`                  | Address form                                                          |
| `advancedpdftemplate`          | Advanced PDF template                                                 |

### Records of custom record types

When a customer-defined custom record type is fetched, Salto creates a NACL **type** named `netsuite.customrecord_<scriptid>` and individual record instances live as `netsuite.customrecord_<scriptid>.instance.<recordid>`. The fields of the type are nested inside the type definition; instances reference them by name.

---

## NACL Structure Examples

### Custom field on transactions

```nacl
netsuite.transactionbodycustomfield.instance.custbody_region {
  scriptid = "custbody_region"
  label = "Region"
  fieldtype = "SELECT"
  selectrecordtype = netsuite.customlist.instance.customlist_regions
  appliestoallforms = true
  displaytype = "NORMAL"
  storevalue = true
  isparent = false
  isformula = false
  defaultchecked = false
  defaultvalue = ""
}
```

### Custom list

```nacl
netsuite.customlist.instance.customlist_regions {
  scriptid = "customlist_regions"
  name = "Regions"
  customvalues = {
    customvalue = [
      { scriptid = "val_emea", value = "EMEA", isinactive = false },
      { scriptid = "val_amer", value = "Americas", isinactive = false },
      { scriptid = "val_apac", value = "Asia-Pacific", isinactive = false },
    ]
  }
}
```

### Custom record type

```nacl
netsuite.customrecordtype.instance.customrecord_project_metadata {
  scriptid = "customrecord_project_metadata"
  recordname = "Project Metadata"
  customrecordcustomfields = {
    customrecordcustomfield = [
      {
        scriptid = "custrecord_project_owner"
        label = "Project Owner"
        fieldtype = "SELECT"
        selectrecordtype = "-4"  # Employee
      },
    ]
  }
}
```

### Saved search

```nacl
netsuite.savedsearch.instance.customsearch_overdue_invoices {
  scriptid = "customsearch_overdue_invoices"
  searchtype = "Transaction"
  title = "Overdue Invoices"
  ispublic = true
  definition = "<search>...</search>"  # The actual search definition is opaque XML
}
```

---

## Common Change Patterns

### Adding a transaction body custom field

1. Create a new `netsuite.transactionbodycustomfield.instance.<scriptid>` element. `<scriptid>` MUST start with `custbody_` and be unique workspace-wide.
2. Required: `scriptid`, `label`, `fieldtype` (e.g. `TEXT`, `SELECT`, `INTEGER`, `DATE`, `CURRENCY`, `CHECKBOX`).
3. If `fieldtype = "SELECT"`, also set `selectrecordtype` — usually a reference to a custom list or a built-in record type (employees use `"-4"`, customers `"-2"`, etc.).
4. **`appliestoallforms = true` is dangerous** — it adds the field to every transaction form in the system. Read the NetSuite post-deployment fetch notes carefully (see Deploy Considerations).
5. Update relevant forms (`transactionForm` elements) if you want fine-grained placement instead of `appliestoallforms`.

### Adding a custom record type

1. Create `netsuite.customrecordtype.instance.<scriptid>` — `<scriptid>` MUST start with `customrecord_`.
2. Nest fields inside `customrecordcustomfields = { customrecordcustomfield = [...] }`. Each field has its own `scriptid` starting with `custrecord_`.
3. The record type itself produces an implicit "type" in subsequent fetches — records of this type will appear as instances of `netsuite.customrecord_<scriptid>`.
4. If the type is intended to be referenced from transactions or other custom fields, set `accesstype = "USERECORDLEVEL"` or appropriate access mode.

### Adding a SuiteScript

1. The actual script code lives as a referenced file (`.js`) under the workspace's adapter file tree, not inside the NACL. The NACL element describes the script's deployment binding.
2. The `scriptid` MUST start with the right prefix (`customscript_` for scripts, `customdeploy_` for script deployments).
3. The script file path is referenced from the script NACL via the `scriptfile` field; ensure the file exists in the workspace under the expected adapter path.

### Modifying a workflow

NetSuite workflows are large, nested elements. Salto treats the whole workflow as a single element — partial edits get serialized as a single planItem with many path-level detailedChanges. Watch out for unintentional whitespace / ordering changes from manual edits; use a YAML/NACL formatter if available.

---

## References and IDs

**Use NACL references for known custom elements, even when NetSuite stores them as scriptid strings:**

```nacl
# Correct
selectrecordtype = netsuite.customlist.instance.customlist_regions

# Acceptable for built-in NetSuite records that have no NACL element
selectrecordtype = "-4"  # Employee — built-in record type ID
```

The numeric record-type IDs (`-2`, `-4`, `-103`, etc.) are NetSuite-internal identifiers for built-in record types. They have no corresponding NACL elements; use them as strings.

---

## Validation Pitfalls

**Scriptid prefix rules** — every element type has a required `scriptid` prefix:

- `customrecord_` — custom record type
- `customfield_` — generic custom field (rarely used directly; subtypes preferred)
- `custbody_` — transaction body field
- `custcol_` — transaction column field
- `custentity_` — entity field
- `custitem_` — item field
- `customlist_` — custom list
- `customsearch_` — saved search
- `customscript_` — script
- `customdeploy_` — script deployment

Wrong prefix = deploy failure. The adapter usually catches this in validate-local.

**Scriptid uniqueness** — scriptids are workspace-unique across ALL element types. Reusing the same scriptid for two different elements (even of different types) breaks the workspace.

**Custom field `selectrecordtype` must match `fieldtype`** — `SELECT` and `MULTISELECT` fields require `selectrecordtype`; other types should not have it. Mismatches surface as a changeError.

**Saved search `definition` is opaque XML** — Salto stores the search query as XML inside the NACL. Hand-editing this is error-prone; safer to recreate the search in the NetSuite UI and re-fetch.

**Workflow scriptid case sensitivity** — NetSuite is inconsistent about case in workflow `scriptid` references. Always copy the exact case from the source element.

**`isinactive = true` is a soft delete, not a true remove** — in NetSuite, "deleting" most custom elements just flips `isinactive`. The NACL will still contain the element; Salto distinguishes by the field.

---

## Deploy Considerations

- **Post-deployment fetch ripple effects** — NetSuite's metadata graph is densely interconnected. Deploying a new `transactionbodycustomfield` with `appliestoallforms = true` causes NetSuite to back-populate the field reference into every `transactionForm` element. Salto's post-deployment fetch then surfaces those as new changes in the next NACL diff. This is normal — not corruption — but it's confusing the first time you see it. The user's local working copy will need a second `git pull` after the post-deployment fetch completes to pick these up.

- **Validation vs. apply** — NetSuite's SDF validate runs `suitecloud project:deploy --dryrun`-equivalent server-side. Most errors surface there, but a few (notably permission and data-volume errors) only emerge during the live deploy.

- **Account-side prerequisites** — some elements require account-level features to be enabled (e.g. `customtransactiontype` needs Custom Transaction Types feature on). If the target account doesn't have the feature, Salto's preview will be clean but apply will fail. Surface this proactively when you see an unusual element type in the change set.

- **Production vs. sandbox** — NetSuite sandboxes are full mirrors but with their own `account_id`. A deploy run against a sandbox account is a no-op on prod; cross-environment changes always go through Salto's deployment mechanism, never direct.

- **Large workspaces are slow** — NetSuite enterprise workspaces with thousands of saved searches and scripts can take 5+ minutes to fetch state. Plan around that — don't `--refresh-state` unless necessary.

---

## Record-Instance Cheat Sheet (locations, subsidiaries, addresses)

**Address `country` / `timeZone` enum values** — these fields are typed `unknown` in the NACL schema, so nothing validates them locally; a wrong value only fails at the live deploy. NetSuite uses `_camelCase` enum tokens. Verified-in-production examples:

| Country | `country` | Typical `timeZone` |
| --- | --- | --- |
| United States | `_unitedStates` | `_americaLosAngeles`, `_americaNewYork`, `_americaChicago` |
| United Kingdom | `_unitedKingdomGB` | `_europeLondon` |
| Canada | `_canada` | `_americaToronto` |
| Japan | `_japan` | `_asiaTokyo` |
| Israel | `_israel` | `_asiaJerusalem` |

For other countries, follow the same pattern (`_<camelCasedEnglishName>`); when the workspace has `Records/nexus/` entries (e.g. `_unitedStates_California`), their prefixes confirm the country token. Do not spend time hunting for an authoritative enum list in the workspace or adapter sources — it is not there.

**`classTranslationList` is fetch-only** — existing records carry it (account-level translation defaults), but NetSuite does not support deploying it and validate-local raises a Warning. **Omit it when creating new records**; don't copy it from sibling records.

**New location records** — model on an existing location: `name`, `subsidiaryList` (reference existing subsidiary instances), `isInactive = false`, `makeInventoryAvailable = false`, and a `mainAddress` block (`country`, `addressee`, `addr1`/`addr2`, `city`, `state`, `zip`, `addrText` mirroring the address lines with `<br>` separators).
