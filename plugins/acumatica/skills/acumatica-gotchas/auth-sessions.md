# Auth, Sessions & Seats

Everything about authenticating a headless/service integration to Acumatica and not
exhausting its concurrent-login license. See the tag legend in [SKILL.md](./SKILL.md).

---

### Only OAuth 2.0 ROPC (password grant) works for a headless service `[UNIVERSAL]`
- **Authorization Code** flow is interactive (needs a browser) — unusable headless.
- **Client Credentials** is **not supported by Acumatica** (any version).
- So a non-interactive integration uses the **Resource Owner Password Credentials**
  (`grant_type=password`) flow against `/identity/connect/token`, or legacy forms-login
  (`/entity/auth/login`). The connected application must be registered for the ROPC/password grant.
- **Do:** register a connected app with the password grant; store client_id/secret + a dedicated
  service user's credentials as secrets.
- *Verified: 2025 R2, Construction edition, 2026.*

### A bearer with the plain `api` scope reuses ONE session per token `[UNIVERSAL]`
- With scope **`api`** (not `api:concurrent_access`), a bearer token authenticates **both**
  contract REST and the OData GI feed, and Acumatica maps it to a **single reused session** — no
  session cookie needed (the only `Set-Cookie` is a benign locale cookie).
- **Trade-off:** one session ⇒ Acumatica **serializes** your calls (a single session does not
  process REST requests concurrently). Fine if reference reads are cached and hot paths are
  sequential; bound in-flight calls so you never fan out beyond what one session can serve.
- **`api:concurrent_access`** enables concurrency **only if you reuse the session cookie** per
  call; otherwise every call counts as a *new* concurrent user and re-floods the license.
- *Verified: 2025 R2, 2026.*

### The concurrent-login license cap is real and small — respect it `[UNIVERSAL]` (cap value `[TENANT]`)
- Acumatica enforces a **maximum number of concurrent sessions/logins** per license. Exceeding it
  → **`License_LoginLimitExceeded`** and/or `ResourceGovernor` request terminations.
- The **cap value is license/tier-specific** (a standard tier is often just a handful; higher tiers
  are larger). Treat the number as `[TENANT]`; never hardcode an assumption.
- **Do:** reuse one cached token/session across requests; single-flight re-auth so a burst of
  401s can't herd many logins at once; bound concurrency; recycle sessions deliberately.

### OAuth token **revocation does NOT free the session seat** `[UNIVERSAL]`
- `POST /identity/connect/revocation` invalidates the *token* but does **not** promptly release
  the Acumatica **session seat** — the seat lingers until the inactivity timeout fires.
- **Consequence:** churning tokens (e.g. revoking on a short cron) mints fresh seats faster than
  old ones idle out → you *climb* toward the cap instead of staying under it.
- *Verified live: 2025 R2, 2026-07 (seat count unchanged after revocation).*

### An explicit **`/entity/auth/logout` DOES free the seat** — but does not kill the token `[UNIVERSAL]`
- Calling `POST /entity/auth/logout` with the bearer (or session cookie) **releases the seat within
  seconds** (returns 204).
- **Gotcha:** logout does **not** invalidate the token. Re-using that same bearer *after* logout
  immediately mints a **new** session. So only ever log out a bearer you have **stopped using**.
- **Pattern that keeps you at ~1 seat:** at token renewal, mint the new bearer, publish it as the
  active one, then log out the **outgoing** bearer and discard it. In a multi-worker/isolate
  deployment, do the swap under a single-flight lock so exactly one logout fires.
- *Verified live: 2025 R2, 2026-07 (seat 2→1 after a clean logout with no re-use).*

### Access-token lifetime is fixed at 1h and not configurable; only refresh-token lifetime is `[UNIVERSAL]`
- Default access token life = **3600s**, returned as `expires_in`. There is **no** exposed knob to
  lengthen it (SaaS: no web.config access).
- Since **2023 R2**, the **refresh**-token lifetime is configurable on the Connected Applications
  form (Absolute / Sliding / Infinite). Access-token life is not.
- **Implication:** renewals happen ~hourly under sustained use; design seat handling around that
  cadence (see the logout-on-renew pattern above), don't expect to avoid renewals.
- *Verified: 2023 R2 → 2025 R2.*

### The user **inactivity timeout is GLOBAL only** — no per-user / per-API override `[UNIVERSAL]`
- Configured in **User Security → Security Preferences** (UI since 2023 R1). There is **no**
  per-user, per-role, or per-login-type (API-vs-UI) timeout override, and SaaS has no web.config.
- **Implication:** you cannot give a service account a shorter idle timeout than interactive users.
  If orphaned API sessions linger too long against the cap, the levers are: reclaim seats yourself
  (logout-on-renew), raise the license tier, or lower the *global* timeout (which also affects
  UI users). Don't plan around a per-service timeout — it doesn't exist.
- *Verified: 2023 R1 → 2025 R2, 2026.*

### OData authenticated with Basic-per-call mints a session **per call** `[UNIVERSAL]` (legacy path)
- In legacy/forms mode, the contract-login cookie may 401 on the OData GI feed, so integrations
  fall back to **HTTP Basic on every OData call** — and Basic with no session cookie makes Acumatica
  **create a new session per call**, exhausting the license fast.
- **Do:** capture and **reuse the session cookie** the first OData (Basic) response returns
  (`ASP.NET_SessionId` + `.ASPXAUTH`), resending it as `Cookie` on subsequent calls. (OAuth
  bearer-only avoids this entirely — see above.)
- *Verified live: 2025 R2 (the dominant cause of a real login-flood incident).*

### A stale/wrong service password → repeated failed logins **LOCK the account** `[UNIVERSAL]`
- If a deployed credential drifts from the real password, the integration's retry loop hammers
  login with the wrong password and Acumatica **locks the account out** (then even correct auth
  500s with "account is locked out").
- **Do:** verify the service password against a live login **before** deploying/enabling it; treat
  auth failures as circuit-breaker events, not blind-retry.

### Granting a **cookie-auth** permission requires flushing the cached session `[UNIVERSAL]`
- A cached forms-login **session cookie carries the rights it had at login time.** Granting a new
  form/GI/entity permission does **not** apply to an already-cached cookie.
- **Do:** after changing a cookie-auth grant, **flush the cached session** (delete it / force re-login),
  or the integration keeps using the old, now-stale rights. **OData/Basic** grants take effect
  immediately (re-auth per call); **cookie** grants do not.
- *Verified live: 2025 R2.*

### Separate tenants = separate service accounts even with the same username `[TENANT]`
- If you run multiple Acumatica **tenants/companies**, the "same" service username in each is a
  **distinct account** — an auth failure/lockout in one cannot affect the other. Don't assume a
  shared identity across tenants. *(Lesson is portable; which tenants exist is `[TENANT]`.)*
