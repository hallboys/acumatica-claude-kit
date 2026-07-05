---
name: acumatica-learn
description: Add Acumatica platform-behavior learnings to the gotchas knowledge base — one you describe, or many harvested from a doc/repo. User-invoked only.
disable-model-invocation: true
---

# Add Acumatica learnings to the kit

Maintain the `acumatica-gotchas` knowledge base. This handles **both** ways of contributing:

- **(A) Capture one lesson** the user describes ("record that logout frees a seat but revocation doesn't").
- **(B) Harvest a source** the user points at ("read `~/code/other-repo/CLAUDE.md` and extract the portable
  Acumatica learnings not already here"). Read that path, mine it for *every* portable lesson, and add each
  one — same rules as a single capture, just in bulk, deduped against what's already in the kit.

Same job either way: classify → scrub → append well-formed entries.

## ⚠️ Where to write (critical) — locate the writable clone

Contributions must land in a **git checkout the user can push**, NEVER the installed plugin cache (a slash
command loaded from an installed plugin resolves to a read-only copy that `/plugin marketplace update`
overwrites). Find the clone in this order:

1. **`$ACUMATICA_KIT_DIR`** — run `echo "$ACUMATICA_KIT_DIR"`; if set, edit the topic files there. This lets
   a contributor capture from ANY session, wherever they cloned.
2. **The current checkout** — else, if the working directory is inside a clone of this kit (find
   `skills/acumatica-gotchas/*.md` under cwd, in a repo whose `.claude-plugin/marketplace.json` names this
   plugin), edit those.
3. **Otherwise STOP** — ask the user for their clone path, then edit there. Offer to persist it so the
   from-anywhere loop works next time: add `export ACUMATICA_KIT_DIR="<path>"` to their shell profile
   (`~/.zshrc` / `~/.bashrc`). Do not write until you have a real git-checkout path.

This is portable across contributors: each person sets their own `ACUMATICA_KIT_DIR` (or just runs from their
clone) — no shared/hardcoded path.

## Steps (per lesson)

1. **Pick the topic file** under `skills/acumatica-gotchas/`: `auth-sessions.md`, `entities-actions.md`,
   `giql-odata.md`, `writes-idempotency.md`, `reference-vs-tenant.md`. Read it first — match the style and,
   if the lesson duplicates an existing entry, **refine that entry** instead of adding a second.

2. **Classify** using `skills/acumatica-gotchas/reference-vs-tenant.md`:
   - `[UNIVERSAL]` — Acumatica platform/API behavior (portable).
   - `[TENANT]` — instance-specific config/data (record the *lesson*, never the value).
   - `[CLAUDE]` — a Claude Code / Acumatica-MCP tooling note.
   Split gray-zone entries: behavior `[UNIVERSAL]`, value `[TENANT]`.

3. **Scrub identifiers.** This kit is shareable/open-source. Do NOT write real hostnames, tenant/company
   names, GI names, endpoint names, client IDs, usernames, secrets, or specific code values. Generalize to
   the *class* ("a work-list GI", "the non-project sentinel code", "the session cap"). Org-specific config
   belongs in a private companion kit, not here.

4. **Write the entry** under the most relevant heading:

   ```markdown
   ### <one-line symptom or rule> `[TAG]` (+ `[TENANT]` note if gray-zone)
   - What you observe / the rule.
   - Why it happens (root cause), if known.
   - **Do:** the concrete action / correct approach.
   - *Verified: <version> <edition>, <YYYY-MM>.*  (omit or mark "unverified" if not confirmed)
   ```

5. **Confirm** what you added (files + headings). For a harvest, summarize the batch: how many added, which
   files, and anything skipped as already-covered, tenant-specific, or a secret.

## Notes
- If none of the topic files fit, propose a new one and add it to the index in `skills/acumatica-gotchas/SKILL.md`.
- Prefer strengthening an existing entry over a near-duplicate — keep files skimmable (they load into context).
- After editing, propagate with the repo's one-command helper: **`"$ACUMATICA_KIT_DIR"/publish.sh "msg"`**
  (or `./publish.sh "msg"` from the clone) — it patch-bumps `plugin.json`, commits, and pushes. Teammates then
  run `/plugin marketplace update`. See `CONTRIBUTING.md`.
