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

### The GI OData feed speaks **OData v4**; contract REST speaks **v3** — don't carry filter syntax between them `[UNIVERSAL]`
- `/t/{tenant}/api/odata/gi/…` is **OData v4** (its parser errors are verbatim Microsoft.OData.Core
  wording); `/entity/{endpoint}/{version}/…` is **v3**:

  | | Contract REST (v3) | GI OData (v4) |
  |---|---|---|
  | partial match | `substringof('x', F)` | `contains(F,'x')` — `substringof` → *"unknown function"* |
  | `startswith` / `endswith` | work | work |
  | `tolower()` / `toupper()` | 500 | work |
  | date literal | `datetimeoffset'…'` | bare `2024-01-01T00:00:00Z`; `datetimeoffset'…'` → *"Unrecognized 'Edm.String' literal"* |

- A v4 parser rejection means the query **never ran** — don't report it as "no rows matched". For an
  unknown-property error, take real names from the GI's `$metadata` (dialect/naming mistakes were the
  largest error class in one production integration's logs).
- *Verified live: 25R2, 2026-07-31.*

### Row-level security **filters** rows silently — HTTP 200 with fewer rows, never an error `[UNIVERSAL]`
- Restriction groups and branch row access limit what an identity sees in GI and contract reads. A missing
  grant produces a clean **200 with a shorter result** (a whole branch returning 0 rows; a catalogue a few percent short).
- A mirror/sync that imports "what it saw" therefore **retires live records**, and every diagnostic read as
  the same restricted account confirms the absence. **An unprivileged read is not evidence of absence.** A
  normal service account can't introspect restriction groups (`RelationGroup` → 403).
- **Not everything is filtered:** the **Branch** master returns every branch whatever the user's access
  (enforcement applies to transactions), so reading `Branch` as the user can't answer "which branches may
  they see". Restriction groups scope *projects*, not branch access.
- The same mechanism works as an ACL: a GI called with the **user's own token** returns only that user's
  rows, so its result *is* their grant. Treat an empty cached grant as a cache miss.
- **Do:** guard destructive sync steps (hold back mass deactivation above a threshold); compare counts
  between the GI and the master entity/DAC as a canary; when a branch or entity comes back empty, check the
  identity's row-level grants first.
- *Verified live: 25R2, 2026-07 (branch) and 2026-08 (catalogue).*

### GI `$filter` on stored columns is pushed into SQL — cost scales with **matched** rows; values arrive right-padded `[UNIVERSAL]`
- Timed at ~**44 ms per matched row**: a wide window (1,000+ rows) took ~45 s; the same window filtered on
  two stored code columns ~1 s. Slow GI reads usually come from fetching too much, not from the filter.
- `$select` cuts the payload (~1.8 MB → ~0.5 MB per 1,000 rows) but **not server time** on large pages.
- Fixed-width CHAR codes come back right-padded (`"CODE      "`). An equality `$filter` still matches (the
  collation ignores trailing pad — also seen on 26R2), but client-side equality, map keys and cache keys
  don't. Trim at the boundary.
- **Do:** push every **stored**-column predicate into `$filter` (never a calculated column), `$select` only
  what you render, and trim before comparing, keying or displaying.
- *Verified live: 25R2, 2026-07 (timed curl).*

### DACs are queryable directly over OData v4 at `/t/{tenant}/api/odata/dac` (2025 R1+) `[UNIVERSAL]`
- No GI needed. Access is the user's own and enforced per DAC — each needs View on its **owning screen**;
  some return 403 to ordinary accounts (user, user-role, payment-method-detail, `RelationGroup`,
  `INItemClass`).
- Entity sets use the **bare class name** (`SOOrder`); the namespace-qualified form in the docs is the OData
  *type* and 404s as a set. There are **thousands** of sets — address them by name, never pull `$metadata`
  into a model's context.
- **Always `$select`** (the users DAC exposes password, password-answer and 2FA fields). Page at **≤ 200**
  rows; larger pages reset the connection.
- Field names are **physical DAC names**, and fields return **surrogate keys** where a GI returns codes
  (`ItemClassID` is an integer, useless without the lookup DAC). Read-only; no aggregation extension.
- **Do:** use it for bulk reads/export/reconciliation and filters contract REST can't apply on document
  entities — not as a speed win for small capped reads.
- *Verified live: 25R2, 2026-07/08.*

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
- An integration's probe script reads `@odata.count` from a 25R2 production GI and a DAC
  (`?$count=true&$top=1`) — indirect evidence it may work on 25R2 too. Not a stated live verification;
  check before relying on it.

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
- **Same failure on a grouped GI:** a `$filter` on an **aggregated** column of a GI with grouping also
  returns an **empty-body 200**. Filtering on the grouped/plain columns (including compound
  `A or (B and C)`) works; apply the rest after fetching. *Verified live: 25R2, 2026-10-06.*
- A grouped GI also can't pass a **formula** column through from an inner GI ("Cannot perform an aggregate
  function on an expression containing an aggregate…"). *(Stated in source; no verification date.)*

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
- **Empirically, Caption DOES change the property name.** Setting a Results Grid Caption renames the
  **live** OData property (consumers keyed on the old name break), and a typo in a Caption becomes the
  property name. A Caption set to *exactly the name OData already reports* is a no-op (`$metadata`
  byte-identical) that pins the name against later design edits.
- **`_N` collision suffixes are positional:** the earlier grid row keeps the bare name; a Caption on a
  collision row must carry the suffix literally (`ReferenceNbr_2`).
- **Hoisting isn't limited to declared keys** (one GI showed a clean 3-column hoist while `$metadata`
  declared no leading keys), and **some active design rows produce no property at all** (cause not
  established) — every later column then shifts.
- **Key columns auto-exposed from JOINED tables are NULL whenever the join finds no match** — never use one
  as a row id; use the column the design selects from the base table.
- An ERP-side read-back of stored column descriptions can't detect a mis-paired column; verify through the
  delivered property names and real values. *Verified live: 25R2, 2026-07/09.*

### `getOData` must follow `@odata.nextLink` `[UNIVERSAL]`
- OData GI feeds **page**. A reader that ignores `@odata.nextLink` silently truncates. Accumulate all
  pages (a `$top` caller intentionally gets one capped page).
- **Not every GI pages.** A large parameter-free GI with the Results-grid Top-N cleared returned its
  **entire** result (tens of thousands of rows, many MB) in one response with **no** `@odata.nextLink` — a nextLink loop never
  iterates, and parsing the body can exceed a memory-capped runtime. `$top`/`$skip` both work there.
  **Do:** page yourself (`$top`/`$skip`) and stop on the first short page. On contract REST, `$skip` paging
  was stable with `$orderby` on the natural key. *Verified live: 25R2, 2026-08.*

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
- **Range filters too.** A `$filter` window of local dates must be converted to UTC instants. Stamping bare
  local dates with `Z` (`le <to>T23:59:59Z`) silently drops every row in the last <UTC-offset> hours of the
  final day. Keep display, write-back and query-bound conversion in **one** shared helper.
  *Verified live: 25R2, 2026-07.*

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

### GIQL is **DAC-land**: contract field names don't transfer, and `WHERE` has no `LIKE` `[UNIVERSAL]`
- Contract-entity field names are endpoint *mappings*, not DAC fields: the shipment line's order link is
  `SOShipLine.OrigOrderNbr` (there is **no** `SOShipLine.OrderNbr`), and `OrigOrderQty` is obsolete — take
  the ordered qty from a `SOLine` join.
- GIQL `WHERE` supports `IS NULL`, `AND`/`OR`, comparisons and parentheses, with **no `LIKE`**. Put
  substring matches on the GI's **Conditions** tab (*Contains*, plus OR grouping), whose labelled
  dropdowns/date picker also sidestep the status-code-vs-label, boolean and date-literal traps.
- A LEFT JOIN on a wrong field name yields **NULL silently**, not an error — confirm join fields in the GI
  editor's field list.
- *Verified: SOShipLine field names against the DAC, 25R2, 2026-08-04. No-`LIKE` per documented GIQL support. LEFT-JOIN-NULL stated, not probed.*

### A GI whose name contains `/` is unreachable over OData — though `$metadata` lists it `[UNIVERSAL]`
- `/` is a URL path separator, so `/api/odata/gi/<name with />` returns **404** and the GI never works as an
  entity set, yet `$metadata` still carries its EntityType (tooling that matches names after stripping
  punctuation will register a GI no call can reach). If the GI is parameterized, its `_WithParameters`
  function URL — whose name has the punctuation stripped — should work (unverified).
- **Do:** keep OData-exposed GI names free of `/` (and, as a precaution, `\ ? # % ( )`). Rename rather than
  escape, after checking what references the GI.
- *Verified live: 25R2, 2026-09-02 (`/` only).*
