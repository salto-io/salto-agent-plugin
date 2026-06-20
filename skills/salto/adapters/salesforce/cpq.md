# Salesforce CPQ (SBQQ / sbaa) — NACL Reference

This file is loaded automatically by salto-deploy, salto-explore, and the cpq-to-rlm-migration workflow when the workspace's `salesforce` **data** config (`fetch.data.includeObjects`) contains `SBQQ__.*` or `sbaa__…`. It complements `salesforce.md`: that file covers Salesforce **metadata** (Profiles, Flows, Apex, …); this file covers the **CPQ configuration data** — instances of managed-package objects that Salto manages as data.

> [!NOTE]
> CPQ (Steelbrick) is a **managed package**. Its object/field *definitions* (namespace `SBQQ__`, `sbaa__`) are read-only packaged metadata. What you edit in Salto are the **records** of those objects (price rules, product options, etc.), pulled in as data because `includeObjects` selects them. Transactional objects (Quote, QuoteLine, Subscription, consumption, logs) are excluded by config and never present.

---

## Record NACL shape

CPQ records are **data instances**, written one file per record at
`salesforce/InstalledPackages/SBQQ/Records/<Type>/<RecordId>.nacl` (and `…/sbaa/Records/…`). Standard objects used by CPQ (`Product2`, `Pricebook2`, `PricebookEntry`) live under `salesforce/Records/<Type>/`.

```nacl
salesforce.SBQQ__ProductOption__c a0q4J000000GfV6QAK {
  SBQQ__ConfiguredSKU__c = salesforce.Product2.instance.01t4J000001gd84QAA   # bundle parent
  SBQQ__OptionalSKU__c   = salesforce.Product2.instance.01t4J000001gd4WQAQ   # child product
  SBQQ__Feature__c       = salesforce.SBQQ__ProductFeature__c.instance.a0p4J000009OqjVQAS
  SBQQ__Number__c        = 10
  SBQQ__Type__c          = salesforce.SBQQ__ProductOption__c.field.SBQQ__Type__c.valueSet.values.Component.fullName
  _alias = "K2HWSMONAPR S&M … K2N Bundle"
}
```

Conventions that matter when authoring/diffing:
- **Declaration:** `salesforce.<Type> <RecordId> { … }`. The id is the 18-char Salesforce Id (default Salto ID — see below). When the id starts with a digit it is quoted: `salesforce.Product2 "01t4J000001gcsdQAA"`.
- **References to other records:** `salesforce.<Type>.instance.<RecordId>` — always a NACL reference, never a string.
- **Picklist values:** `salesforce.<Type>.field.<Field>.valueSet.values.<Value>.fullName`. Spaces/special chars are encoded (`On_Calculate@s`, `Product_Option@s`, `1@`). Don't hand-write these — copy the exact encoded ref.
- **`_alias`** is a human-readable label Salto adds (often parent context baked in). It is display-only; it is the field behind the "compare shows a diff because the name/number differs across orgs" noise.
- **Salto ID:** `saltoIDSettings.defaultIdFields = ["Id"]` — every CPQ record is keyed by its Salesforce Id. There are no Name/Code overrides (unlike RLM).

---

## Object dictionary by functional area

### Catalog & bundles
| Object | Purpose | Key fields / links |
| --- | --- | --- |
| `Product2` (+ `SBQQ__*` fields) | Catalog item. Bundle parent if it has options. | `ProductCode`, `Family`, `SBQQ__SubscriptionType__c`, `SBQQ__SubscriptionPricing__c`, `SBQQ__PricingMethod__c`, `SBQQ__Optional__c`, `SBQQ__OptionSelectionMethod__c`, `SBQQ__BlockPricingField__c` |
| `SBQQ__ProductOption__c` | One child line of a bundle. | `SBQQ__ConfiguredSKU__c`→parent Product2, `SBQQ__OptionalSKU__c`→child Product2, `SBQQ__Feature__c`→feature, `SBQQ__Number__c` (order), `SBQQ__Quantity__c`, `SBQQ__Required__c`, `SBQQ__Bundled__c`, `SBQQ__Type__c` (Component/Accessory/Related), `SBQQ__DiscountedByPackage__c` |
| `SBQQ__ProductFeature__c` | Named group of options within a bundle. | `SBQQ__ConfiguredSKU__c`→parent Product2, `SBQQ__MinOptionCount__c`, `SBQQ__MaxOptionCount__c`, `SBQQ__Number__c`, `Name` |
| `SBQQ__ConfigurationRule__c` | Binds a ProductRule to a product/feature in the configurator. | `SBQQ__Product__c`, `SBQQ__ProductFeature__c`, `SBQQ__ProductRule__c`, `SBQQ__RuleType__c` (Selection/Validation/…), `SBQQ__RuleEvaluationEvent__c` |

### Pricing & discounts
| Object | Purpose | Key fields / links |
| --- | --- | --- |
| `SBQQ__PriceRule__c` | A pricing rule (fires on an event, targets calculator/quote/line). | `SBQQ__Active__c`, `SBQQ__ConditionsMet__c` (All/Any/Custom), `SBQQ__EvaluationEvent__c`, `SBQQ__TargetObject__c` |
| `SBQQ__PriceCondition__c` | A condition gating a price rule. | `SBQQ__Rule__c`→PriceRule, `SBQQ__Object__c`, `SBQQ__Field__c`, `SBQQ__Operator__c`, `SBQQ__FilterType__c`, `SBQQ__Value__c` |
| `SBQQ__PriceAction__c` | The effect of a price rule (writes a field). | `SBQQ__Rule__c`→PriceRule, `SBQQ__Field__c` (target field), `SBQQ__TargetObject__c`, `SBQQ__SourceVariable__c`→SummaryVariable, `SBQQ__Formula__c` |
| `SBQQ__SummaryVariable__c` | Aggregation used by price logic/formulas. | `SBQQ__AggregateField__c`, `SBQQ__AggregateFunction__c` (Sum/Count/…), `SBQQ__TargetObject__c`, `SBQQ__Scope__c`, `SBQQ__ConstraintField__c` |
| `SBQQ__DiscountSchedule__c` | Volume/term discount tiers. | `SBQQ__Type__c` (Range/Slab), `SBQQ__DiscountUnit__c` (Percent/Amount), `SBQQ__AggregationScope__c`, `SBQQ__ConstraintField__c`; tiers in `SBQQ__DiscountTier__c` |
| `SBQQ__DiscountTier__c` | One tier of a schedule. | `SBQQ__Schedule__c`, `SBQQ__LowerBound__c`, `SBQQ__UpperBound__c`, `SBQQ__Discount__c` |
| `Pricebook2` / `PricebookEntry` | Standard price book + list prices. | `allowReferenceTo` only by default (referenced, lightly managed). |

### Attributes & configuration rules
| Object | Purpose | Key fields / links |
| --- | --- | --- |
| `SBQQ__ConfigurationAttribute__c` | A product-scoped attribute shown in the configurator. | `SBQQ__Product__c`, `SBQQ__Position__c`, `SBQQ__DisplayOrder__c`, `SBQQ__TargetField__c` (writes to a quote-line field), `SBQQ__DefaultObject__c`/`SBQQ__DefaultField__c`, `SBQQ__Required__c`, `SBQQ__Global__c` |
| `SBQQ__ProductRule__c` | Selection/Validation/Alert/Filter rule. | `SBQQ__Type__c`, `SBQQ__Scope__c` (Product/Quote), `SBQQ__EvaluationEvent__c`, `SBQQ__ConditionsMet__c`, `SBQQ__EvaluationOrder__c` |
| `SBQQ__ProductAction__c` | The effect of a product rule (add/hide/etc.). | `SBQQ__Rule__c`→ProductRule, `SBQQ__Product__c`, `SBQQ__Type__c` (Add/Remove/…), `SBQQ__Required__c` |
| `SBQQ__ErrorCondition__c` | Condition for a product/validation rule. | `SBQQ__Rule__c`, tested object/field/operator/value |
| `SBQQ__CustomScript__c` / `SBQQ__CustomAction__c` | Apex/JS extension points & custom buttons. | Free-form Apex/JS — **no declarative equivalent in RLM** |

### Advanced Approvals (sbaa)
`sbaa__ApprovalRule__c`, `sbaa__ApprovalCondition__c`, `sbaa__ApprovalChain__c`, `sbaa__Approver__c`, `sbaa__ApprovalVariable__c`, `sbaa__EmailTemplate__c`, `sbaa__TrackedField__c`. Rule↔Condition relationship mirrors PriceRule/PriceCondition.

---

## Common change patterns

- **Edit a bundle option:** change the `SBQQ__ProductOption__c` record (quantity, required, feature, order). Adding an option = new `SBQQ__ProductOption__c` with `SBQQ__ConfiguredSKU__c`→parent and `SBQQ__OptionalSKU__c`→child.
- **Add a price rule:** create `SBQQ__PriceRule__c`, then its `SBQQ__PriceCondition__c`(s) and `SBQQ__PriceAction__c`(s) pointing back via `SBQQ__Rule__c`. See the deploy quirk below for ordering.
- **Adjust a discount:** edit `SBQQ__DiscountTier__c` rows under the schedule.

---

## Deploy considerations & quirks (from `packages/salesforce-adapter/src`)

- **CPQ triggers must be paused during data deploys.** A change validator (`change_validators/cpq_trigger.ts`) detects CPQ data changes and instructs you to disable/re-enable CPQ package triggers around the deploy. Honor the info message.
- **Rule ↔ Condition circular dependency.** A rule references its conditions and vice-versa. The adapter (`group_changes.ts`, `custom_object_instances_deploy.ts`) groups them and deploys the **rule first with `SBQQ__ConditionsMet__c = 'All'`**, then the conditions, then restores `ConditionsMet`. Applies to CPQ Price rules, Product rules, Quote Terms, and sbaa Approval rules. You don't orchestrate this — but expect the plan to show the grouped/regrouped changes.

## Validation pitfalls

- **Packaged metadata is read-only.** You cannot modify the `SBQQ__`/`sbaa__` object or field *definitions* — only their records. Salto's planner refuses changes to packaged metadata.
- **Keyed by Salesforce Id.** With `defaultIdFields = ["Id"]`, records are identified by org-specific Ids, so the same logical record has a different Salto ID in each org — this is why cross-env compares of CPQ data are noisy (see `_alias`). RLM, by contrast, uses Name/Code keys.
- **References must resolve.** Use `salesforce.<Type>.instance.<id>` and the exact encoded `valueSet.values.<V>.fullName` refs; raw strings break dependency ordering and renames.
