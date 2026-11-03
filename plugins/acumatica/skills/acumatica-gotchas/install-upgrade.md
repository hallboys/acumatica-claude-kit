# Self-hosted Install, Patching, Snapshots, Upgrades & Customization Publishing

Running Acumatica yourself (or restoring a SaaS snapshot into a self-hosted sandbox) and moving
customizations across releases. See the tag legend in [SKILL.md](./SKILL.md).

---

### Customization publishing is **site-wide** — a TEST tenant on the same site is not a sandbox `[UNIVERSAL]` (which tenants share a site `[TENANT]`)
- Code items (DLLs, pages, DACs, code, files) are shared by every tenant on a site. Publishing in **any**
  tenant applies site-wide and unpublishes previously published projects in all tenants that aren't in the
  publish set (Administration Guide; Customization Guide). Unpublishing does not revert database changes.
- A tenant whose Customization Projects list is **empty** may still run customizations uploaded from
  another tenant.
- A restored/snapshot tenant keeps the **External File Storage** (SM202540) settings, which point at the
  **production** container: with *Allow Saving Files* off, deletes orphan blobs; with it on, they delete
  production blobs. SM202540 also shows the storage key on screen.
- **Do:** test customizations on a separate site; check SM202540 on any restored tenant before file operations.
- *Verified: 25R2 doc set + read-only observation on a 25R2 SaaS site, 2026-10.*

### Self-hosted install hangs on the **bundled RabbitMQ installer** when run as SYSTEM `[UNIVERSAL]`
- `ac.exe -configmode:"NewInstance"` (like the wizard) first installs Erlang and RabbitMQ from
  `Data\Components\`. The bundled RabbitMQ installer is **32-bit**: run as SYSTEM (remote-run agent,
  scheduled task, `psexec -s`), WOW64 redirection puts its base folder under
  `C:\Windows\SysWOW64\config\systemprofile\AppData\Roaming\RabbitMQ`, while the 64-bit service it
  registers uses `System32\config\systemprofile\…`.
- Result: the service dies ~3 s after start (exit 1067, no log), the installer waits forever, ac.exe waits
  on it — no database, IIS app or site is created and no error is reported.
- **Do:** create `C:\Windows\System32\config\systemprofile\AppData\Roaming\RabbitMQ`, start the `RabbitMQ`
  service, and rerun with `-skiprabbit:"False"` (with the broker running, ac.exe skipped the stage). End
  ac.exe **before** the installer when cleaning up a hung run.
- Side effect: ac.exe disables Windows Firewall notifications on all profiles. The 26R2 parameter list no
  longer documents `-skiprabbit`; the 26R2 wizard can connect to an existing broker.
- *Verified live: 25R2 self-hosted (RabbitMQ 3.13.5, Windows Server 2022), 2026-10-26.*

### The patch level is the **4th version field** and is in no file version; PatchTool is a separate download `[UNIVERSAL]`
- Help > About shows `<build>.<patch>` (e.g. `25.201.0213.7`). MSI ProductVersion and the `ac.exe` /
  `PX.Data.dll` file versions carry only the 3-field build and don't change when a patch is applied.
  PatchTool names patches `<build>-<n>`.
- The **25R2 MSI does not install PatchTool** (the guide says `Data\`); download it from
  `https://update.acumatica.com/rest/api/patch/tool` (`PatchTool.exe` is signed; many bundled DLLs are not —
  that is how it ships). The 26R2 MSI ships it in `Data\PatchUtility\`.
- `PatchTool check --path <instance>` exits **1** when a patch is available, 0 when none (undocumented).
  Online `patch` applies only the **latest** patch; matching an older production patch level needs the
  archive from Acumatica support (`--archive`). `patch --zip <file>` writes a rollback backup.
- The 25R2 install root is `C:\Program Files\Acumatica ERP`, **not** `(x86)` as the Installation Guide
  states. The release notes require the latest patch after an upgrade.
- *Verified live: 25R2 and 26R2 self-hosted (PatchTool 1.19.2.0), 2026-10.*

### Wizard snapshot restore: build-level version check, **silent partial imports**, and a tenant that starts sending immediately `[UNIVERSAL]`
- Snapshots over 1 GB restore only through the Configuration Wizard (Tenant Setup → Insert Data), XML
  format, from `…\Acumatica ERP\Database\Data`; the wizard lists only the **extracted** folder, not the
  `.zip` (~3 GB zipped was ~60 GB of XML). Overwrite in place via Maintain Tenants → Advanced → Insert Data.
- `manifest.xml` records the **build without the patch level**: a patch-7 snapshot restored into a patch-8
  instance of the same build.
- **Silent partial import:** if a snapshot column is longer than the destination column (a source
  customization widened it), the wizard offers **Ignore** — and Ignore **ends the import**: every later table
  (roughly alphabetical) stays unloaded, yet the wizard reports done. Tables with no destination
  (unpublished customization/ISV tables) are skipped silently.
- **The restored tenant acts like production as soon as the site starts:** automation schedules ran within
  hours, queued hundreds of emails and attempted push notifications. There's no bulk deactivate (SM205020,
  SM302000, SM302050, SM304000 are per-record); SM205030 "Initialize Scheduler" reactivates schedulers after
  a restore from another site. Queued emails go out the moment an email account is re-enabled.
- **Do:** publish the source's customization projects before restoring and never click Ignore; compare
  per-table `<row>` counts against `COUNT(*)` afterwards; block egress before the first site start and
  disable email (SM204002, SM204015), notifications (SM302000, SM204004, SM203535), CA205000, CA205500,
  TX102000 and ISV callouts.
- *Verified live: 25R2 self-hosted, 2026-10-26/27.*

### A snapshot carries customization project **records**, not their files — republish from deployment packages `[UNIVERSAL]`
- The restored tenant gets the source's `CustProject`/`CustObject` rows, but an export excluding attachments
  omits the file storage their File items point to: publishing fails with *"Cannot access the uploaded file.
  Failed to get the latest revision of the file <guid>"*.
- The restored script-history rows mark the source's DB scripts as already executed, so a publish may skip
  scripts that never ran on this database.
- **Do:** export deployment packages from the source (SM204505), import each with **Replace Highlighted
  Project Content**, and publish with **Publish to Multiple Tenants → Execute All Database Scripts
  (Including Previously Executed)**.
- *Verified live: 25R2 self-hosted, 2026-10-27.*

### `ac.exe DBMaint` + `UpgradeSite` skip customization validation — then **none** of the published projects applies `[UNIVERSAL]`
- A major upgrade can't go through Apply Updates (SM203510); run DBMaint, then UpgradeSite. Neither
  validates customizations. At first site start the published projects are re-applied as **one merged set**:
  a single incompatible DLL (*"Failed to resolve type/method reference"*) fails validation and the site runs
  **plain** (no custom DLLs, pages or code; custom DB columns remain). The sign-in page shows the log.
- **Do:** unpublish all → upgrade → publish projects validated on the new release. Confirm what applied by
  comparing `Bin` with the site template and checking `CstPublished`.
- Benign upgrade-log noise: ~85 `[OEM] … Could not find assembly 'netstandard, Version=2.0.0.0'` WRN lines
  per step; `MultiSiteModeMigration finished with result: False` on a single-site instance; *"Table
  AppRestartRequest does not have a primary key"*. **Not benign:** `PivotMigrationException` for a pivot
  table with duplicate views — pivot tables become GI views in 26R2 and that one must be recreated.
- Planning: DBMaint 72 min + UpgradeSite 20 min on a ~70 GB database. 26R2 needs IIS Integrated pipeline
  and SQL Server 2022/2025, and upgrades directly from 25R1/25R2/26R1. A release's developer notes start
  from one prior build, so changes in builds between yours and that baseline appear in neither set.
- *Verified live: 25R2 → 26R2 (26.200.0334) self-hosted, 2026-10-28.*

### 2026 R2 republish blockers for 25R2-era customization projects `[UNIVERSAL]`
- **MSDL mobile scripts** built for the Classic UI block the publish ("… Run the Adapt for Modern UI
  action"): Project Editor → Mobile Application → More → Adapt All, then map leftovers with Element
  Inspector. Adapted scripts work only on 26R2.
- **A Modern UI HTML extension without a root `<template>`** → `ExtensionStructuralError` (25R2 likely
  ignored it). Fields added in a TS extension belong on a **view** class, not the screen class.
- **Removed APIs:** `PXCopyPasteData<T>` → `IPXPasteable<T> c = PXCopyPaste.CopyFrom(graph); … c.PasteTo(target);`
  (also `PXCopyPaste.Copy<T>(src, tgt)`, `FromTemplate(id)`). Namespace
  `PX.Objects.CN.Subcontracts.SC.Views` is removed (settings moved to the `SCSetup` DAC); a stale `using`
  alone breaks the compile.
- Act on, but not blockers: the inherited-workflow *version* warning (Screens → Workflows → Upgrade
  Predefined Workflow); *"The base property is missed or IBqlField is not defined: Usr…"* (a cache-extension
  property with no field attribute/BQL class).
- After a republish, `[A]X cannot be cast to [B]X` errors from two `RuntimeCode_*` assemblies → **Restart
  Application** (SM203510). Classic UI is off in 26R2; Classic-only screens open with a warning and 2027 R1
  removes them.
- *Verified live: 26R2 (26.200.0334) self-hosted, 2026-10-28.*

### Behind a reverse proxy, preserve the **Host** header — Acumatica builds absolute URLs from it `[UNIVERSAL]`
- OIDC discovery (`issuer`, `token_endpoint`, …) is built from the **request host**; if the proxy rewrites
  Host to an internal name, clients get unreachable URLs and issuer mismatches. (Paging links likely too —
  unverified.)
- The discovery `issuer` path came back **lower-cased** while `token_endpoint` kept the site's original
  case; the site path itself matched case-insensitively.
- **Do:** bind IIS and the certificate for the public name and pass Host through; validate `iss` against the
  discovered value, not a constructed one.
- *Verified live: 26R2 self-hosted, 2026-11-01.*
