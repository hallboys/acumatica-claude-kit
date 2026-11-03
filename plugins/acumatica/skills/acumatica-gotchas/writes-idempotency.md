# Writes, Idempotency & Attribution

The traps that make a write silently do the wrong thing (or nothing). These are the highest-severity
gotchas — a mis-fired write posts to the ledger. See the tag legend in [SKILL.md](./SKILL.md).

---

### A write-denied role returns **HTTP 200 with the change silently discarded** `[UNIVERSAL]` ⚠️
- If the service account's role **lacks write access** to an entity/field, a `PUT`/`POST` returns
  **200** and the response **echoes the OLD value** — indistinguishable from a read-only/derived field
  unless you check the role's permissions.
- **This is the #1 time-sink.** When a contract-REST write appears to no-op (200, value unchanged),
  **check the role's WRITE access FIRST** — before suspecting read-only fields, workflows, or add-on
  modules. After granting write access on a **cookie-auth** connection, **flush the cached session**
  (it carries login-time rights) or the deployed integration keeps using the denied rights.
- *Verified live: 25R2 (a long investigation chased "read-only fields" when the real cause was a
  revoked write role).*

### Some fields are **genuinely unwritable** and discard silently too — same 200, different cause `[UNIVERSAL]`
- Once the role's write access is confirmed (entry above), a field can *still* accept a `PUT` with **200
  and no change**. Confirmed cases (write access proven by a control field in the SAME PUT persisting):
  the shipment line's warehouse-picked qty (`PickedQty`) even after an admin maps it onto the endpoint
  (it then *reads*, but writes discard), and the shipment header `Picked` flag — both workflow-owned.
- **The physical-inventory LINE note is writable, just not where you'd look.** The plain `note` on a count
  line discards in every shape on both PI entities, and the Count entity's *header* note discards too (only
  the Review entity's header note persists). But `PhysicalInventoryReview` PUT
  `Details:[{id, custom:{PIDetail:{NoteText:{type:"CustomStringField", value:"…"}}}}]` **persists**, and
  reads back as the line's standard `note` on BOTH PI entities. The same custom write through
  `PhysicalInventoryCount` → 200, discarded. Read it with `$custom=Details/PIDetail.NoteText` (slash form;
  the dotted `Details.PIDetail…` 500s "view Details is not found"). The write REPLACES (`""` clears), so
  merge with any human-typed text first.
- The pattern: a field can be exposed on one projection/path and owned elsewhere. "Not writable via the
  obvious field" ≠ "not writable" — try the owning entity's `custom` view before concluding.
- **Do:** never accept a 200 as proof. **Read back on a fresh GET/session** before you design around a
  field, and prove it on the *specific* entity + level + path you intend to write.
- *Verified live: 25R2, 2026-06 (PickedQty/Picked) and 2026-09-29 (PI line note via Review custom, re-read on a fresh session).*

### `PhysicalQty: 0` on a **never-counted** PI line is silently dropped `[UNIVERSAL]`
- PUT `PhysicalInventoryCount` with `PhysicalQty: 0` on a line nobody has counted → **HTTP 200, value
  discarded**; the line stays uncounted (null). A counter keying "0 — nothing here" sees "saved" and it
  never lands.
- 0 sticks only **after a non-zero value**, and the two writes must **not be back-to-back**: writing 1 then
  0 in one go left the line at 1. A keyed `GET …/{ref}?$expand=Details` between them makes the 0 stick
  (the session appears to cache the record, so the 0 reads as "no change").
- Related: contract REST **cannot insert** PI lines; lines added mid-count must be added in the ERP. At
  Complete, the ERP turns remaining null quantities into 0, so "never counted" vs "counted 0" is only
  distinguishable **before** Complete, by `PhysicalQty == null`.
- **Do:** for zeros, prime a non-zero value, re-read, write 0, then **read back** and fail loudly if it
  didn't land. Never trust a 200 on a PI quantity write.
- *Verified live: 25R2, 2026-09-28 (prime/re-read/0 sequence). "Can't insert lines" and "null→0 at Complete" are from source analysis, not a dedicated probe.*

### A **confirmed shipment** discards field & attribute writes (200) — but **attachments still persist** `[UNIVERSAL]`
- Once a shipment is confirmed, PUTs to its fields or user-defined attributes return **200 and nothing
  persists**. An *invalid* attribute value is a loud 422; only the document lock is quiet.
- Files are different: a `files:put` attach **after** `ConfirmShipment` persists and reads back in
  `$expand=files`, so post-confirm artifacts (signature/photo PDFs) can be built off the critical path.
- **The PUT echo is not a uniform success signal:** a locked document echoes the written field as `null`
  (a reliable lock detector); a write-denied role echoes the **old** value (entry above); a requisition
  line `note`/`Description` echoes `null` **even on success**. Only a keyed read-back is proof.
- **Do:** write any status you need recorded in the PUT that runs **before** `ConfirmShipment`. Treat a
  post-confirm field write as impossible, not as a retry case.
- *Verified live: 25R2, 2026-08-26 (attribute lock + null echo) and 2026-10-12 (attach after confirm).*

### Endpoint **detail collection vs single-object mapping** is per-tenant and silently breaks writes `[UNIVERSAL]` (shape `[TENANT]`)
- A custom/extended endpoint can map a document's **`Details`** as either a **collection** or a
  **single object**. If the endpoint maps it one way and your payload sends the other, the write fails
  with a vague **"An exception occurred during input parsing"** — deserialization, not your data.
- **Do:** confirm the endpoint's detail mapping shape per tenant; send the shape it expects. This
  differs between a sandbox and production endpoint even for the "same" entity.
- *Verified live: 25R2.*

### Update detail rows by their **`id`**, PUT to the **base entity URL** — `LineNbr` means insert, a keyed URL misroutes `[UNIVERSAL]`
- **Row identity:** a detail row carrying only `LineNbr` makes the ERP attempt to **insert** a new row,
  which fails opaquely (500 on a PI count, where inserts are illegal; 422 "Data Field cannot be empty"
  elsewhere). Delete + re-add also renumbers lines.
- **URL:** `PUT /entity/{endpoint}/{ver}/{Entity}/{key1}/{key2}` is routed to the file-upload controller →
  "Invalid uri structure"; `/{Entity}/{id}` on a custom-endpoint entity returned 500 with the same text.
- **Do:** GET with the detail expanded, map each row to its `id` GUID, and PUT to `/{Entity}` (the
  collection) with the key fields or record `id` in the body and every row addressed by `id`
  (`{"id": "...", "delete": true}` removes one). One PUT can carry every row. Cache ids if you save
  repeatedly; on a stale id, re-GET and remap.
- Failure bodies: the outer message is often a bare **"Operation failed"**; the real cause is in
  `innerException.exceptionMessage`. Surface it verbatim.
- *Verified live: 25R2 — PhysicalInventoryCount (2026-06), Field Service appointments (2026-07), a GI-design detail collection on a custom endpoint (2026-08).*

### Acumatica has **no native idempotency** — you must enforce it `[UNIVERSAL]`
- A retried `POST` (timeout, 5xx, network blip) will **double-post** — Acumatica won't dedupe it.
- **Do:** carry an **idempotency key** per mutating request and dedupe on it end-to-end (record
  key → created ref#, and short-circuit a replay). Persist the mapping durably (not in memory).
- Contract-REST `PUT` is an **upsert**: idempotent only when the payload carries the key. Omit the key on an
  auto-numbered entity and every retry creates a **new** record with the next number.
- A successful write normally echoes the saved record. A **2xx with an empty or non-JSON body** is
  unconfirmed: don't auto-retry it (a retry can duplicate); verify in Acumatica instead.
- *Upsert behaviour verified 25R2 (2026); the empty-body rule is a design rule, not a reproduced failure.*

### Resolve a write to a **2xx before reporting success** `[UNIVERSAL]`
- Don't report "saved/queued" optimistically. A write that 422s (bad reason usage, branch mismatch,
  missing required field) must surface as a failure, not a silent loss. Resolve only on a real 2xx and
  return the actual Acumatica ref#.

### The service account is the ledger "creator" — stamp the **real operator** yourself `[UNIVERSAL]`
- Because a single service account authenticates, Acumatica records *it* as the document creator.
- **Do:** stamp each write with the real end-user's identity (a `note` string, or a dedicated UDF if
  the endpoint exposes one) **and** keep an independent audit record (who + idempotency key + ref#).
  Never take the operator identity from the request body — derive it from the authenticated user.

### Never do floating-point math on money or ledger quantities `[UNIVERSAL]`
- Amounts and posting quantities must use exact decimal arithmetic. Watch **decimal-type inference on
  GI-derived fields** — GI feeds often deliver numbers as **strings** or loosely typed; parse safely
  (a shared safe-parse), never string-concat or trust a possibly-null `Qty`.

### Cross-branch / cross-tenant writes are a boundary you enforce in code `[UNIVERSAL]` (the map is `[TENANT]`)
- Acumatica ties a document's branch to its source (e.g. a receipt's branch to the PO's branch). A
  write into the wrong branch/warehouse **fails at release** ("warehouse X does not belong to branch Y"),
  sometimes leaving an orphaned balanced document.
- **Do:** validate the branch/warehouse ↔ source relationship **up front** (reject before posting),
  and infer branch **server-authoritatively** from the warehouse rather than trusting the caller. The
  warehouse→branch **map itself is `[TENANT]`**.
