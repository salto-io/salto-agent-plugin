# CPQ → RLM migration (reference, loaded by the `/salto` router)

This is reference content. It is not registered as a slash command.

> [!NOTE]
> Invoked via: `/salto "migrate CPQ to RLM …"` (also: "rebuild CPQ in RLM", "move from CPQ to Revenue Cloud"). Flags: `[--source <cpq workspace>] [--target <rlm workspace>] [--area catalog|pricing|attributes|all]`.

## Prime directive — read before doing anything

Migrating Salesforce **CPQ (SBQQ)** to **RLM / Revenue Cloud Advanced (RCA)** is a **semantic, lossy REBUILD, not a copy**. The two products share almost no object model (only `Product2`, `Pricebook2`, `PricebookEntry`). Salesforce's own guidance is to rebuild, because capabilities are not 1:1.

Therefore this workflow:
- **Reads the CPQ source workspace read-only.** Never `salto fetch`/`deploy` against the source.
- **Surfaces every lossy/ambiguous decision and every gap for human review** before generating anything, and again at the end. Gaps are never silently dropped.
- **Generates RLM NaCL into the target workspace, runs a reviewer subagent, then a preview**, and **stops at a human gate**. It does **not** run a real (non-preview) deploy — the human approves the apply, which then goes through the standard `references/salto-deploy.md` workflow.
- **Stops to ask the user whenever a faithful rebuild needs a decision it cannot derive from the data — even in "auto" / non-interactive mode.** See the Clarification Gate below. Never fabricate selling models, terms, prices, or rule behavior to keep going.

## Step 0 — Load adapter knowledge

Read both, using `.`:
- `./adapters/salesforce/cpq.md` — source semantics (SBQQ/sbaa record shapes, fields, deploy quirks).
- `./adapters/salesforce/rlm.md` — target semantics (RLM objects, saltoID Name/Code keys, exact field API names, Draft-status quirk). **`rlm.md` is the source of truth for exact RLM field names** — this file maps at the object/concept level.

---

## Clarification Gate — STOP and ask the user (applies even in auto mode)

A faithful rebuild depends on decisions that **cannot be derived from the CPQ data**. Do **not** guess your way past them. After inventorying the source (Phase 1) and before generating NaCL (Phase 3), check the inventory against the triggers below; if any fire, **halt and ask the user**, naming the specific objects/areas and quoting the relevant counts/records. This stop is **mandatory even when invoked non-interactively / in "auto" mode** — surface the questions and wait. Proceed automatically only for the high-confidence area (catalog, bundles, attributes, basic pricing) **when its source data is complete**.

### Always-ask (strategic — ask once, up front)
1. **Faithful 1:1 rebuild, or redesign?** RLM models pricing/config differently; Salesforce guidance is "rebuild, not migrate as-is." This changes the whole approach.
2. **Scope** — whole catalog, or specific bundles/product lines? What is explicitly out of scope?
3. **Target org & definition of done** — which RLM env is the target, sandbox-first?, and is "done" = green `validate-local`, a real deploy, or a working RLM quote? (Only a deploy + test quote proves the rebuild actually configures/prices.)

### Ask-if-present (per problematic object/area — name them when you stop)
Trigger when the inventory contains these; each is lossy or has no clean target:

| If the source has… | Why it needs you | What to ask |
| --- | --- | --- |
| Subscription/`Renewable` products, any `ProductSellingModel` choice | CPQ rarely states the RLM selling-model **type or term**; "per month" vs annual vs one-time is a business call | Per product family: which RLM `SellingModelType` + term/billing cadence? |
| `PricebookEntry` missing or sparse (prices) | Prices may be excluded from fetch or set fresh in RLM; components are often bundle-priced | Where do real prices come from? Are components individually priced or bundle-included? |
| `SBQQ__PriceRule__c`/`PriceCondition__c`/`PriceAction__c`/`SummaryVariable__c` | Attribute-based adjustments map partially; **general field-writes & formula variables have no RLM target** | Which price rules are still required, and rebuild as attribute adjustments / re-implement / drop? |
| `SBQQ__ProductRule__c`/`ProductAction__c`/`ErrorCondition__c`, `SBQQ__ConfigurationRule__c` | Map unevenly to `ProductQualification`/`Disqualification`/`ProductConfigurationFlow` (flows aren't plain records) | Which selection/validation rules still matter, and how should they behave in RLM? |
| `SBQQ__ConfigurationAttribute__c` with `SBQQ__TargetField__c` | RLM attributes are catalog data, **not quote-field writers** — `TargetField` has no equivalent | Is the attribute still needed, and what replaces its field-write effect? |
| `SBQQ__CustomScript__c` / `SBQQ__CustomAction__c` (Apex/JS) | **No declarative RLM target** — manual Flow/Apex re-implementation | Keep, re-implement, or drop each? (Not an object rebuild.) |
| `SBQQ__QuoteTemplate__c`/`TemplateSection`/`TemplateContent`/`LineColumn`, `QuoteProcess__c` | Quote-doc & configurator UX — different RLM subsystem, no 1:1 map | In scope? If so, handled separately from this rebuild. |
| `sbaa__*` (Advanced Approvals) | **No RLM object model** | Rebuild via core Approval Processes / Flow Orchestration — in scope? |
| CPQ behavior flags (`Taxable`, billing, `AssetConversion`/`AssetAmendmentBehavior`, `NonDiscountable`, block/ramp) | Map to separate RLM setup (`TaxPolicy`/`BillingPolicy`/asset/ramp), not carried by default | Carry these semantics, or is catalog+bundle+price enough for v1? |
| A bundle option whose child is itself a bundle (nested) | RLM models multi-level bundles differently | Confirm intended nesting depth/behavior. |

When you stop, present it as: the **list of triggered areas/objects (with counts)**, the **specific questions**, and what you **can** proceed with now vs what is blocked. Record the answers and treat them as the mapping decisions for Phase 2.

---

## The CPQ → RLM mapping

Tags: ✅ clean · ⚠️ lossy / judgment call · ❌ no target (gap → manual). For exact RLM field API names, defer to `adapters/salesforce/rlm.md`.

### Area A — Catalog & bundles
| CPQ source | RLM target | Tag | Notes |
| --- | --- | --- | --- |
| `Product2` (+ `SBQQ__*` fields) | `Product2` | ✅ | The one object that survives. CPQ-only fields (`SBQQ__SubscriptionType__c`, `SBQQ__Optional__c`, `SBQQ__PricingMethod__c`, …) are **not** copied — their behavior is re-expressed via SellingModel / Classification / RelatedComponent. |
| `Product2.Family` / feature grouping | `ProductClassification` (+ `ProductClassificationAttr`) | ⚠️ | CPQ has no first-class classification. Synthesize one; saltoID key = **Code** → invent a deterministic Code (default: derive from `ProductCode`/`Family`). |
| `SBQQ__ProductOption__c` | `ProductRelatedComponent` | ⚠️ | `ConfiguredSKU__c`→`ParentProductId`, `OptionalSKU__c`→`ChildProductId`, `Quantity__c`→`Quantity`, `Required__c`→`IsComponentRequired`, `Selected__c`→`IsDefaultComponent`, `Number__c`→`Sequence`. Set `ParentProductRole="Bundle"`/`ChildProductRole="BundleComponent"` and `ProductRelationshipTypeId`→the Bundle→BundleComponent `ProductRelationshipType`. Also set `QuantityScaleMethod` and `DoesBundlePriceIncludeChild` (all live records populate them). **The parent `Product2` must have `Type="Bundle"`.** |
| `SBQQ__ProductFeature__c` | `ProductComponentGroup` | ⚠️ | `Name`→`Name`, `Number__c`→`Sequence`, `ConfiguredSKU__c`→`ParentProductId`, `MinOptionCount__c`→`MinBundleComponents`, `MaxOptionCount__c`→`MaxBundleComponents`; option→feature membership via `ProductRelatedComponent.ProductComponentGroupId`. |
| `Pricebook2` / `PricebookEntry` | same | ✅ | Survive; but RLM reads price through SellingModel + RateCard. |

### Area B — Pricing & discounts
| CPQ source | RLM target | Tag | Notes |
| --- | --- | --- | --- |
| Subscription/term pricing on `Product2` | `ProductSellingModel` (OneTime / TermDefined / Evergreen) | ⚠️ | Classify each product's pricing behavior into a selling model — a per-product modeling decision, not a copy. |
| `PricebookEntry` list price + selling model | `RateCard` / `RateCardEntry` + `PriceBookRateCard` | ⚠️ | RLM decomposes price into rate cards keyed by selling model. |
| `SBQQ__DiscountSchedule__c` + `SBQQ__DiscountTier__c` | `PriceAdjustmentSchedule` + `PriceAdjustmentTier` | ⚠️ | Closest structural match. `DiscountUnit__c`→adjustment type; tier bounds→tier lower/upper; `Type__c` Range/Slab→tier method. `AggregationScope__c`/`ConstraintField__c` have no clean target → flag. |
| `SBQQ__PriceRule__c` + `PriceCondition__c` + `PriceAction__c` + `SummaryVariable__c` | `AttributeBasedAdjRule` + `AttributeAdjustmentCondition` + `AttributeBasedAdjustment` | ⚠️❌ | Attribute-driven adjustments map partially. General-purpose PriceActions that **write arbitrary fields** / SummaryVariable formulas have **no RLM target** → flag each as manual. |
| Package discounts (`SBQQ__DiscountedByPackage__c`, percent-of-total options) | `BundleBasedAdjustment` | ⚠️ | Percent-of-total options need remodeling. |
| Block / ramp pricing | `ProductRampSegment` + `RateCardEntry` | ⚠️ | Only if CPQ used block/ramp. |

### Area C — Attributes & configuration rules
| CPQ source | RLM target | Tag | Notes |
| --- | --- | --- | --- |
| `SBQQ__ConfigurationAttribute__c` | `AttributeDefinition` (+ `ProductAttributeDefinition` + `AttributeCategory`/`AttributeCategoryAttribute`) | ⚠️ | Attribute→AttributeDefinition (saltoID key **Name**); product binding→ProductAttributeDefinition; display grouping→AttributeCategory. `SBQQ__TargetField__c` (writes a quote-line field) has **no equivalent** — RLM attributes are catalog data, not field-writers → flag. |
| Attribute picklist values | `AttributePicklist` (key **Code**) + `AttributePicklistValue` | ⚠️ | Invent stable Codes; map valueSet entries → picklist value rows. |
| `SBQQ__ProductRule__c` + `ProductAction__c` + `ErrorCondition__c` | `ProductConfigurationFlow` + `ProductQualification` / `ProductDisqualification` | ⚠️❌ | Selection/auto-add → RelatedComponent defaults or ConfigurationFlow; validation/exclusion → Qualification/Disqualification. Apex/JS (`SBQQ__CustomScript__c`/`CustomAction__c`) → **no declarative target**, manual flow rebuild. |
| `SBQQ__ConfigurationRule__c` (rule↔feature↔product binding) | `ProductConfigurationFlow` bindings | ⚠️ | Re-expressed in the flow + qualification model. |
| Config lifecycle/state | `ObjectStateDefinition` (+ Value/Transition/Action) | ⚠️ | New concept; usually set up fresh, not derived from CPQ. |

### Gaps — must appear in the plan AND the final summary, never silently dropped
- **Advanced Approvals (`sbaa__*`)** → **no RLM object model**. Inventory the sbaa rules/conditions/chains and emit manual-rebuild guidance using core Salesforce **Approval Processes / Flow Orchestration**. Do not auto-map.
- **Usage / consumption** → CPQ consumption objects are transactional (excluded from the source fetch). RLM `UsageResource` / `UsageResourceBillingPolicy` / `ProductUsageGrant` / `UnitOfMeasure(Class)` are adjacent but structurally unrelated. Document the target model + manual setup; do not auto-map.
- **General rule-engine logic & field-writes** → CPQ PriceAction field-writes, SummaryVariable formulas, CustomScript/CustomAction Apex, attribute `TargetField__c` writes. Flag each instance for human design.

---

## Workflow (knowledge / NaCL only — execution is delegated)

### Phase 0 — Preconditions
- Confirm `--source` ≠ `--target`; confirm the target is the RLM/dev workspace (the only deploy-eligible env) and the source is the CPQ workspace.
- Confirm both are valid Salto workspaces (`salto.config/workspace.nacl`).
- Confirm the target org actually has the RLM objects (a fetch shows `ProductClassification`, `AttributeDefinition`, etc.). **If the RLM objects are absent, STOP** — RLM isn't provisioned/permissioned; generating RLM records would fail to deploy.
- Refuse any request to fetch/deploy the CPQ source. Abort on any failed precondition.

### Phase 1 — Inventory the CPQ source (read-only)
- Enumerate SBQQ + sbaa record types and counts (`salto element list`, read source files directly).
- Build a per-area inventory: products, bundles (options/features), discount schedules, price rules, configuration attributes, product rules, sbaa approvals.
- Read representative records to capture real values/references. Nothing is written.
- **Run the Clarification Gate** (above): check the inventory against its triggers and collect the always-ask questions.

### Phase 2 — Mapping plan → human review (first gate)
- **Clarification Gate first:** if any Clarification-Gate trigger fired, **STOP and ask the user now** — list the triggered areas/objects with counts, ask the specific questions, and state what you can proceed with vs what's blocked. This stop is mandatory even in auto mode. Do not generate NaCL for a blocked area until answered.
- Apply the mapping above to the inventory. For each source element, list target RLM object(s), the field mapping, and a confidence tag (✅/⚠️/❌).
- Surface every ⚠️ judgment call (selling-model classification per product, invented Codes/Names, range-vs-slab tier method) and every ❌ gap.
- Present the plan and **wait for human approval before generating any NaCL.**

### Phase 3 — Generate RLM NaCL into the target workspace
- Write RLM records under the target `salesforce/Records/<Type>/`, following `adapters/salesforce/rlm.md` for exact field names and the conventions in `salesforce.md`/`cpq.md` (reference syntax, `_alias`).
- **Honor saltoID keys:** AttributeCategory/AttributeDefinition by **Name**; AttributePicklist/ProductClassification/UnitOfMeasureClass by **Code**. Invented keys must be **deterministic** (derive from CPQ `ProductCode`/`Name`) so re-runs are idempotent — record the scheme in the plan.
- **Honor dependency order** (emit so references resolve): UnitOfMeasureClass→UnitOfMeasure · AttributeDefinition / AttributePicklist(+Value) / AttributeCategory(+CategoryAttribute) · ProductClassification(+Attr) / ProductRelationshipType · ProductAttributeDefinition / ProductSellingModel · ProductComponentGroup→ProductRelatedComponent · RateCard→RateCardEntry→PriceBookRateCard / PriceAdjustmentSchedule→PriceAdjustmentTier / AttributeBasedAdjRule→AttributeAdjustmentCondition→AttributeBasedAdjustment / BundleBasedAdjustment · ObjectStateDefinition→Value/Transition/Action / ProductQualification·Disqualification / ProductConfigurationFlow.
- **Honor deploy-time quirks** (the adapter handles them; shape the data to cooperate): `UnitOfMeasure`/`UnitOfMeasureClass` get deployed `Status='Draft'` then reverted — generated records carry the intended final Status and a two-step deploy is expected; `ObjectStateDefinition` reference fields must point to already-emitted state values.

### Phase 4 — Reviewer subagent (quality gate)
- **Spawn a reviewer subagent** over the generated NaCL + the mapping decisions. It checks: correctness vs the mapping, dependency ordering, saltoID-key determinism/collisions, that references resolve, Draft-status handling, and that **no gap was silently dropped** (every ❌ from Phase 2 is represented as an explicit manual item, not omitted).
- Fix findings and re-run the reviewer until clean.

### Phase 5 — Preview (delegated)
- Hand the generated changes to the deploy workflow: read `./references/salto-deploy.md` and run its **preview** (`salto deploy --preview` / `deployment preview`) against the target. Loop back to Phase 3 on changeErrors (bounded iterations).

### Phase 6 — Human gate (hard stop)
- Present: the approved mapping, the generated-NaCL summary, the reviewer verdict, the preview plan, and the explicit gaps/manual list.
- **Stop here. Do not run a real deploy.** The human approves the apply, which proceeds via the standard salto-deploy workflow (branch → PR → SaaS preview → apply).

## Rollback / safety
- Before approval the live target is never mutated — "rollback" = discard the generated NaCL (the CPQ source is never touched).
- What makes this safe: source is read-only; all lossy/gap decisions are approved before generation and reaffirmed at the end; a reviewer subagent audits before any preview; the workflow halts at preview; deterministic saltoIDs make the rebuild idempotent and re-runnable.
