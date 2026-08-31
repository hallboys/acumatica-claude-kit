# GIQL & OData Generic Inquiries

Reading data through Generic Inquiries (GIs) over the OData feed, and the traps that make a
GI return nothing / the wrong columns. See the tag legend in [SKILL.md](./SKILL.md).

> If your project has a dedicated GIQL-authoring skill, defer clause-order/DAC-sourcing detail
> to it; this file is the cross-cutting *gotchas*.

---

### When contract REST can't do it, ride a GI `[UNIVERSAL]`
- Contract REST **cannot filter by a child-collection field** (e.g. an item's cross-reference
  `AlternateID`) — it throws **`CannotOptimizeException`** — and some inquiry-style tables aren't
  exposed as top-level entities at all.
- **Do:** expose a **Generic Inquiry** for that read and query it over OData. This is the standard
  escape hatch for search/lookup/work-list reads.

### On a **list** GET, an expanded sub-collection is dropped unless it's also in `$select` `[UNIVERSAL]`
- `$expand=Orders` alone returns `Orders: []` on a list read. You must **also** name it in
  `$select` (`$select=…,Orders&$expand=Orders`) to get the rows.
- *Verified live: 25R2.*

### A **parameterized** GI returns **0 rows** when queried by its BASE name — parameters bind only through `_WithParameters` `[UNIVERSAL]`
- Querying `/api/odata/gi/<GI>` for a GI that declares parameters returns **empty, with HTTP 200 and
  no error** — the parameters stay NULL, so the WHERE clause fails. This is a silent wrong answer,
  not a failure, which is what makes it dangerous.
- **Parameters ARE bindable, and Acumatica documents it.** A parameterized GI is exposed as a
  *separate* **`_WithParameters` FunctionImport** and addressed by that distinct name with the args in
  parentheses: `/api/odata/gi/<GI>_WithParameters(Warehouse='WHOLESALE')`, or with aliases
  `..._WithParameters(Warehouse=@1)?@1='WHOLESALE'`. The `$metadata` service document lists an
  `EntitySet` for the plain form and a `FunctionImport` with the `_WithParameters` postfix for the
  parameterized one — which is also the reliable way to *detect* that a GI is parameterized.
  Source: *Generic Inquiry Access Through OData: Data Retrieval* and *…: General Information*.
- **Do:** for a consumer that can't or won't supply parameters (and for any AI/agent consumer, which
  cannot detect the silent-empty case), publish a **parameter-free** copy for OData, or read the
  underlying **contract entity**. For a deliberate caller that knows the parameters, use
  `_WithParameters` — it is supported, not a workaround.
- **Don't** conclude "OData can't bind GI parameters" from a probe that only tried `$filter` on
  parameter names, URL query strings, or function-call syntax against the **base** GI name. That
  tests the wrong path and is how this entry originally got the mechanism wrong.
- *Verified live: 25R2. Documented in both the 25R2 and 26R1 doc sets (checked 2026-08-31).*

### GI **column names differ between the raw OData feed and the MCP** — trust the feed `[CLAUDE]` / `[UNIVERSAL]`
- The Acumatica MCP may render a GI column under a different name than the **raw OData feed** your
  code actually receives (e.g. a cost-code id shown one way by the MCP, delivered under a plainer
  name in the feed). **Trust the raw feed**; confirm real column names by reading the feed, not the MCP.
- **Mechanism (2026-08-31):** the two names have different origins. The feed's property name is
  derived from the field's **display name** (see the naming-rule entry below). An MCP/tooling label
  may instead come from the GI design's **Caption** column, which is only an *override* and is NULL
  for most columns — so tooling that pairs design rows to properties has to do it **positionally**,
  and a mis-paired row shows a plausible-but-wrong name. A mismatch is therefore a symptom of a
  mapping failure, not a rename.

### A `$select` projection can be **SLOWER** than no projection on a delegate-heavy detail view `[UNIVERSAL]`
- The reflex "project only the columns you need, it'll be cheaper" can **invert** on entities whose detail
  view is full of computed / BQL-delegate fields. Measured on one ~500-line document via a keyed GET:
  **unprojected ≈ 0.76 s, the same GET with a `$select` ≈ 1.4 s** — the projection nearly doubled it,
  because naming fields forces per-field evaluation across the whole detail set instead of letting the
  export path do its bulk thing.
- **Do:** on these entities, **measure both** rather than assuming. Keep `$select` for the cases it
  genuinely helps (narrowing a *header* read away from an expensive `$expand`, which is a real and large
  win), and don't reach for it reflexively on detail rows. Note also that projecting can *break* a read
  outright when a field isn't a bindable property (some note fields raise a key-not-found), so an
  unprojected read is often both faster and safer here.
- *Verified live: 25R2, 2026-08.*

### `$filter` on a **CALCULATED** GI column returns an **empty-body HTTP 200** `[UNIVERSAL]`
- Acumatica documents that you cannot sort or filter by fields the system calculates with a
  **formula** (*Generic Inquiries and OData: Preparation of an Inquiry for Exposure*). What it does
  **not** say is how the violation is reported: the response is a **body-less 200** — not a 400, not
  an OData error. `response.json()` on it throws a raw parser message, and any code that treats an
  empty result as "no rows matched" reports a confident wrong answer.
- Reproducible shape: a filter on a stored column works; adding `and <ExpressionColumn> ne 0` to the
  same filter returns the empty body.
- **Do:** filter only on **stored** columns (keys, dates, statuses, codes) and apply conditions on
  calculated columns to the returned rows yourself. Identify them before filtering — a calculated
  column is one whose Results Grid row is a `=…` expression; `acumatica_describe_inquiry` flags them
  as `calculated: true`.
- **Don't** treat a body-less 200 as an empty result set: standard OData returns `{"value":[]}` for a
  genuinely empty result, so a missing body is anomalous and means the query never really ran.
- *Verified live: 25R2 (reproduced three times). Documented limitation, undocumented failure mode.*

### GI OData property names come from **display names** — the *order* of columns is undocumented `[UNIVERSAL]`
- **Documented naming rule** (*Preparation of an Inquiry for Exposure* → "Supporting the OData
  Specification"): a property name is generated from the field's **display name** in an English
  locale — left as-is if already valid, prefixed with `_` if it starts with a digit, and with invalid
  symbols such as spaces stripped (`Account Name` → `AccountName`). This is why feed property names
  often resemble neither the DAC field name nor the grid header.
- **Documented:** the EntityType always carries the **key fields of the tables used by the GI** as
  `PropertyRef`, *even when those keys were never added to the Results Grid* (*GI Access Through
  OData: General Information*). Expect key columns you did not ask for.
- **NOT documented — confirm empirically, per instance:** (a) the **order** of properties, including
  that result columns which are also keys appear **first** and non-result keys are appended at the
  end; (b) that remaining columns follow the design's **Sort Order** (which can differ from Line
  Number) and that **inactive** rows are skipped; (c) how **duplicate** names are disambiguated (a
  `_2`-style suffix appears, but which column keeps the bare name is not stated); (d) that setting
  the Results Grid **Caption** changes the property name — Caption is documented only as the caption
  used *on the form*.
- **The display name is not available from the GI design tables.** `GIResult.fieldName` exists but is
  a **virtual (unbound) field** — Acumatica's own error is `Filter on '{0}' is not allowed because it
  is a virtual field` — so it is null over OData and cannot be read back. Any tooling that needs to
  know *which* design row became *which* property must infer it positionally and should **refuse**
  rather than guess when the answer is ambiguous: a wrong pairing shifts every later column silently.
- **Do:** treat `$metadata` as the only authority for property names and order. Query a few rows and
  confirm each property returns the kind of value you expect before relying on a mapping.
- *Verified live: 25R2; naming and key rules documented in both the 25R2 and 26R1 doc sets
  (checked 2026-08-31).*

### `getOData` must follow `@odata.nextLink` `[UNIVERSAL]`
- OData GI feeds **page**. A reader that ignores `@odata.nextLink` silently truncates. Accumulate all
  pages (a `$top` caller intentionally gets one capped page).

### Column names are **case/spelling-exact** and GIQL `WHERE` matches **DAC codes**, not labels `[UNIVERSAL]`
- Filter/`WHERE` on the stored **code** value (e.g. an order type `'RO'`), not the UI **label**
  (`'Normal'`). A label-based filter matches nothing.

### OData GI datetimes are **true UTC** (`…Z`) — the raw feed does NOT localize `[UNIVERSAL]` (display TZ `[TENANT]`)
- A datetime column over the **raw OData GI feed** comes back as a **true UTC instant** stamped `Z`
  (e.g. an 8 AM Eastern appointment reads `…T12:00:00Z`). The Acumatica **screen and the GI's
  *interactive* UI localize** it to the instance display timezone, so *they* show the right wall time —
  but your code receives raw UTC and must convert itself.
- **Trap:** pulling the hour/date without converting — e.g. `getHours()` on a runtime whose local zone
  is already UTC (a Cloudflare Worker, many containers) — renders **every** row off by the UTC offset.
  It looks correct in the GI UI and stays hidden until a value is compared against the screen.
- **Do:** treat GI datetimes as UTC; convert to the instance display timezone for display and back to
  UTC on write, as **exact inverses** so a round-tripped write lands on the slot it started from. The
  display zone is a single instance-wide value (`[TENANT]`; confirm it's not per-branch/per-record).
- *Verified live: 25R2, 2026-07.*

### `substringof` / contains filters can silently match nothing `[UNIVERSAL]`
- Text-contains filters over GI feeds are finicky (field must be a queryable string column). If a
  `substringof`/`contains` returns nothing where you expect hits, verify the column is exposed as a
  filterable string and try an exact `eq` first to isolate the issue.

### Caching an **empty** GI result poisons the cache `[UNIVERSAL]` (app-side lesson)
- If your integration caches reference/GI reads, a run against a mis-mapped or ungranted GI can cache
  an **empty result as a hit** — future requests keep returning empty until the TTL expires.
- **Do:** after fixing a GI mapping/grant, **flush the cache** for that key; and prefer a cache layer
  that does **not** cache empty results (so a transient miss self-heals next request).

### `InventoryQuantityAvailable` has no per-location breakdown `[UNIVERSAL]`
- The `InventoryQuantityAvailable` inquiry returns only `InventoryID` + `QtyAvailable` — no per-warehouse/
  per-location rows. For bin-level on-hand (stock check by location, cycle counts, put-away), ride a **GI**
  over the location-contents inquiry instead.
- *Verified live: 25R2.*

### The Acumatica MCP reads a STALE / divergent snapshot — don't verify writes through it `[CLAUDE]`
- The Acumatica MCP server can lag the live tenant: `LastModifiedDateTime` may not advance after a write,
  and fields can read differently than what the API just wrote. It's fine for **schema/shape exploration**,
  but **verify writes by reading them back through the same contract API you wrote with**, not the MCP.
- The MCP connection is also **per-session** — it can be dead in one client session while another works
  (separate sockets); a "not connected" / "token refresh failed" usually needs a session restart.
- The MCP also **localizes datetimes** while the raw feed delivers **true UTC** (see the datetime entry
  above) — a time that reads as local wall-clock in the MCP is UTC in the feed your code consumes.
  Confirm datetime *representation/offset* from the raw feed, not the MCP, or you'll bake in a wrong
  timezone assumption (this masked a bug where every row rendered off by the UTC offset).

### Column set of a GI is `[TENANT]` — confirm per instance
- A GI's exact **name and column set** are instance configuration. Never hardcode GI names in code —
  read them from config/env. Confirm the columns live per tenant before depending on them.
