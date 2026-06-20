# Salesforce RLM / Revenue Cloud Advanced (RCA) — NACL Reference

This file is loaded automatically by salto-deploy, salto-explore, and the cpq-to-rlm-migration workflow when the workspace's `salesforce` **data** config (`fetch.data.includeObjects`) contains RLM objects (e.g. `ProductClassification`, `AttributeDefinition`, `RateCard`, `ProductSellingModel`). It complements `salesforce.md` (metadata) — this file covers the **RLM configuration data**: instances of **native standard objects** managed as data.

> [!NOTE]
> RLM (a.k.a. Revenue Cloud Advanced / Agentforce Revenue Management) is **NOT a managed package** — its objects are native Salesforce objects with **no namespace prefix** (`ProductClassification`, not `SBQQ__…`). In Salesforce they live in the main Object Manager / Elements, not under Installed Packages. Salto manages their **records** as data (`includeObjects` selects ~36 RLM objects).

---

## Record NACL shape

RLM records are data instances at `<env>/salesforce/Records/<Type>/<SaltoID>.nacl`. Shared standard objects (`Product2`, `Pricebook2`, `PricebookEntry`) live under the same `Records/` tree.

```nacl
salesforce.ProductRelatedComponent "0dSbm000000Il3hEAC" {
  ParentProductId          = salesforce.Product2.instance.01tbm00000NooUWAAZ
  ChildProductId           = salesforce.Product2.instance.01tbm00000NooUrAAJ
  ParentProductRole        = "Bundle"
  ChildProductRole         = "BundleComponent"
  ProductComponentGroupId  = salesforce.ProductComponentGroup.instance.0y7bm000000EZR7AAO
  ProductRelationshipTypeId = salesforce.ProductRelationshipType.instance.0yobm000000PW9ZAAW
  Quantity                 = 1
  IsComponentRequired      = true
  IsDefaultComponent       = true
  Sequence                 = 2
  _alias = "PRC-000000023"
}
```

Conventions (verified against a live RLM org):
- **Declaration:** `salesforce.<Type> <SaltoID> { … }`. The SaltoID depends on `saltoIDSettings` (below): a human key for override objects, otherwise the 18-char Salesforce Id (quoted when it starts with a digit, e.g. `"0dSbm…"`).
- **SaltoID overrides** (from the data config): records keyed by a real business field, so they're stable across orgs (unlike CPQ's Id keys):
  - `ProductClassification` → **Code** (file `ACTVN.nacl`, `ProductClassification ACTVN`)
  - `AttributeDefinition` → **Name** (`Advance_Ecommerce@s` — spaces encoded `@s`)
  - `AttributeCategory` → **Name**
  - `AttributePicklist` → **Code** (`CW00902`)
  - `UnitOfMeasureClass` → **Code** (`CALLUNITS01`)
  - everything else → **Id**.
- **References:** `salesforce.<Type>.instance.<SaltoID>` (always a NACL ref). Field refs: `salesforce.Contract.field.Status`; object label ref: `salesforce.Contract.attr.label`. Picklist values: `salesforce.<Type>.field.<F>.valueSet.values.<V>.fullName`.
- **Broken/unfetched references** render as `salesforce.<Type>.instance.missing_<id>` (e.g. `salesforce.BillingPolicy.instance.missing_1BPbm…` on `Product2`). This is the `brokenOutgoingReferencesSettings.defaultBehavior = "BrokenReference"` at work — targets outside the fetched set. `User` refs use `InternalId` instead.
- **Custom fields exist on RLM objects too** — e.g. `MinNumberOfEmployees__c` on `ProductQualification`, `Industry__c` (picklist) on `ProductDisqualification`.
- **`_alias`** is Salto's display label (often parent context baked in, e.g. `"LP001 Hardware Laptop Screen Size"`).

---

## Object dictionary by functional area

### Catalog & attributes
| Object | SaltoID | Purpose / key fields |
| --- | --- | --- |
| `Product2` (+ RLM fields) | Id | Catalog item. `Name`, `ProductCode`, `Family`, `ConfigureDuringSale` (Allowed/Required/NotAllowed), `CanRamp`, `IsAssetizable`, `IsSerialized`, `IsSoldOnlyWithOtherProds`, `SpecificationType`, `BillingPolicyId`, `TaxPolicyId`. **No SBQQ fields.** |
| `ProductClassification` | **Code** | Product category/type. `Code`, `Name`, `Status`. |
| `ProductClassificationAttr` | Id | Attribute attached to a classification. `ProductClassificationId`, `AttributeDefinitionId`, `AttributeNameOverride`, `Is{Hidden,PriceImpacting,ReadOnly,Required}`, `UnitOfMeasureId`, `Status`. |
| `AttributeDefinition` | **Name** | Reusable attribute. `Name`, `DeveloperName`, `Label`, `DataType` (Checkbox/Number/Picklist/Text…), `DefaultValue`, `IsActive`, `IsRequired`. |
| `AttributeCategory` | **Name** | Display grouping of attributes. `Code`, `Name`. |
| `AttributeCategoryAttribute` | Id | Links category↔attribute. `AttributeCategoryId`, `AttributeDefinitionId`. |
| `AttributePicklist` | **Code** | Picklist for an attribute. `Code`, `Name`, `DataType`, `Status`, `UnitOfMeasureId`. |
| `AttributePicklistValue` | Id | One picklist value. `PicklistId`, `Code`, `Name`, `Value`, `DisplayValue`, `Sequence`, `IsDefault`, `Status`. |
| `ProductAttributeDefinition` | Id | Binds an attribute to a product. `Product2Id`, `AttributeDefinitionId`, `AttributeCategoryId`, `ProductClassificationAttributeId`, `DefaultValue`, `Is{Hidden,PriceImpacting,ReadOnly,Required}`, `Sequence`, `Status`. |

### Bundles
| Object | SaltoID | Purpose / key fields |
| --- | --- | --- |
| `ProductRelatedComponent` | Id | Bundle parent→child line. `ParentProductId`, `ChildProductId`, `ParentProductRole` (Bundle), `ChildProductRole` (BundleComponent), `ProductComponentGroupId`, `ProductRelationshipTypeId`, `Quantity`, `IsComponentRequired`, `IsDefaultComponent`, `IsQuantityEditable`, `DoesBundlePriceIncludeChild`, `QuantityScaleMethod`, `Sequence`. |
| `ProductComponentGroup` | Id | Feature/group within a bundle. `Code`, `Name`, `ParentProductId`, `Sequence`, `MinBundleComponents`, `MaxBundleComponents` (min/max options selectable). |
| `ProductRelationshipType` | Id | Defines the kind of parent↔child relationship. |

### Pricing
| Object | SaltoID | Purpose / key fields |
| --- | --- | --- |
| `ProductSellingModel` | Id | How a product is sold/priced. `Name`, `SellingModelType` (OneTime/TermDefined/Evergreen), `PricingTerm`, `PricingTermUnit`, `DoesAutoRenewAssetByDefault`, `Status`. |
| `PricebookEntry` | Id | Price per product+selling-model. `Pricebook2Id`, `Product2Id`, `ProductSellingModelId`, `UnitPrice`, `IsActive`, `IsDerived`, `UseStandardPrice`. |
| `RateCard` | Id | Usage/rate pricing container. `Name`, `Type` (Base), `EffectiveFrom`. |
| `RateCardEntry` | Id | One rate. `RateCardId`, `ProductId`, `ProductSellingModelId`, `Rate`, `RateCardType`, `EffectiveFrom`, `Default/RateUnitOfMeasureId`, `Default/RateUnitOfMeasureClassId`, `RateUnitOfMeasureName`, `RateNegotiation`, `UsageResourceId`, `Status`. |
| `PriceBookRateCard` | Id | Links a rate card to a price book. |
| `PriceAdjustmentSchedule` | Id | Volume/attribute adjustment. `Name`, `AdjustmentMethod` (Range/…), `ScheduleType` (Attribute/Volume/Term), `Pricebook2Id`, `IsActive`, `EffectiveFrom`. |
| `PriceAdjustmentTier` | Id | One tier of a schedule (lower/upper bound, adjustment). |
| `AttributeBasedAdjRule` / `AttributeAdjustmentCondition` / `AttributeBasedAdjustment` | Id | Attribute-driven price adjustments (rule + conditions + adjustment). `AttributeBasedAdjRule`: `Name`, `AttributeCount`. |
| `BundleBasedAdjustment`, `ProductRampSegment`, `PriceBookEntryDerivedPrice` | Id | Package-discount, ramp, and derived-price constructs. |

### Qualification & lifecycle
| Object | SaltoID | Purpose / key fields |
| --- | --- | --- |
| `ProductQualification` | Id | When a product is allowed. `ProductId`, `ParentProductId`, `RootProductId`, `IsQualified`, `EffectiveFromDate`/`ToDate`, + custom criteria fields (e.g. `MinNumberOfEmployees__c`). |
| `ProductDisqualification` | Id | When a product is excluded. Same shape + `IsDisqualified`, custom fields (e.g. `Industry__c` picklist). |
| `ProductConfigurationFlow` | Id | Links a configurator Flow to products. |
| `ObjectStateDefinition` | Id | Lifecycle state machine on an object. `Name`, `ReferenceObject` (`salesforce.<Obj>.attr.label`), `ReferenceField` (`salesforce.<Obj>.field.<F>`), `AdditionalField`, `AdditionalFieldValue`, `IsActive`, `VersionNumber`. |
| `ObjectStateValue` / `ObjectStateTransition` / `ObjectStateTransitionAction` / `ObjectStateActionDefinition` | Id | States, transitions, and their actions. `ObjectStateValue`: `Name`, `ObjectStateDefinitionId`, `RefRecordLayoutFieldValue`. |

### Usage & units
| Object | SaltoID | Purpose / key fields |
| --- | --- | --- |
| `UnitOfMeasureClass` | **Code** | Class of units. `Code`, `Name`, `Type` (Usage/Count), `DefaultUnitOfMeasureId`, `BaseUnitOfMeasureId`, `Status`. |
| `UnitOfMeasure` | Id | A unit. `Name`, `UnitCode`, `Type`, `ConversionFactor`, `Sequence`, `UnitOfMeasureClassId`, `Status`. |
| `UsageResource`, `UsageResourceBillingPolicy`, `ProductUsageGrant` | Id | Usage metering resources & grants. |

---

## RLM-specific Salto behaviors & deploy quirks (from `packages/salesforce-adapter/src`)

- **UnitOfMeasure / UnitOfMeasureClass deploy as `Status='Draft'` then revert.** On add, the adapter forces `Status='Draft'`, deploys the class, then its units, then updates `Status` back to the intended value in a follow-up change (`custom_object_instances_deploy.ts`, `group_changes.ts`). Generated records should carry the real final `Status`; expect a two-step plan. A `UnitOfMeasure` only deploys after its `UnitOfMeasureClass` succeeds.
- **`ObjectStateDefinition` reference fields** (`ReferenceObject`/`ReferenceField`/`AdditionalField`) point at object/field metadata — they must resolve to elements already present.
- **Stable SaltoIDs:** because of the Name/Code overrides, RLM records have the *same* Salto ID across orgs (unlike CPQ) — cross-env compares are much cleaner. When generating new records, the Code/Name must be unique and deterministic or you create duplicates / collisions.
- **Broken outgoing references:** unfetched targets render `missing_<id>`; `User` uses `InternalId`. Don't invent element refs for objects outside `includeObjects`.

## Common change patterns
- **Add a bundle:** parent `Product2` → `ProductComponentGroup` (parent=bundle) → `ProductRelatedComponent` per child (parent/child product, group, quantity, required/default).
- **Add an attribute:** `AttributeDefinition` (Name key) → optional `AttributePicklist`(Code)+`AttributePicklistValue` → bind via `ProductAttributeDefinition` (or `ProductClassificationAttr` for classification-level) → group via `AttributeCategory`+`AttributeCategoryAttribute`.
- **Add pricing:** `ProductSellingModel` → `PricebookEntry` (product+model+price); usage via `RateCard`→`RateCardEntry`; adjustments via `PriceAdjustmentSchedule`(+`PriceAdjustmentTier`) or `AttributeBasedAdjRule` chain.

## Validation pitfalls
- **Dependency order on deploy:** UnitOfMeasureClass→UnitOfMeasure; AttributeDefinition before ProductClassificationAttr/ProductAttributeDefinition/AttributeCategoryAttribute; ProductClassification before its attrs; Product2 + ProductSellingModel before PricebookEntry/RateCardEntry/ProductRelatedComponent.
- **Code/Name uniqueness:** ProductClassification/AttributePicklist/UnitOfMeasureClass (Code) and AttributeDefinition/AttributeCategory (Name) are the identity — collisions merge or fail.
- **Native objects, but feature-gated:** these objects only exist in an RLM/RCA-provisioned org and only if the fetching user has the RLM permission set; otherwise they won't appear in a fetch at all.
