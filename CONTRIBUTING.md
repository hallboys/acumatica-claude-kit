# Maintaining the Acumatica Claude Kit

How to add, edit, and ship knowledge so it stays accurate, lean, and safe to reuse.

## Where things live

```
.claude-plugin/marketplace.json              # marketplace catalog (lists the plugin)
plugins/acumatica/
  .claude-plugin/plugin.json                 # plugin manifest (bump "version" on release)
  skills/acumatica-gotchas/
    SKILL.md                                  # index + tag legend (update when adding a topic file)
    auth-sessions.md
    entities-actions.md
    giql-odata.md
    writes-idempotency.md
    reference-vs-tenant.md                    # the classification rule — read before editing
  skills/acumatica-learn/SKILL.md                       # the /acumatica-learn capture command
```

## Adding a learning

Easiest: run **`/acumatica-learn`** inside Claude Code and describe the lesson — it does the steps
below for you. To do it by hand:

1. **Pick the topic file** it best fits. Read it first to avoid duplicates.
2. **Classify** with [reference-vs-tenant.md](plugins/acumatica/skills/acumatica-gotchas/reference-vs-tenant.md):
   `[UNIVERSAL]`, `[TENANT]`, or `[CLAUDE]`. Split gray-zone entries (behavior universal, value tenant).
3. **Scrub identifiers** (see below).
4. **Append** using the entry template:

   ```markdown
   ### <one-line symptom or rule> `[TAG]`
   - What you observe / the rule.
   - Why it happens (root cause), if known.
   - **Do:** the concrete correct action.
   - *Verified: <version> <edition>, <YYYY-MM>.*
   ```

## Rules that keep the kit trustworthy

- **Tag everything.** An untagged entry is unusable across repos. When in doubt, read the
  classification file.
- **No identifiers.** This repo is shareable / open-source-bound. Never commit hostnames, tenant or
  company names, GI names, endpoint names, client IDs, service usernames, secrets, KV/store IDs, or
  specific business code values. Generalize to the *class* of thing. This is a hard review gate.
- **Version-stamp `[UNIVERSAL]` claims.** Include `Verified: <version> <edition>, <date>`. Acumatica
  behavior changes across releases; an unstamped claim is a hypothesis — mark it "unverified" if so.
- **Strengthen, don't duplicate.** Prefer editing an existing entry over adding a near-duplicate. Keep
  each topic file skimmable — it's loaded into a model's context on demand, so lean beats exhaustive.
- **One concept per entry.** Symptom → cause → do. If a lesson spans topics, put it in the best-fit
  file and cross-reference.
- **New topic file?** Create it under `skills/acumatica-gotchas/`, then add it to the index list in
  `skills/acumatica-gotchas/SKILL.md` so Claude knows it exists.

## Shipping an update (propagation)

Editing the files locally updates *your* installed copy on the next `/reload-plugins`. For teammates:

1. Bump `"version"` in `plugins/acumatica/.claude-plugin/plugin.json` (semver: patch for entry
   tweaks, minor for new topic files/commands).
2. Commit and `git push`.
3. Teammates run `/plugin marketplace update acumatica-claude-kit` to pull it.

## Consolidation cadence

Every so often (or when a file sprawls), do a consolidation pass: merge overlapping entries, delete
anything disproven, re-verify stale `[UNIVERSAL]` claims against the current Acumatica version, and
confirm no identifiers slipped in. The `skill-creator` and `consolidate-memory` skills can help.

## A note on the source of these entries

The seed content was distilled from real integration work and deliberately stripped of the origin
project's specifics. If you port a lesson *from* a proprietary repo, re-run the identifier scrub —
what's obvious-and-safe in the source repo (a GI name, a warehouse code) is exactly what must not
land here.
