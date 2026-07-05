---
name: acumatica-learn
description: Capture a new Acumatica learning into the gotchas knowledge base. User-invoked only.
disable-model-invocation: true
---

# Capture an Acumatica learning

The user is recording a new Acumatica gotcha / tripwire / rule. Turn what they describe into a
well-formed entry and append it to the right topic file in the `acumatica-gotchas` skill.

## Steps

1. **Locate the topic files.** They live alongside this command, under the sibling skill:
   `../acumatica-gotchas/` → `auth-sessions.md`, `entities-actions.md`, `giql-odata.md`,
   `writes-idempotency.md`, `reference-vs-tenant.md`. Read the target file first so the new entry
   matches the existing style and isn't a duplicate (if it duplicates, refine the existing entry
   instead of adding a second).

2. **Classify it** using `../acumatica-gotchas/reference-vs-tenant.md`:
   - `[UNIVERSAL]` — Acumatica platform/API behavior (portable).
   - `[TENANT]` — instance-specific config/data (record the *lesson*, never the secret/value).
   - `[CLAUDE]` — a Claude Code / Acumatica-MCP tooling note.
   Split gray-zone entries: behavior `[UNIVERSAL]`, value `[TENANT]`.

3. **Scrub identifiers.** This kit is shareable/open-source. Do NOT write real hostnames, tenant/
   company names, GI names, endpoint names, client IDs, usernames, secrets, or specific code values.
   Generalize to the *class* ("a work-list GI", "the non-project sentinel code", "the session cap").

4. **Write the entry** in this shape and append it under the most relevant heading:

   ```markdown
   ### <one-line symptom or rule> `[TAG]` (+ `[TENANT]` note if gray-zone)
   - What you observe / the rule.
   - Why it happens (root cause), if known.
   - **Do:** the concrete action / correct approach.
   - *Verified: <version> <edition>, <YYYY-MM>.*  (omit or mark "unverified" if not confirmed)
   ```

5. **Confirm** the file + heading you chose and show the appended entry. If the lesson spans topics,
   put it in the best-fit file and cross-reference rather than duplicating.

## Notes
- If none of the topic files fit, propose a new topic file and add it to the index in
  `../acumatica-gotchas/SKILL.md`.
- Prefer editing/strengthening an existing entry over adding a near-duplicate — keep the base lean.
- After editing, remind the user that a new plugin version + `git push` (and teammates running
  `/plugin marketplace update`) is how the change propagates. See `CONTRIBUTING.md`.
