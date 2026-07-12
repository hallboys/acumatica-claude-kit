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

### A **parameterized** GI returns **0 rows over OData** for a service account `[UNIVERSAL]`
- GIs that declare parameters expect them supplied interactively; their OData feed returns **empty**
  for a headless service account.
- **Do:** publish a **parameter-free** copy of the inquiry for OData consumption, or read the
  underlying **contract entity** instead. (Only parameter-free GIs are OData-friendly.)
- *Verified live: 25R2.*

### GI **column names differ between the raw OData feed and the MCP** — trust the feed `[CLAUDE]` / `[UNIVERSAL]`
- The Acumatica MCP may render a GI column under a different name than the **raw OData feed** your
  code actually receives (e.g. a cost-code id shown one way by the MCP, delivered under a plainer
  name in the feed). **Trust the raw feed**; confirm real column names by reading the feed, not the MCP.

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
