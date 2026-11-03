# Acumatica's Built-in MCP Server (2026 R2) & Description for AI

What the MCP server that ships with 2026 R2 actually does, and the 26R1+ "Description for AI"
fields. See the tag legend in [SKILL.md](./SKILL.md). Acumatica notes that the generated tool
schemas are not fixed contracts, so re-check these on each release.

---

### Setup: AI Studio feature → SM302100; URL is `{instance}/t/{Login Name}/mcp/{Server Name}` `[UNIVERSAL]`
- Turned on with the **MCP Server** feature under *AI Studio* on Enable/Disable Features
  (CS100000); servers are configured on **MCP Servers (SM302100)**. Each server exposes the
  Generic Inquiries you add to it (Acumatica suggests 50 or fewer).
- The URL embeds the tenant **Login Name** (SM203520), not the Tenant Name — see
  [auth-sessions.md](./auth-sessions.md).
- Clients authenticate with OAuth through a Connected Application whose client ID and secret are
  entered by hand in the AI client (no dynamic registration).
- *Verified live: 26R2 self-hosted (2026-11).*

### It is **GI-only**, and its tool descriptions are just field-name lists `[UNIVERSAL]`
- One tool per GI. The tool description is "Available result properties for the function: …" —
  no field types, no inquiry description.
- Responses are `{count, value}`: `count` is the exact total; `skip` / `top` page through it (default
  top 100; a top of 5000 was honoured).
- Values come back **space-padded as stored** (`"MAIN        "`); equality filters still match, but
  trim before comparing or displaying.
- The filter dialect is OData v4 (`contains(F,'x')` works, `substringof` fails).
- *Verified live: 26R2 (2026-11).*

### **Every** failure returns the same opaque message `[UNIVERSAL]`
- A misspelled field, a v3 function on this v4 dialect, and a filter on a calculated column all came
  back as `An error occurred invoking '<tool>'.` with no detail, so an agent cannot tell what to fix.
- One improvement over plain GI OData on 25R2: a filter on a calculated column errors instead of
  returning an empty-body 200 (see [giql-odata.md](./giql-odata.md)).
- *Verified live: 26R2 (2026-11).*

### GI parameters are tool inputs but are **not enforced** `[UNIVERSAL]`
- A parameterized GI's parameters appear as a `parameters` object (named exactly as in the GI design,
  typos included). The schema calls them mandatory but does not mark them required; a call without
  them runs the inquiry with blank parameters — on a "blank = all" design, the unfiltered result.
- With parameters supplied, the results were correct.
- **Do:** treat parameter presence as the caller's job; an agent client should check the GI's
  Parameters tab (Is Required, defaults) before relying on this server for it.
- *Verified live: 26R2 (2026-11).*

### The built-in server and GI OData do **not always return the same rows** `[UNIVERSAL]` (unexplained)
- For the same user and inquiry, the built-in server returned a handful of rows that GI OData never
  returned, even filtered by the document's own key; GI OData on 25R2 hid the same rows. The rows
  shared a project-level trait, but the cause (and which behavior is intended) was not determined.
- **Do:** don't reconcile totals between the two paths and assume a bug in your own code.
- *Observed: 26R2 vs 25R2/26R2 OData (2026-11). Cause unknown.*

### "Description for AI" fields (26R1+) are **license-gated** and do not reach the MCP server unprocessed `[UNIVERSAL]` (license `[TENANT]`)
- 26R1 adds built-in AI description fields on the GI (`GIDesign`), Results Grid columns (`GIResult`)
  and Parameters (`GIFilter`), plus an *Expose to AI Assistant* flag. The documentation ties them to
  the in-product **AI Assistant** (processed on AI Assistant Data Processing, ML503010) and does not
  mention MCP.
- Generic Inquiry (SM208000) **shows the fields only when AI Studio is licensed**; without the
  license they are hidden and cannot be edited there.
- With descriptions entered but **not processed**, a freshly connected MCP client still saw only the
  field-name list — the text did not reach the tool descriptions. Whether *processed* descriptions
  reach MCP clients is untested: ML503010 failed on a self-hosted sandbox with "Discovery endpoint
  address not set" (the AI Assistant cloud service was not configured there — an inference).
- **Do:** if a third-party MCP server needs GI/column descriptions on any license, keep them in
  your own custom fields; treat the built-in fields as an optional source on licensed instances.
- *Verified live: 26R2 (2026-11).*
