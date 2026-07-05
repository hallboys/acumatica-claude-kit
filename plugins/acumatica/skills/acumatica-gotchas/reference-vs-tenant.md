# Universal vs Tenant — the classification rule

This kit is only reusable across projects if every fact is correctly classified. A **tenant** fact
copied into another repo as if it were **universal** is worse than no note — it's a confident wrong
assumption. Read this before adding an entry or porting a fact.

## The one rule

> **If it's a NAME, an ID, a CODE VALUE, a MAP, a COUNT, a HOST, or a SECRET specific to an
> instance → `[TENANT]`. If it's a BEHAVIOR of the Acumatica platform / API → `[UNIVERSAL]`.**

Platform behavior is portable (still confirm the version). Instance shape is not — only the *lesson*
about that class of shape is.

## Always `[TENANT]` — never copy the value into another repo

- **Endpoint** name and version (e.g. a customized endpoint extending Default).
- **Generic Inquiry** names and their column sets.
- **Codes / sentinels:** the non-project sentinel value, reason-code IDs, cost-code IDs, order-type
  codes, transfer-type.
- **Maps:** warehouse→branch, branch→bin, any lookup specific to the business.
- **Numbers:** the concurrent-session cap, PO-number padding width, page sizes tuned to a dataset.
- **Identities:** service usernames, connected-app client IDs, employee/location defaults, tenant/
  company names, Entra/AD tenant + app IDs.
- **Hosts & secrets:** base URLs, client secrets, passwords, tokens, KV/store IDs.
- **Customizations:** UDFs, extended DAC fields, custom actions, workflow tweaks.

## Usually `[UNIVERSAL]` — the platform behaviors

- Auth flow support (ROPC yes, Client Credentials no), scope/session/seat semantics, revocation-vs-
  logout, token/timeout lifetimes and their configurability.
- Which actions exist and their names (`Release`, `ConfirmShipment`, `FinishCounting`).
- Error semantics: `CannotOptimizeException`, silent-200-on-revoked-write, "input parsing" on a
  detail-shape mismatch, 403-on-missing-grant, `License_LoginLimitExceeded`.
- OData/GI mechanics: paging via `@odata.nextLink`, `$select`+`$expand` coupling, parameter-free
  requirement, DAC-code (not label) matching.
- Rules that hold regardless of data: idempotency is your job; money needs exact decimals; a DAC
  field isn't settable unless exposed.

## The gray zone — split the entry

Many real lessons are a **universal behavior with a tenant-specific value**. Write the entry so the
behavior is `[UNIVERSAL]` and the value is called out as `[TENANT]`. Examples:

- *"Reason codes are usage-restricted per doc type"* → `[UNIVERSAL]`; *which* codes exist → `[TENANT]`.
- *"There is a concurrent-session cap"* → `[UNIVERSAL]`; *the number* → `[TENANT]`.
- *"PO numbers are zero-padded"* → `[UNIVERSAL]`; *the width* → `[TENANT]`.

## Version discipline

Acumatica behavior shifts across releases (2023 R1/R2, 2024, 2025 R1/R2) and editions (Construction,
Distribution, …). Every `[UNIVERSAL]` entry should carry a `Verified:` line with the version/edition/
date it was confirmed. Without it, the entry is a hypothesis — useful, but flag it as unverified.
