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

### The scheduled **Update IN** posting **permanently disables `CorrectShipment`** — the correction window is the schedule gap `[UNIVERSAL]` (cadence `[TENANT]`)
- The scheduled "Update IN" job posts a confirmed SO shipment's inventory **Issue**: the shipment's
  `Orders[]` gains `InventoryDocType: "Issue"` + an `InventoryRefNbr`, and status moves
  **Confirmed → Completed**. From that moment the **Correct Shipment** action on the shipment screen
  is **disabled/greyed for everyone** — including in the Acumatica UI, not just via the API.
- Practical consequence: with an hourly Update IN schedule the window to un-confirm is **sub-hour**
  (observed: shipments confirmed minutes before a batch were locked by it) — so a correction path is
  dead exactly when problems are usually noticed (later that day).
- **Do:** don't build an integration "undo a confirm" feature on `CorrectShipment` — it only works
  inside the window. **After posting, the sanctioned correction path is an inventory Adjustment**,
  not `CorrectShipment`. If a tenant needs more correction slack, the lever is the **Update IN
  schedule** (ERP config, `[TENANT]`), not API code.
- *Verified live: 25R2 Construction, 2026-08.*

### Long-op **action polling**: strip the endpoint prefix; one long-op per session `[UNIVERSAL]`
- After invoking an action that returns a long-running-operation `Location`, poll it — but **strip
  the `/entity/{endpointName}/{version}/` prefix** from that Location first, and **wait between polls**.
- A single reused session allows **one long-op at a time**; serialize them.

### List-GETs on entities with BQL-delegate detail fields **500 with CannotOptimizeException** `[UNIVERSAL]`
- Some entities (seen on documents with computed/delegate detail fields) cannot serve a `$filter`
  list GET — they throw **`CannotOptimizeException`**.
- **Do:** use a **keyed GET** (`/Entity/{key}`) instead of a `$filter` list; for search/lookup by a
  non-key field, ride a **Generic Inquiry** (see [giql-odata.md](./giql-odata.md)).
- `CannotOptimizeException` is one member of a **family**: the same filter binder 500s with *"…is not a
  single value"* (filter reaches a child collection), *"Type conversions not supported"* (computed numeric
  such as a document total), *"The given key was not present"* (field the contract view doesn't bind).
  Classify by the binder namespace in the error (`PX.Api.ContractBased.OData…` /
  `Microsoft.Data.OData.Query`), not one message string.
- There is also a **silent mode**: HTTP 200 `[]` although matching records exist (seen with `substringof`
  on an unbound text field of the purchase-order header) — indistinguishable from a genuine empty result.
  Seen on purchase orders, shipments and physical-inventory counts; a **keyed** filter (`$top=1`) still works.
- **Do:** treat an empty non-key filter result on these entities as *unverified*, not "no such record";
  search through a GI. *Verified live: 25R2, 2026.*

### Contract REST: `substringof(…) eq true` returns **`[]` silently** — send the bare function `[UNIVERSAL]`
- `substringof('X', F) eq true`, `startswith(…) eq true`, `endswith(…) eq true` → **HTTP 200, empty array,
  no error**. The bare `substringof('X', F)` returns the matching rows. `eq true` is valid OData v3 and
  clients/models append it habitually, so partial-text searches silently "find nothing".
- Not a URL-encoding problem (parenthesis / `+` encoding was ruled out live).
- Negation has no known working form: `not substringof(…)` → **500**; `eq false` is unverified.
- **Do:** strip `eq true` from boolean string functions before sending. The GI feed is a different (v4)
  dialect — see [giql-odata.md](./giql-odata.md).
- *Verified live: 25R2, 2026.*

### A `$top=1` probe is **not** cheap on a delegate-heavy entity `[UNIVERSAL]`
- `$top=1` bounds the rows **returned**, not the work done to produce them. On an entity whose
  detail view is full of computed / BQL-delegate fields (project *budget*-style entities are the
  ones to watch), a one-row existence/grant probe measured **~23 s**.
- **Consequence:** a readiness check that probes each entity once is dominated by its worst entity —
  the same sweep measured **~35 s total**. On a single serialized session that every caller shares
  (see [auth-sessions.md](./auth-sessions.md)), that reads to an operator as "the app is hung", and
  on a request path it is a real stall.
- **Do:** keep these probes off request paths and cache the verdict; expect a full readiness sweep to
  take tens of seconds rather than treating it as a fault. Log **per-probe timings** so the expensive
  entity is named rather than guessed at, and where one dominates, prefer a keyed GET of a known
  record over `$top=1`.
- *Verified live: 25R2, Construction edition, 2026-09 (~23 s single-row probe, ~35 s full sweep).*

### `$orderby` can be **silently ignored** on heavy entities — a small `$top` then drops the rows you want `[UNIVERSAL]`
- On some list-heavy entities (those with computed / BQL-delegate fields — e.g. the **Project** entity),
  the contract endpoint **ignores `$orderby`** and returns rows in a **fixed ascending key order**.
  Combined with a broad `substringof` filter and a small `$top`, you get the **lowest-key matches only** —
  a recently-created, high-key record the user actually wants is **silently dropped past the cap**, so a
  typeahead "returns nothing" / the-wrong-rows even though the record exists and the filter matches.
- A **selective** query (full key value) still works because it fits under the cap — which masks the bug
  in testing and makes it look data-specific.
- **Do:** don't rely on server-side ordering for these. Fetch a **wide window** and **sort / rank in the
  app layer** (newest-key-first for time-ordered ids, or a relevance rank: exact > prefix > substring),
  then cap. Applies to any high-cardinality typeahead (items, vendors, tasks, locations), not just one.
- *Verified live: 25R2, 2026-07.*

### The **file-attach path is the record's own `files:put` link template** `[UNIVERSAL]`
- To attach a file, use the record's `_links["files:put"]` template
  (`/files/{Graph}/{node}/{guid}/{filename}`). The guessed by-id form
  `PUT /{Entity}/{id}/files/{name}` **404s**.
- **Gotcha:** `files:put` keys attachments by **filename** — uploading two files with the **same
  name overwrites** (only the last survives). Give each file a **unique name** when attaching several.
- **Readback gotcha:** listing with `?$expand=files` returns each name **prefixed with the record**
  (`<Screen Name> (<RefNbr>)\<filename>`) even though the name you `PUT` was bare. So any logic that
  keys off the existing filenames — "how many `report-N.pdf` are already attached, so what's next?" —
  matches **nothing** and hands out the same name forever, silently overwriting. **Compare on the
  basename**, not the returned string.
- *Verified live: 25R2, 2026-08.*

### There is no REST file delete; only `UploadFileMaintenance.DeleteFile` removes external blobs, and only conditionally `[UNIVERSAL]`
- Contract REST has **no file delete** (`DELETE files/{id}` is reported to fail), and re-attaching creates
  a **new FileID**, breaking anything that pointed at the old one. *(docs/community; unverified live)*
- `DeleteFile(Guid?)` (behind *Delete File* on SM202520 / *Delete* on SM202510) removes external blobs only
  when *Allow Saving Files* is on and web.config `DisableDeleteOnExternalFileStorage` isn't true. It does
  **not** check access rights or links (the docs say SM202520 acts only on unlinked files; the code doesn't
  check), doesn't delete `UploadFileTag` rows, and opens no transaction of its own.
- The **record-delete cascade** (`PXNoteAttribute`) raw-deletes files linked only to the deleted record and
  **never removes external blobs**; it runs per file inside the owner's transaction, so a parent with
  thousands of attachments can hit *Execution Timeout Expired*.
- An empty **Entities** tab on SM202510 doesn't mean the file is unlinked — query `NoteDoc`.
  `UploadFileRevision.Size` is in **KB** (rounded up).
- A data provider (SM206015) whose `FileName` is the sentinel `<EmptyFileName>` uses the **most recently
  created attached file**; the screen shows the resolved name, the DB keeps the sentinel.
- *Verified: code reading of a decompiled 25R2 build (25.201.0213), 2026-10. Not exercised live.*

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
- **Diagnostic signature:** a dependent lookup that **returns nothing for a KNOWN-VALID parent** (e.g. a
  task or cost-code picker empty for a record that provably has children) is usually a **swallowed 403 on
  the child entity's grant**, not a query/data bug — UIs routinely render a failed lookup as "no results".
  Confirm the exact query returns data under an **admin** account, then check the **service account's**
  grant on that child entity. Sibling entities being granted does **not** imply the related one is (grants
  are per-entity, one at a time).

### Costing fields on a count line are **empty until the count is finished** `[UNIVERSAL]`
- A physical-inventory line's **unit cost and extended variance cost are blank while the count is in
  progress** and are filled when the count is **finished/completed**. Confirmed by comparing the same
  document in two states: an in-progress count had **0 of N** counted lines carrying a unit cost, a
  completed one had **all** of them.
- Why it bites: any logic that grades or prioritizes lines *during* counting — a variance-value
  threshold, a review queue sorted by dollar impact — reads the field at exactly the point in the
  lifecycle where it does not exist. Worse, it reads as **absent (`{}`), not `0`**, so a naive
  "parse to a number, default 0" turns *cost unknown* into *costs nothing* and the distinction vanishes:
  costed items get silently classed as free.
- **Do:** for anything evaluated mid-count, source cost from the **item master** instead (see the next
  entry), and keep `null`/absent distinct from `0` all the way through the logic.
- *Verified live: 25R2, 2026-08.*

### A stock item has **no single "unit cost"** — pick the basis from its valuation method `[UNIVERSAL]`
- There is no `UnitCost` property on the item. There are several: **`AverageCost`**, **`LastCost`**,
  **`MinCost`**, **`MaxCost`**, **`CurrentStdCost`** (plus pending/last standard variants), and a
  **`ValuationMethod`** that says which one the item is actually valued at.
- **Do:** choose by the item's own `ValuationMethod` — *Average* → `AverageCost`, *Standard* →
  `CurrentStdCost`, *FIFO/Specific* → `LastCost` as the closest proxy — and **fall through to whichever
  field is populated** rather than reporting a costed item as free. Treat "all of them zero/absent" as
  **unknown**, not as $0; those are different facts and usually deserve different handling.
- Which method a given catalogue uses is `[TENANT]`; that the choice must be *per item* is not — a
  catalogue can mix methods.
- *Verified live: 25R2, 2026-08.*

### Physical-inventory entity names are non-obvious `[UNIVERSAL]`
- The count entity is **`PhysicalInventoryCount`** — a bare `PhysicalInventory` entity does **not** exist.
- **Finishing a count is on a *different* entity:** `PhysicalInventoryReview` → action `FinishCounting`,
  then `CompletePhysicalInventory` posts the variances. `Finish` on the count entity 404s. (List-GET on
  `PhysicalInventoryCount` also `CannotOptimize`s — use a keyed GET.)
- **The two are the SAME record, projected differently.** A keyed GET on either returns the *identical*
  header `id` GUID and the *identical* detail-row GUIDs, so a row id read from one is valid in a write to
  the other. But they expose **different field sets** — only the review-side projection carries the
  header's warehouse / freeze date / a persisting note, and unit-cost + variance columns on the lines —
  and even the **bin field is named differently between them** (`Location` vs `LocationID`), per the
  per-entity naming trap at the top of this file. Read from whichever projection has the fields; write
  through the one that owns the operation.
- *Verified live: 25R2.*

### User-defined **attributes**: write the value ID, read back the LABEL; Datetime attributes store **date only** `[UNIVERSAL]` (which attributes exist `[TENANT]`)
- A contract-REST write takes the attribute's **value ID**; the read returns the **label** (you write a short code,
  you read back its display text). Compare read-backs against labels. A GI reading the answers table
  surfaces the ID instead.
- **Datetime-type attributes keep only the date**: a written `14:22` reads back `00:00:00` in four input
  formats. Don't use them for dwell/elapsed time.
- A document type with **no class** (e.g. shipments) has nowhere to hang an attribute default, so every
  untouched or pre-existing record reads `null`. A GI/report on the attribute needs a "date ≥ go-live"
  filter, or history reads as "untouched".
- Reading: `$custom=Document.Attribute<ID>` on contract REST; in a GI select `<DAC>.Attribute<ID>`
  directly, no answers-table/NoteID join needed.
- *Verified live: 25R2, 2026-08-26 (ID-vs-label, date-only, null default) and 2026-06-30 (direct `Attribute<ID>` select + `$custom` read).*

### Inventory documents have a **header (Financials-tab) branch separate from the line branch** — set both `[UNIVERSAL]`
- IN documents (adjustment / issue / receipt) carry a **per-line branch** (drives the line's inventory
  transaction) and a **document/header branch** (drives the **GL batch**). An unset header branch defaults
  to the **signed-in (service) user's branch**, whatever the lines say — the GL posts to the wrong branch
  while the lines look right.
- Testing with a warehouse in the service account's default branch **masks** this.
- The header branch field is **not in the stock Default endpoint** for these entities; extend the endpoint.
  The per-line branch field name differs per entity (`BranchID` on adjustment lines, `Branch` on issue
  lines, a `custom` transactions field on receipts). `TransferOrder` has **no branch field** (derived from
  the from/to warehouses).
- **Do:** stamp header and line branch from the warehouse, server-side; verify with a warehouse outside the
  service account's home branch.
- *Verified live: 25R2, 2026-06.*

### `PX-CbApiBranch` header sets the session branch per call — works on **create**, not to re-branch `[UNIVERSAL]`
- Documents whose graph defaults `BranchID` from the session's current branch (and whose endpoint can't map
  a branch field) land in the **service account's sign-in branch**, invisible to users without that branch.
- The per-request header **`PX-CbApiBranch: <branch CD>`** (Integration Development Guide → "Change the
  Business Date or Current Branch") makes the create land in that branch. Unknown branch, or one the user
  lacks → **500** "The user does not have access to the X branch".
- It does **not** re-branch an existing record: an update PUT with the header, a `custom` `BranchID`
  write, or both → 200, unchanged. Read back with `$custom=Document.BranchID` (`$select=BranchID` 500s).
- **Do:** resolve the branch server-side and send the header on create.
- *Verified live: 25R2, 2026-10-22 (requisition request).*

### Raising a shipment line's `ShippedQty` from **0 → N** needs `LocationID` (+ `WarehouseID`) `[UNIVERSAL]`
- Reducing `ShippedQty` (including to 0) works with the qty alone. **Raising** it from 0 returns **422**
  unless the same PUT also sends `LocationID` + `WarehouseID` (the ERP rebuilds the line's split). Same for
  raising a non-stock kit line 0 → 1.
- **Do:** always send location + warehouse on any shipment-line qty write.
- *Verified live: 25R2, 2026-06.*

### Field Service **Appointment** writes: schedule, staff reassign, hidden prerequisites `[UNIVERSAL]`
- **Schedule:** a base-URL PUT with keys (`ServiceOrderType`, `AppointmentNbr`) + `ScheduledHandleManually:
  true` (stops the recompute) + `ScheduledStartDate`/`EndDate` (UTC date at `T00:00:00Z`) and
  `ScheduledStartTime`/`EndTime` as **`1900-01-01Thh:mm:ssZ` UTC** epoch-datetimes. Works on stock Default.
- **Reassigning staff:** an in-place update of a Staff line's `StaffMember` returns 200 and is **silently
  ignored**. Delete the old line by `id` and add a new one (`StaffMember`, `PrimaryDriver`,
  `StaffType: "Employee"`, `CostCode`) in **one** PUT.
- **Since 25R2 a Staff line requires a Cost Code**, and the API does **not** apply the order-type default
  the UI applies → 500 "'Cost Code' cannot be empty…" inside "Operation failed". Supply it explicitly.
- **The acting user must be linked to an Employee** ("User must be an Employee to use current screen"), so a
  generic service account can't write appointments; use per-user auth.
- *Verified live: 25R2, 2026-07.*

### **Project Quote** is not on the Default contract endpoint; customer visibility lives on `Customer` `[UNIVERSAL]`
- Default `25.200.001` exposes **no** `ProjectQuote` / `SalesQuote` / `PMQuote` / `Quote` entity (only
  `ProjectProperties.QuoteNbr`). Writing Project Quotes (PM304500) needs a **custom endpoint** — ship it in
  a customization project so every tenant gets the same shape.
- **`RestrictVisibilityTo` is on the `Customer` entity**; a business account can't be restricted, and
  prospects (no `Customer` record) have no restriction to read.
- *Verified live: 25R2, 2026-07/08 (entity absence, `RestrictVisibilityTo` placement).*
