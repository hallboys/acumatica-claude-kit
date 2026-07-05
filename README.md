# Acumatica Claude Kit

A [Claude Code](https://claude.com/claude-code) **plugin marketplace** carrying a portable, cross-repo
knowledge base of Acumatica ERP integration lessons — gotchas, tripwires, and hard-won rules for
**contract-based REST** and **OData Generic Inquiries**.

It exists because Acumatica integration knowledge is (a) expensive to rediscover, (b) easy to get
subtly wrong, and (c) mostly the same from project to project — *if* you carefully separate platform
behavior from one instance's configuration. This kit does that separation explicitly.

## What's in it

One plugin, **`acumatica`**, containing:

- **`gotchas`** skill — model-invoked whenever Claude works with Acumatica. An index
  ([SKILL.md](plugins/acumatica/skills/gotchas/SKILL.md)) plus topic files:
  auth/sessions/seats, entities/fields/actions, GIQL/OData, writes/idempotency, and the
  universal-vs-tenant classification rule.
- **`/acumatica:learn`** command — user-invoked; captures a new lesson into the right topic file,
  correctly tagged and identifier-scrubbed.

## The core idea: `[UNIVERSAL]` vs `[TENANT]`

Every entry is tagged:

- **`[UNIVERSAL]`** — Acumatica *platform/API* behavior. Portable across projects (confirm the version).
- **`[TENANT]`** — *instance-specific* config/data. Never copy the value into another repo — only the
  lesson.
- **`[CLAUDE]`** — a Claude Code / Acumatica-MCP tooling note.

This tagging is what makes the kit safe to reuse. See
[reference-vs-tenant.md](plugins/acumatica/skills/gotchas/reference-vs-tenant.md).

## Install

**Try it locally (from a clone):**
```
/plugin marketplace add ./acumatica-claude-kit
/plugin install acumatica@acumatica-claude-kit
```
Then reload so the skill is active this session: `/reload-plugins` (or restart Claude Code).

**From a git host (teammates / other machines):**
```
/plugin marketplace add hallboys/acumatica-claude-kit
/plugin install acumatica@acumatica-claude-kit
```

**Update later:**
```
/plugin marketplace update acumatica-claude-kit
```

## Maintaining it

See [CONTRIBUTING.md](CONTRIBUTING.md) — the entry template, tagging rules, version discipline,
identifier-scrubbing, and how to cut a new plugin version so updates propagate.

## Scope & disclaimer

Not affiliated with or endorsed by Acumatica. Entries reflect behavior observed on specific versions
(noted per entry) — **always verify against your own Acumatica version and edition** before relying on
a `[UNIVERSAL]` claim. Contributions must contain **no** secrets, credentials, hostnames, or
tenant-identifying values.

## License

[Apache License 2.0](LICENSE) © 2026 Hall Boys, Inc. See [NOTICE](NOTICE).
