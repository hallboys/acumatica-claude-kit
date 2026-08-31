# Maintaining the Acumatica Claude Kit

How to add, edit, and ship knowledge so it stays accurate, lean, and safe to reuse.

## Consuming vs contributing (the workflow)

**Consume everywhere; contribute from the source.**

- **Consume:** install this plugin at user scope (`/plugin install acumatica-claude-kit@acumatica-claude-kit`).
  It then auto-loads in *every* repo whenever Claude works with Acumatica. Consuming repos do nothing else.
- **Contribute:** always edit **a clone you can push**, then push. The *installed* copy in other repos lives
  in a managed plugin cache that is **overwritten on every `/plugin marketplace update`** — edits there never
  reach git and get wiped.

### Contributor setup (one-time, per person — portable)

Anyone can contribute; nothing depends on a shared directory layout:

1. **Clone** this repo anywhere: `git clone https://github.com/hallboys/acumatica-claude-kit`.
2. *(Optional but recommended)* point your tools at it so you can capture from **any** session:
   add `export ACUMATICA_KIT_DIR="/your/path/to/acumatica-claude-kit"` to your shell profile
   (`~/.zshrc` / `~/.bashrc`).

Then to contribute you can either **run `/acumatica-learn` from inside your clone**, or — if `ACUMATICA_KIT_DIR`
is set — capture from any session (the command self-locates your clone via that var, falls back to the current
checkout, and asks for your path if it finds neither). Either way edits land in *your* git checkout, never the
read-only plugin cache.

**Three planes — keep them apart:**

| Plane | Example | Where |
|---|---|---|
| Universal platform behavior | "logout frees a seat; revocation doesn't" | **this kit** (`[UNIVERSAL]`) |
| Your org's instance config | GI names, endpoint name, warehouse→branch map | a **separate private** org kit — never here |
| Secrets | passwords, client secrets, tokens | a secret store (e.g. Workers secrets) — never any repo |

This kit is `[UNIVERSAL]`-only; the identifier scrub (below) is what enforces that. Keep org config in a
private companion kit and secrets in a secret store.

**Harvesting a repo that already has learnings:** to lift portable lessons out of a project that
accumulated them, open a Claude session with cwd = **this** repo, point it at the other repo's docs
(Claude can read any absolute path), and have it extract → classify → scrub → append here. Doing it from
this repo guarantees edits land where you push (not in a throwaway plugin cache).

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

One command from your clone does the bump + commit + push:

```
./publish.sh "what changed"        # or  "$ACUMATICA_KIT_DIR"/publish.sh "what changed"
```

It patch-bumps `plugin.json`, commits, and pushes. (Bump the **minor** by hand for a new topic file or
command.) Teammates then pull it with `/plugin marketplace update acumatica-claude-kit` + `/reload-plugins`
— needed only to *use* the new knowledge locally; your push already shares it.

## Consolidation cadence

Every so often (or when a file sprawls), do a consolidation pass: merge overlapping entries, delete
anything disproven, re-verify stale `[UNIVERSAL]` claims against the current Acumatica version, and
confirm no identifiers slipped in. The `skill-creator` and `consolidate-memory` skills can help.

## A note on the source of these entries

The seed content was distilled from real integration work and deliberately stripped of the origin
project's specifics. If you port a lesson *from* a proprietary repo, re-run the identifier scrub —
what's obvious-and-safe in the source repo (a GI name, a warehouse code) is exactly what must not
land here.

### License boundaries on outside sources

This kit is **Apache-2.0**. Two upstream sources are easy to reach for and must be handled
differently:

- **`github.com/Acumatica/Acumatica-AI-Resources` — everything outside `Documentation/` is
  `GPL-3.0-only`.** That includes its skills (`acumatica-integration-diagnostics`,
  `acumatica-customization-update`, `acumatica-modern-ui-control-builder`) and its PowerShell
  scripts. GPL is one-way: **do not copy that text, or close paraphrases of it, into this repo.**
  The overlap with `acumatica-gotchas` makes this a live temptation — read it for ideas, write
  entries in your own words from your own verification, and cite behavior rather than prose.
- **Acumatica's official documentation is licensed content, not open content.** In that same repo
  the `Documentation/` directory is explicitly *excluded* from its GPLv3 and carries an
  all-rights-reserved notice; the Beacon Portal download is login-gated. Being publicly readable is
  not redistribution rights. **Cite topics by name** (e.g. "*Preparation of an Inquiry for
  Exposure* → 'Supporting the OData Specification'") and state the rule in your own words. Do not
  paste doc prose, tables, or screenshots into entries, and never commit any part of the corpus.
