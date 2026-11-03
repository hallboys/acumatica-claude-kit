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

### A **parameterized** GI queried by its BASE name silently ignores its parameters — bind them through `_WithParameters` `[UNIVERSAL]`
- Querying `/api/odata/gi/<GI>` for a GI that declares parameters runs it **with no parameter values,
  HTTP 200, no error**. What comes back depends on how the design uses each parameter: a WHERE that
  compares against the NULL parameter returns **0 rows**; one written as "blank = all" returns
  **every row** (an unfiltered result that looks plausible). Either is a silent wrong answer.
- **Parameters ARE bindable, and Acumatica documents it.** A parameterized GI is exposed as a
  *separate* **`_WithParameters` FunctionImport**:
  `/api/odata/gi/<Import>_WithParameters(Warehouse='WHOLESALE')`, or with aliases
  `..._WithParameters(Warehouse=@1)?@1='WHOLESALE'`. In `$metadata`, the `FunctionImport` name is the
  GI name with spaces and punctuation stripped (`My - Inquiry` → `MyInquiry_WithParameters`); its
  `Function="GenericInquiry.<real GI name>"` attribute points at the `<Function>` element that lists
  each `<Parameter Name Type [Nullable="false"]>`. Look the GI up by that `<Function Name>` — the real
  name, XML entities decoded — not by guessing the stripped import name.
  Source: *Generic Inquiry Access Through OData: Data Retrieval* and *…: General Information*.
- `$filter`, `$select`, `$top` (and `$count` where supported — see below) all work **on top of** the
  function call; empty parentheses `<Import>_WithParameters()` runs with every parameter unset.
- Values: strings single-quoted with `'` doubled (`'O''Brien'`), booleans bare `true`/`false`,
  numbers bare. A string value of `''` is **not** "no value": it is a literal blank and usually
  matches nothing — omit the parameter instead.
- **Do:** a caller that knows the parameters should use `_WithParameters` — it is supported, not a
  workaround, and is safe for an agent **if** the caller validates parameter names and required
  parameters first (see the next two entries). A consumer that can't supply parameters should use a
  parameter-free copy or the underlying contract entity.
- **Don't** conclude "OData can't bind GI parameters" from a probe that only tried `$filter` on
  parameter names, URL query strings, or function-call syntax against the **base** GI name.
- **Don't** use "it has a `_WithParameters` import" only as a reason to *hide* a GI — that import is
  the way to call it correctly.
- *Verified live: 25R2 and 26R2 (2026-11). Documented in the 25R2 and 26R1 doc sets.*

### A **misspelled** `_WithParameters` parameter name is **silently ignored** `[UNIVERSAL]`
- `<Import>_WithParameters(WrongName=@p1)?@p1='X'` succeeds (HTTP 200) and runs as if the parameter
  were absent — on a "blank = all" design that returns the **whole unfiltered result**. No error, no
  warning. GI parameter names are free text, so a typo in the design itself is common — and a caller
  that "corrects" the spelling gets unfiltered data.
- **Do:** validate every supplied name against the `<Function>` parameters in `$metadata` before
  calling (a case-insensitive match resolved to the canonical spelling is fine), and refuse unknown
  names rather than sending them.
- *Verified live: 25R2 and 26R2 (2026-11).*

### Required GI parameters: `Nullable="false"` ⇔ **Is Required**; an omitted optional takes the GI **default** `[UNIVERSAL]`
- A `<Parameter … Nullable="false"/>` in `$metadata` is exactly a parameter with **Is Required**
  checked on the GI's Parameters tab (SM208000); unchecked ones carry no `Nullable` attribute.
- **Required parameter omitted** from the call → **HTTP 404** ("Record not found"), not a silent result.
- **Optional parameter omitted** → it takes the GI's **Default Value** (e.g. `@QuarterStart`,
  `@QuarterEnd`), so the result can be narrower than the caller expects. Defaults are **not** in
  `$metadata`; read them from the design (`GIFilter`) if a consumer needs to say which applied.
- **Do:** enforce required parameters client-side (a 404 is easily misreported as "no such record"),
  and report which optional parameters fell back to their defaults.
- *Verified live: 26R2 (Is Required ⇔ Nullable checked both ways; defaults confirmed by comparing an
  omitted date range with an explicit wider one) and 25R2 (2026-11).*

### OData date-time values can't go in the URL **path** — pass them as **aliases** `[UNIVERSAL]`
- `<Import>_WithParameters(FromDate=2026-10-01T00:00:00Z)` is rejected by ASP.NET request validation
  before Acumatica sees it ("A potentially dangerous Request.Path value was detected from the client
  (:)", an HTML error page). The `:` is the trigger.
- **Do:** put values in the query string as parameter aliases:
  `<Import>_WithParameters(FromDate=@p1)?@p1=2026-10-01T00:00:00Z`. Sending **every** value as an
  alias is the simplest single code path (it also keeps `/`, `#` etc. out of the path). Percent-encoded
  alias keys (`%40p1`) are accepted.
- *Verified live: 26R2 (path rejected, alias works) and 25R2 (alias works) (2026-11).*

### GI **date** parameters change type between releases: 25R2 `Edm.DateTimeOffset`, 26R2 `Edm.Date` `[UNIVERSAL]`
- The same GI's date parameters are declared `Edm.DateTimeOffset` on 2025 R2 and `Edm.Date` on
  2026 R2 (and the corresponding result columns come back as `2026-10-01T00:00:00Z` vs `2026-10-01`).
- 2025 R2 still **accepts a plain `YYYY-MM-DD`** for its `Edm.DateTimeOffset` parameters and applies
  it correctly (an out-of-range plain date returned 0 rows, an in-range one the expected row).
- **Do:** read the parameter type from live `$metadata` rather than hardcoding it, and accept a plain
  date for date-time parameters instead of forcing `…T00:00:00Z` (which makes the caller pick a time
  zone and can shift a range edge by a day).
- *Verified live: 25R2 production and 26R2 (2026-11).*

### `$count=true` **works** on the GI OData endpoint in 26R2 — though the 25R2 docs list it as unsupported `[UNIVERSAL]`
- On 26R2, `/api/odata/gi/<GI>?$count=true` returns `@odata.count`, with or without `$filter`, and it
  equals the number of rows the same query returns. It also works on `_WithParameters` calls.
- The 25R2 *Reporting Tools* guide ("Supporting the OData Specification") lists `$expand` and
  `$count` as unsupported on the GI-based OData interface. Not tested on 25R2.
- **Do:** on 26R2+, request `$count` to tell "exactly at the row cap" apart from "more rows exist";
  keep it switchable per release.
- *Verified live: 26R2 (2026-11). 25R2: documented unsupported, untested.*

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
