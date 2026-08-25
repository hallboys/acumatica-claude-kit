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
  and no change**. Confirmed case: the **per-line `note` on a physical-inventory count line** — discarded
  in every payload shape (bare string, `{value}` envelope, alongside a quantity write that DID persist),
  on **both** PI entities, and it does not read back even when set in the ERP UI. The document **header**
  note on the same record persists normally.
- The pattern: a note/annotation field can be exposed on a *detail* row of a document yet be owned by the
  screen rather than the API. Detail notes on other document types (e.g. receipt lines) do persist — so
  "detail notes work here" proves nothing about the next entity.
- **Do:** never accept a 200 as proof. **Read the field back on a fresh GET** before designing around it,
  and prove it on the *specific* entity + level (header vs line) you intend to write. If it discards,
  don't build the feature on that field — put the durable record where it demonstrably persists (a header
  note, a file attachment, or your own store) rather than assuming a payload-shape fix exists.
- *Verified live: 25R2, 2026-08.*

### Endpoint **detail collection vs single-object mapping** is per-tenant and silently breaks writes `[UNIVERSAL]` (shape `[TENANT]`)
- A custom/extended endpoint can map a document's **`Details`** as either a **collection** or a
  **single object**. If the endpoint maps it one way and your payload sends the other, the write fails
  with a vague **"An exception occurred during input parsing"** — deserialization, not your data.
- **Do:** confirm the endpoint's detail mapping shape per tenant; send the shape it expects. This
  differs between a sandbox and production endpoint even for the "same" entity.
- *Verified live: 25R2.*

### Acumatica has **no native idempotency** — you must enforce it `[UNIVERSAL]`
- A retried `POST` (timeout, 5xx, network blip) will **double-post** — Acumatica won't dedupe it.
- **Do:** carry an **idempotency key** per mutating request and dedupe on it end-to-end (record
  key → created ref#, and short-circuit a replay). Persist the mapping durably (not in memory).

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
