---
name: acumatica-gotchas
description: >-
  Acumatica ERP integration gotchas, tripwires, and hard-won rules for
  contract-based REST and OData Generic Inquiries (GIs). Use whenever working
  with Acumatica: writing or debugging contract-REST or OData/GIQL calls,
  choosing endpoints or entities, invoking actions (Release, ConfirmShipment,
  FinishCounting), attaching files, or diagnosing symptoms like
  CannotOptimizeException, a write that returns 200 but silently does nothing,
  License_LoginLimitExceeded / session-limit errors, "input parsing" errors,
  empty GI/OData results, or account lockouts. Also use when deciding
  GI-vs-contract-entity or reasoning about auth/session/seat behavior.
---

# Acumatica Integration Gotchas

A portable, cross-repo knowledge base of things that cost real debugging time when
integrating with Acumatica (Construction/Distribution editions, 2023 R1 → 2025 R2)
over **contract-based REST** and **OData Generic Inquiries**. Read the topic file
matching the task; each is a list of atomic entries.

## How to read every entry — the tag legend

Each entry is tagged. **This tagging is the whole point of a cross-repo kit** — it stops
you from carrying one instance's config into another repo as if it were platform truth.

- **`[UNIVERSAL]`** — behavior of the Acumatica platform / API. Holds for any tenant on
  the noted version+edition. Safe to rely on across projects (still confirm the version).
- **`[TENANT]`** — depends on *this instance's* configuration, customization, license, or
  data. **Never copy the value** into another repo — only the *lesson*. (Names, IDs, codes,
  maps, counts, hostnames, endpoint names, GI names, and secrets are always `[TENANT]`.)
- **`[CLAUDE]`** — a tooling note about Claude Code / the Acumatica MCP, not Acumatica itself.

When unsure how to classify something you're adding, read **[reference-vs-tenant.md](./reference-vs-tenant.md)** first.

Entries carry a `Verified:` line (version/edition/date) where known — Acumatica behavior
shifts across releases, so an unverified claim is a hypothesis, not a fact.

## Topics

- **[auth-sessions.md](./auth-sessions.md)** — OAuth 2.0 ROPC, bearer/session/seat behavior,
  the concurrent-login cap, revocation vs logout (and the `Content-Length: 0` / 411 trap that
  makes logout look broken), scope-dependent sign-out (`api` vs `api offline_access` vs
  `api:concurrent_access`) and why "not required" still costs a seat, the connected app as the ONLY tenant binding
  under oauth, seat-neutral session refresh, token/session lifetimes, inactivity
  timeout scope, cookie reuse, account lockout, grant-cache flush, the `/t/{tenant}` Login Name
  segment, why the GI feed rejects a browser session, Auth Code `offline_access`/`api` scopes and
  refresh rotation, OIDC claims (no roles), no users/roles API, and 401-before-routing on SaaS.
- **[entities-actions.md](./entities-actions.md)** — per-entity field-name traps, PXAction
  names (Release / ConfirmShipment / FinishCounting), the post-Update-IN CorrectShipment lockout,
  keyed-GET-not-$filter, why a `$top=1` probe is not cheap on a delegate-heavy entity, the
  file-attach path and file deletion, long-op polling, PO number padding, drop-ship detection, mandatory
  Project, reason-code usage restrictions, the CannotOptimize family + silent-empty mode, `substringof eq true`,
  attributes (ID vs label, date-only), IN header vs line branch, `PX-CbApiBranch`, shipment qty raises,
  Field Service appointment writes, Project Quote endpoint gap.
- **[giql-odata.md](./giql-odata.md)** — CannotOptimizeException, why some reads must ride a GI,
  $select+$expand drops, parameterized GIs (base name ignores parameters; `_WithParameters` binds
  them; misspelled names silently ignored; Is Required ⇔ `Nullable="false"`; defaults; date-time
  aliases; 25R2 vs 26R2 date types), `$count` on 26R2, v4-vs-v3 dialects, row-level security filtering
  silently, DAC-based OData, filter cost and right-padding, `/` in GI names, GIQL vs contract field names,
  calculated-column filters returning an
  empty-body 200, display-name-derived property naming vs undocumented column order, MCP column
  renames, @odata.nextLink paging, empty-result cache poisoning.
- **[builtin-mcp.md](./builtin-mcp.md)** — Acumatica's own 2026 R2 MCP server (setup, GI-only
  tools, opaque errors, unenforced parameters, row differences vs OData) and the license-gated
  26R1+ "Description for AI" fields.
- **[install-upgrade.md](./install-upgrade.md)** — site-wide customization publishing, self-hosted
  install (RabbitMQ-as-SYSTEM hang), patch levels and PatchTool, snapshot-restore traps (silent partial
  import, a restored tenant that starts sending), republishing customizations, the 25R2 → 26R2 upgrade and
  its republish blockers, reverse-proxy Host header.
- **[writes-idempotency.md](./writes-idempotency.md)** — the silent-200-on-revoked-write trap,
  genuinely unwritable fields (and the PI line note's real path), PI zero writes, confirmed-shipment locks,
  detail rows by `id` + base-URL PUT, endpoint detail collection-vs-object mapping, idempotency and
  PUT-as-upsert, operator attribution, money precision.
- **[reference-vs-tenant.md](./reference-vs-tenant.md)** — the classification rule + a checklist
  of what is ALWAYS tenant-specific. Read this before adding an entry or porting a fact.

## Adding a learning

Run **`/acumatica-learn`** and describe the lesson — it appends a correctly-tagged, version-stamped
entry to the right topic file. See [CONTRIBUTING.md](../../../../CONTRIBUTING.md) for the entry
template and maintenance cadence.
