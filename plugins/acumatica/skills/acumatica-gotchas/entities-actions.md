# Entities, Fields & Actions

Contract-based REST entity/field/action traps. See the tag legend in [SKILL.md](./SKILL.md).

---

### Field names are inconsistent **per entity** — validate against the live endpoint `[UNIVERSAL]`
- The "same" concept is named differently on different entities. Real examples: **Inventory
  Adjustment** uses `WarehouseID` / `LocationID`, while **Inventory Issue / Receipt** use
  `WarehouseID` / **`Location`** (no `ID`). Some headers expose `Branch`, others don't expose it
  at all.
- **Do:** never assume a field name transfers across entities. Confirm each entity's real schema
  against the deployed endpoint (or the schema/describe tooling) before writing.
- *Verified: 25R2 contract endpoint.*

### The release action is the classic PXAction **`Release`** for all IN/PO/Transfer docs `[UNIVERSAL]`
- Do **not** guess entity-specific names like `ReleaseInventoryAdjustment` / `ReleaseTransferOrder`
  — they 404 ("can't find action"). It is plain **`Release`** for InventoryAdjustment,
  InventoryIssue, InventoryReceipt, PurchaseReceipt, TransferOrder.
- Shipments: **`ConfirmShipment`** (confirm), `CorrectShipment` / `Correct` (correct).
- Physical Inventory **finish is on a different entity**: `PhysicalInventoryReview` →
  action **`FinishCounting`**, then `CompletePhysicalInventory` posts variances. `Finish` on the
  count entity 404s.
- *Verified live (invoke-tested): 25R2, 2026.*

### Long-op **action polling**: strip the endpoint prefix; one long-op per session `[UNIVERSAL]`
- After invoking an action that returns a long-running-operation `Location`, poll it — but **strip
  the `/entity/{endpointName}/{version}/` prefix** from that Location first, and **wait between polls**.
- A single reused session allows **one long-op at a time**; serialize them.

### List-GETs on entities with BQL-delegate detail fields **500 with CannotOptimizeException** `[UNIVERSAL]`
- Some entities (seen on documents with computed/delegate detail fields) cannot serve a `$filter`
  list GET — they throw **`CannotOptimizeException`**.
- **Do:** use a **keyed GET** (`/Entity/{key}`) instead of a `$filter` list; for search/lookup by a
  non-key field, ride a **Generic Inquiry** (see [giql-odata.md](./giql-odata.md)).

### The **file-attach path is the record's own `files:put` link template** `[UNIVERSAL]`
- To attach a file, use the record's `_links["files:put"]` template
  (`/files/{Graph}/{node}/{guid}/{filename}`). The guessed by-id form
  `PUT /{Entity}/{id}/files/{name}` **404s**.
- **Gotcha:** `files:put` keys attachments by **filename** — uploading two files with the **same
  name overwrites** (only the last survives). Give each file a **unique name** when attaching several.
- *Verified live: 25R2.*

### Mandatory `Project` on Inventory documents; non-project uses a sentinel code `[UNIVERSAL]` (code value `[TENANT]`)
- Every IN document requires a **Project**. Non-project transactions use a **sentinel project code**
  (commonly `X`, but treat the actual value as `[TENANT]`). Send Project/Task/CostCode only when set,
  else let the ERP default the sentinel.
- *Verified live: 25R2.*

### Reason codes are **usage-restricted per document type** `[UNIVERSAL]` (which codes exist `[TENANT]`)
- A reason code has a **usage** (Adjustment / Issue / Receipt / Transfer). Using a code whose usage
  doesn't match the document type is **rejected** ("usage type … does not match the document type").
- **Example trap:** a "job return" reason with **Receipt** usage cannot be used on an **Issue**-type
  return document — you need an Issue-usage reason. Match usage to the doc, always.

### PurchaseReceipt lines need `POOrderType`; `Location` is optional `[UNIVERSAL]`
- Receipt lines need **`POOrderType`** (e.g. `"Normal"`) to resolve the PO link. **Location is
  optional** — forcing a specific bin **500s** on warehouses that lack that bin.

### PO `OrderNbr` is **zero-padded** to a fixed width `[UNIVERSAL]` (width `[TENANT]`)
- The stored order number is padded (e.g. `PO017606`, not `PO17606`). Typed/looked-up values must
  match the **padded** form. Auto-padding a user's input is unsafe unless you know the width.

### A padded `PO0…` number is **NOT** a Normal-vs-drop-ship discriminator `[UNIVERSAL]`
- Both normal and **Project Drop-Ship** POs can have padded `PO0…` numbers. Only the PO **`Type`**
  field is authoritative. Drop-ship POs are job-site delivered and **not receivable via contract-REST
  `PurchaseReceipt`** — scope receivable-PO queries by `Type eq 'Normal'`.
- **Note:** a Normal PO's `OrderType` **code** may be `'RO'` (not `'RG'`); GIQL `WHERE` matches DAC
  **codes**, not UI labels. *Verified live: 25R2.*

### `EmployeeName`, not `Name`, on the Employee entity `[UNIVERSAL]`
- Selecting `Name` on the employee entity errors; the field is **`EmployeeName`**.

### A DAC field is not **settable** via contract REST unless the endpoint/screen exposes it `[UNIVERSAL]`
- A field existing on the DAC does **not** mean you can write it. If the endpoint/screen doesn't
  expose it (e.g. `BranchID` on some documents), `$select`-ing or setting it **500s** ("key not
  present"). Extend the endpoint to expose a field before relying on writing it.
- *Verified live: 25R2.*

### The service account needs **explicit per-form / per-GI / per-entity grants** `[UNIVERSAL]`
- Access is granted **one resource at a time** — each form (e.g. the PO form, the Employee form) and
  **each GI separately**. A missing grant → **403** (or 403 on OData once Basic auth itself is accepted).
- **Do:** when a call 403s, suspect a missing grant on that specific resource before anything else.
