# Inspectra Mobile — Inspection Flow Rework

> **Read this first in every new session.** It is the contract. If something here
> contradicts what you remember, this file wins. Update it when a decision changes.

Repo: `josiahcustodio/inspectra-mobile`, branch `main`
Path: `Downloads/Inspectra/Inspectra Firebase/clowtec_inspector/`
Baseline commit: `d6e2eb1` (clean tree, 2026-10-01)

Related repos (NOT in this repo — do not edit them from a mobile session):

- Web admin — `Downloads/Inspectra/File processing task/` (`inspectra-web`)
- Docs — `Downloads/Inspectra/docs/code-walkthrough/mobile/*.md` + docx build

---

## 1. Decisions (locked 2026-10-01)

| # | Decision | Chosen |
|---|---|---|
| D1 | Mobile-visible establishment fields | **Business Name, Owner Name, Address only.** Hide `barangay`, `personnel_count`, `personnel_with_hc`, `sanitary_permit_no`, `control_no`, and the category badge. |
| D2 | Create / edit establishments on mobile | **Removed entirely.** The web admin is the sole owner of establishment data. |
| D3 | Establishments tab | **Kept, read-only browse.** Tapping a row starts an inspection; it no longer opens an editor. |
| D4 | Category selection | **Chosen at inspection time**, not bound to the establishment beforehand. |
| D5 | Where the chosen category is stored | **On the inspection log only.** The app never writes to `establishments`. |
| D6 | Category suggestion source | **Offline keyword rules** over the business name. Deterministic and explainable — this is a government audit trail. |
| D7 | Finish-time integrity | **Detect and flag**, not prevent. Monotonic anchor when available, device clock otherwise, evidence always recorded. |
| D8 | Server-side enforcement | **Firestore rules only. No Cloud Functions.** Project stays on the Spark plan. |
| D9 | No trusted anchor available | **Allow submission, mark unverified.** An inspector in a dead zone is never blocked. |
| D10 | Web admin changes | **Planned here, built in a separate session** (Chunk 5). One repo per session. |
| D11 | Documentation output | Update `docs/code-walkthrough/mobile/*.md` + `parts/mobile_learn.md`; rebuild the docx once at the end. |
| D12 | Record `started_at` | **Yes.** Captured when the inspection form opens. Same trust treatment as the finish time. |
| D13 | Timestamp storage format | **Firestore `Timestamp`**, not ISO strings, for all new time fields. See 2.2. |
| D14 | Timestamp display format | **12-hour with AM/PM** (`2:32 PM`) in both apps. |
| D15 | QR scanner | **Kept.** It reaches an establishment read-only, so it does not conflict with D2. |
| D16 | Banner placement | **Live inspection form only** — not the details or history screens. |
| D17 | `establishments` write rule | **Stays `isAuthorized()`.** V1 investigation found the web admin lets officers create and edit. Narrowing to `isAdmin()` would lock them out. Mobile not writing is enforced by the absence of any write call, not by rules. |
| D19 | Pre-Chunk-1 offline-created establishments | **Preserved locally for one release, never pushed.** `syncData` keeps a `!isSynced` bridge so an upgrading device does not lose a record the old add screen promised to sync. Not drained to Firestore — that would be the mobile write D2 removes. Bridge is deleted in Chunk 6. |
| D18 | Dirty `categories` data | **Cleaned before the picker is built** (new Chunk 2.5), from the web/admin session. The picker then reads clean data with no special-casing. |

---

## 2. The time-integrity design

### 2.1 Why this shape

`DateTime.now()` follows the device settings clock, so an inspector can backdate a
late inspection just by changing it. Dart has **no clock that survives the app
process**: `Stopwatch` is monotonic but resets when the app is killed. Without native
platform code there is no way to *prevent* a backdated finish time. So this design
makes tampering *visible* instead, and records enough evidence that a reader can tell
the difference.

```
App launch WITH signal   fetch server time, start Stopwatch  ->  anchor LIVE
drive to site, lose signal, inspector changes the device clock
tap "Finish"             finished_at = anchor + elapsed      ->  clock change is inert
                                                                 time_source: anchored

app killed / phone rebooted while still offline
tap "Finish"             finished_at = device clock          ->  flagged, not prevented
                                                                 time_source: device_unverified
```

The anchored path covers the realistic field case: leave the office online, inspect,
come back. The reboot gap is an accepted and documented limitation — revisit it with a
native `SystemClock.elapsedRealtime()` channel only if it proves to matter in practice.

### 2.2 Field contract on `inspection_logs`

Additive only. Every existing field keeps its current meaning, so the web admin does
not break before Chunk 5 lands.

| Field | Type | Written by | Meaning |
|---|---|---|---|
| `inspection_date` | string | app | **UNCHANGED.** Legacy zone-less local wall clock. Existing readers keep working. |
| `started_at` | Timestamp | app | When the inspector opened the inspection form. Immutable after first write. |
| `finished_at` | Timestamp | app | **The highlighted time.** When submit was tapped. Immutable after first write. |
| `time_source` | string | app | `anchored` or `device_unverified`. Applies to both start and finish. |
| `clock_anchor` | map or null | app | `{ server_time, device_time_at_anchor, elapsed_ms_at_anchor }` |
| `elapsed_ms_at_start` | int or null | app | Stopwatch reading at form open. Null when there is no anchor. |
| `elapsed_ms_at_finish` | int or null | app | Stopwatch reading at submit. Null when there is no anchor. |
| `device_time_at_finish` | Timestamp | app | The raw device clock at submit, recorded even when anchored. Drift = this minus `finished_at`. |
| `uploaded_at` | Timestamp | **server** | `FieldValue.serverTimestamp()`, forced by rules to equal `request.time`. The app cannot fake it. |

**Why `Timestamp` and not the ISO strings the app writes today.** A `Timestamp` is a
true instant, so the web no longer has to guess whether a value is a wall clock or an
instant — the whole hazard `src/lib/inspectionDates.ts` was written to work around.
Every CHO device is UTC+8 with no DST, and in the anchored path the instant comes from
the server anyway, so it stays correct even if the inspector changed their device
timezone. A client can write a `Timestamp` for an arbitrary moment while offline, so
this costs nothing in the offline queue. The zone-less convention stays confined to
the legacy `inspection_date` field; new fields must not inherit that problem.

**Display rule (D14).** All of these render as 12-hour with AM/PM — `2:32 PM`. The
web's existing `isoTimePart` returns 24-hour (`14:32`); Chunk 5 adds a separate
12-hour formatter rather than changing that helper, which other screens still use for
legacy records.

The trust verdict is **not stored** — it is derived at read time from the evidence, by
mirrored helpers (`lib/core/time_trust.dart` on mobile, `src/lib/timeTrust.ts` on web).
Storing a verdict the client computed would just be the client marking its own homework.

**`started_at` strengthens the drift check.** With only a finish time, an anchored
record and a tampered one can look alike. With both ends recorded, the plausibility of
the elapsed duration becomes checkable: a sanitary inspection that claims to have run
for four seconds, or for nine hours, is visible as an anomaly regardless of what the
device clock said.

### 2.3 Rules to add

```
match /inspection_logs/{logId} {
  // uploaded_at must be the server's own clock, not anything the client chose.
  allow create: if isAuthorized()
    && request.resource.data.uploaded_at == request.time;

  // A sync retry may refresh uploaded_at, but never rewrite the time evidence.
  allow update: if isAuthorized()
    && request.resource.data.uploaded_at  == request.time
    && request.resource.data.started_at   == resource.data.started_at
    && request.resource.data.finished_at  == resource.data.finished_at
    && request.resource.data.time_source  == resource.data.time_source;
}
```

Note the interaction with the `SetOptions(merge: true)` retry path in `SyncService`:
the retry writes a *new* `serverTimestamp()`, which the create rule would reject but
the update rule above allows. This must be covered by a rules test.

---

## 3. Chunks

Each chunk is one session. Do not start the next chunk in the same session as the
previous one — see section 5.

### Chunk 1 — Read-only establishments + field trim

**Goal:** D1, D2, D3.

| File | Action |
|---|---|
| `lib/ui/screens/add_establishment_screen.dart` | Delete (753 lines). It doubles as the edit screen today. |
| `lib/core/router/app_router.dart` | Remove `/establishments/add` and `/establishments/edit`. |
| `lib/ui/screens/establishments_screen.dart` | Drop the `+` button. Row tap starts an inspection. Show name / owner / address only. Search across those three. |
| `lib/ui/widgets/new_inspection_modal.dart` | Drop "Add New Establishment Manually". Subtitle becomes the owner name, not `barangay • #shortId`. |
| `lib/data/services/sync_service.dart` | Remove `insertEstablishment`, `updateEstablishment`, `deleteEstablishment`, `syncPendingEstablishments`. |
| `lib/data/services/offline_service.dart` | Remove `updateEstablishment` / `deleteEstablishment`. **Correction — the preservation branch in `syncData` is NOT dead.** This plan called it dead on the premise that mobile no longer creates establishments, but the Hive box outlives the binary: a device upgrading from a build that still had the add screen can hold an offline-created record, and `syncData()` runs unconditionally at launch, so `estBox.clear()` would destroy the only copy of it. Keep the branch as a one-release bridge per D19, marked `[REF: ESTABLISHMENT_UPGRADE_BRIDGE]`. Also, **in the same function**, parse each Firestore snapshot fully *before* clearing its box, for establishments and templates alike — `fromJson` casts, so one type-drifted document threw after the box was already empty, leaving the device with no establishments (or, worse, no checklists, so a zero-item inspection form) while the `catch` logged that it was "relying on local cache". Pre-existing; in scope because it defeats the offline guarantee the chunk depends on. |
| `lib/ui/screens/qr_scanner_screen.dart` | Drop the "Can't find it? Add New Establishment" link (dead route). Suggestion subtitle becomes the owner name — it rendered `'ID: … • category'`, which D1 forbids. **Added to this chunk during review**: a kept screen still showing a hidden field means the chunk only appears to meet D1. |
| `lib/providers/pending_inspections_provider.dart` | Drop the `syncPendingEstablishments()` call and the unsynced-establishment term in `_loadPendingCount` (it can only be 0 now). Incidentally fixes a real `RangeError`: `pending_card.dart:183` used `pendingCount` as `itemCount` while indexing the inspections-only `pendingItems`. |
| `lib/data/models/establishment.dart` | Remove `toJson()` only — its callers were the three removed `SyncService` methods and the deleted screen. **No `@HiveField` touched**; `establishment.g.dart` unchanged. |
| `lib/ui/widgets/animations/` | Delete both widgets. The deleted add screen was their only consumer; nothing imports the directory. |
| `firestore.rules` | **No change — V1 resolved, see D17.** The rule stays `isAuthorized()`. Record the reason as a comment on the `establishments` match block so a later reader does not "tighten" it and break the web app. |

**Hard constraint — do not break the Hive box.** `Establishment` is
`@HiveType(typeId: 0)` with fields 0–13 already written to every inspector's device.
Removing a `@HiveField` corrupts existing boxes on upgrade. Fields that become unused
(`isSynced`, `personnelCount`, `sanitaryPermitNo`, …) stay declared on the model and
simply stop being read by the UI. Only `Establishment.toJson()` becomes genuinely dead
and may go.

### Chunk 2 — Persistent establishment banner

**Goal:** requirement 4.

| File | Action |
|---|---|
| `lib/ui/widgets/establishment_banner.dart` | New. Business name, owner, address. Pinned. |
| `lib/ui/screens/inspection_form_screen.dart` | Mount the banner above `_buildStickyScoreHeader`. Both stay pinned while the checklist scrolls. |

**Watch the vertical budget. Corrected measurement:** the score header is **~96pt**
once a score exists, not 76pt — a 48pt figure at `height: 1.0`, a ~14pt band label and
32pt of padding (~84pt before the first answer, where the figure is 36pt). It grows with
the system text scale, because the score column is always its tallest child and nothing
caps that text. Both numbers were verified twice, independently, against
`_buildStickyScoreHeader`.

A second pinned block on a small phone can leave very little checklist visible. The
banner may shrink on scroll (address collapsing to one line, then dropping), but the
business name must never leave the screen **while the inspector is scoring**.

**The one exception, and why it exists (`[REF: BANNER_KEYBOARD_YIELD]`).** The body is
`Column[banner, scoreHeader, Expanded(checklist)]`, and the two pinned children are
inflexible — so when they exceed the body height the `Expanded` is clamped to zero and
the checklist is clipped outright, silently in release. That is reachable: 320x568 at
text scale 2.0 with the keyboard open for the remarks field leaves ~276pt against ~285pt
of chrome. The banner therefore withdraws **entirely** while `viewInsets.bottom > 0`,
rather than merely shrinking, which hands back the ~118pt the form had before the banner
existed and keeps the focused field scrollable into view.

**Correction — this yield is not confined to text entry, as first assumed.** Marking a
checklist item FAIL reveals a *required* deficiency-notes `TextFormField` inline,
mid-checklist (`checklist_item_card.dart`), so the keyboard genuinely does open while the
inspector is scoring — during the most consequential write on the screen. The first
implementation paired the yield with a genericised app bar title, which left **nothing**
on screen naming the business at that moment. So the app bar keeps its own copy of the
business name: it sits outside the body `Column`, costs the checklist no vertical space,
and never yields. **That app-bar copy, not the banner, is what actually satisfies the
never-lose-the-name rule.** The banner is the readable primary; the app bar is the
backstop. Do not "de-duplicate" them.

Decided 2026-10-01 after review. A sliver-based implementation was rejected because
`SliverPersistentHeaderDelegate` demands fixed `minExtent`/`maxExtent` and neither block
has a knowable height. The `viewInsets` read must stay above the `Scaffold` — `Scaffold`
strips the bottom inset from its own body, so the same call from inside the body reads a
constant zero and fails silently.

### Chunk 2.5 — `categories` data cleanup (separate repo/session, D18)

**Goal:** make `categories` fit to drive a picker. Chunk 3 depends on this.

Live state as measured on 2026-10-01 (read-only probe, service account):

```
categories — 10 docs, 3 distinct names
  '1' Food    '2' Water    '3' Institutional
  '4'..'10'   Food                      <- 7 duplicate "Food" docs

checklist_templates — 20 items each for category_id '1','2','3' ONLY
  so category_id '9' ("Food") has zero templates ...
  ... and 14 of 21 establishments point at '9'

no catch-all doc. "Others" and "Swimming Pool and Bathhouse" exist only as
free-text `category` strings with category_id = null (1 establishment each)

type drift — 3 establishments store category_id as the NUMBER 1, not '1'
```

| Action | Notes |
|---|---|
| Delete the 7 duplicate `Food` docs (`4`–`8`, `10`, and `9` last) | Keep `'1'`, `'2'`, `'3'` — the only ids with templates. |
| Repoint the 14 establishments off `category_id '9'` onto `'1'` | They are already named `Food`; this is the move that makes a checklist appear for them. |
| Normalize `category_id` to a **string** everywhere | 3 establishments hold the number `1`. Any string-keyed lookup misses them today. |
| Decide `Others` / `Swimming Pool and Bathhouse` | 2 establishments carry these as free text. Either add real category docs with templates, or map them onto an existing category. Not a silent drop. |
| One-off admin script, not app code | Run from the web/admin session. The mobile app never writes `establishments` (D2) or `categories` (rules already `isAdmin()`). |

**One hazard to close while you are in there.** `SyncService.fetchCategories` already
dedupes by name, but it keeps the *first* doc id seen per name. Only ids `1`-`3` have
templates, so the picker is correct today only because Firestore returns doc ids in
lexicographic order and `'1'` sorts ahead of `'10'` and `'4'`. Deleting the duplicates
removes the coincidence this relies on.

Establishment `category` / `category_id` stay on the documents — Chunk 3 stops *reading*
them for the inspection (D4), but the web admin still shows the category badge, so this
is a cleanup, not a removal.

### Chunk 3 — Category picked at inspection time

**Goal:** D4, D5, D6.

| File | Action |
|---|---|
| `lib/core/category_suggester.dart` | New. Pure Dart keyword rules, no Flutter import, unit-testable. |
| `lib/ui/widgets/category_picker.dart` | New. `DropdownMenu` with `enableFilter` + `requestFocusOnTap` gives type-to-filter natively — no new package. |
| `lib/data/services/offline_service.dart` | Persist `categories` into a new Hive box. Today `syncData` fetches them but only builds a throwaway name map, so the picker would be empty offline. |
| `lib/ui/screens/inspection_form_screen.dart` | `_templates` becomes state driven by the picked category, **not** `initState` reading `widget.establishment.category` (currently line 46). |
| `lib/providers/rating_provider.dart` | Needs a re-`init` / reset path — switching category after answering items must not leave stale answers behind. |
| `lib/data/models/inspection_log.dart` | Add `categoryId`, `categoryName`. |

**Depends on Chunk 2.5.** Built against the cleaned collection, so the picker needs no
dedupe-by-name or has-templates filtering of its own.

**The empty case is real** — and it is not hypothetical. Before the Chunk 2.5 cleanup,
14 of 21 establishments pointed at a category with zero templates. If the picked
category has no templates, the form today renders "No checklists found for this
category." and still lets you submit a zero-item inspection. Submission must be blocked
with a clear message, cleanup or no cleanup.

### Chunk 4 — Trusted finish time

**Goal:** D7, D8, D9. Full design in section 2.

| File | Action |
|---|---|
| `lib/core/trusted_clock.dart` | New. Anchor fetch, Stopwatch, `now()` returning `(DateTime, TimeSource)`. |
| `lib/core/time_trust.dart` | New. Read-time verdict from the evidence fields. Mirror of the web helper. |
| `lib/core/time_format.dart` | New. The single 12-hour AM/PM formatter (D14). Nothing else formats a time by hand. |
| `lib/data/services/offline_service.dart` | Persist the anchor in the existing `app_prefs` box. |
| `lib/data/services/sync_service.dart` | `uploaded_at: FieldValue.serverTimestamp()`. Refresh the anchor on every successful sync. |
| `lib/data/models/inspection_log.dart` | New fields per section 2.2. Note these are `Timestamp`, so `toQueueJson` must serialize them for Hive and `fromJson` must read both a `Timestamp` and the JSON form back. |
| `lib/ui/screens/inspection_form_screen.dart` | Capture `started_at` in `initState`. Capture `finished_at` the moment submit is tapped, before any `await`. |
| `lib/ui/screens/inspection_details_screen.dart` | Finished-at prominent, started-at and uploaded-at secondary, badge when unverified. |
| `firestore.rules` | Per section 2.3, plus rules tests in `firestore-tests/`. |

**The offline queue needs care here.** The queue stores each log as a JSON **string**
in Hive (`inspectionsQueueBox`), and a Firestore `Timestamp` is not JSON-serializable.
`toQueueJson` must write these as epoch millis and `fromJson` must accept both that
and a real `Timestamp`, since the same model is also built from live Firestore reads.
Getting this wrong fails only on the offline path, which is the path least likely to
be exercised by hand — so it needs a test, not just a once-over.

### Chunk 5 — Web admin alignment (separate repo, separate session)

`src/lib/models.ts`, `src/lib/firestore.ts`, new `src/lib/timeTrust.ts`,
`src/lib/inspectionDates.ts`, `Inspections.tsx`, `InspectionChecklistView.tsx`,
`EstablishmentHistoryModal.tsx`. Finished-at becomes the headline column; started-at
and uploaded-at are secondary; unverified records get an amber badge. Fall back to
`inspection_date` for records written before Chunk 4.

Two specifics:

- Add a 12-hour AM/PM formatter (D14). Do **not** change `isoTimePart` — it returns
  24-hour today and legacy screens still read `inspection_date` through it.
- `inspectionDates.ts` detects wall-clock-vs-instant from the string shape. The new
  fields arrive as Firestore `Timestamp` objects, not strings, so they need their own
  path rather than being squeezed through `localParts`.

### Chunk 6 — Docs rebuild + regression pass

**Delete the upgrade bridge first.** Remove `[REF: ESTABLISHMENT_UPGRADE_BRIDGE]` in
`offline_service.syncData` — the `strandedKeys` capture and the delete-by-key dance it
guards (D19). By Chunk 6 one release has shipped without the add screen, so no device
can still be creating establishments locally, and a plain `clear()` + `putAll` becomes
genuinely safe again.

**The bridge ships unexercised.** Nothing in `test/` touches `Establishment` or
`syncData`, and the upgrade path by definition cannot occur on a fresh install, so it
will never have run before release. Verify it by hand once, before deleting it: with the
*old* build, create an establishment in airplane mode; confirm it is in the box; install
this build; launch; confirm the record is still listed and that no establishment the
server still has went missing.

Two docs-build chores inherited from Chunk 1, both already half-done:

- `build.py`'s walkthrough list had `add_establishment_screen.dart` and `animations`
  removed in the Chunk 1 session (it hard-fails on a missing file rather than skipping),
  and `mobile_learn.md` was renumbered to match. Those two are consistent now — do not
  "fix" one without the other.
- `build.py`'s `MOBILE_E` still omits `rating_scale.dart`, so that walkthrough never
  reaches the docx. Pre-existing, unrelated to this rework; add it while you are in there.

Regenerate the docx via `docs/_codedocu_build/build.py`, run a full `flutter analyze`,
and do a manual pass on a real device:

1. Airplane mode, run an inspection end to end, confirm it queues.
2. While still offline, move the device clock forward two days, submit another.
3. Re-enable the network. Both sync. The clock-changed one is flagged
   `device_unverified` only if the app was killed between anchor and submit —
   otherwise it stays `anchored` with the correct time and a visible drift.
4. Confirm every time on screen reads 12-hour with AM/PM (D14), in both apps.
5. Confirm `started_at` and `finished_at` survived the Hive queue round-trip
   with the right values, not epoch zero.
6. Establishments and checklists both still populate after a sync, and a record
   deleted in the web admin disappears from the mobile list on the next launch —
   the delete-by-key path from Chunk 1 is what makes that non-obvious.

---

## 4. Multi-agent protocol

Three roles, **strictly sequential within a chunk**. Subagents share one working tree,
so a coder and a reviewer running at the same time would read each other's
half-finished state.

```
  chunk spec (this file)
          |
          v
   [1] CODER         general-purpose  -- writes code, commits nothing
          |
          v
   [2] REVIEWER      general-purpose, FRESH context
          |           -- reads the diff, never the coder's reasoning
          |
     findings -> orchestrator applies fixes -> re-review if anything was structural
          |
          v
   [3] DOCUMENTER    general-purpose  -- updates walkthroughs after the code settles
          |
          v
   orchestrator: flutter analyze, then commit
```

**Why the reviewer gets a fresh context rather than a fork:** a fork inherits the
coder's rationalizations and will tend to agree with them. The reviewer must see only
the chunk spec and `git diff`, and be told to assume the code is wrong until it proves
otherwise.

### Standing brief — CODER

- Scope is the file list in the chunk. Touching a file outside it means stopping and
  reporting why.
- **The comment convention is non-negotiable.** This codebase anchors comments with
  `// [REF: TAG]` markers that the walkthrough docs reference by name. Follow it.
  Comments explain *why*, never *what* the next line does. Match the density of the
  surrounding file.
- Never remove a `@HiveField` from a model that already ships in a released box.
- Firestore changes are additive only. Never rename or repurpose an existing field.
- Do not run `git commit`.

### Standing brief — REVIEWER

Inputs: this file's chunk section, and `git diff`. Nothing else. Check in this order:

1. Hive schema safety — any removed or renumbered `@HiveField`?
2. Offline correctness — does it still work in airplane mode, and does the queue still drain?
3. Firestore contract — anything non-additive, or any field the web reads whose shape changed?
4. Does the diff actually satisfy the chunk goal, or only appear to?
5. Dead code left behind by a removal.
6. Comment convention followed — and are the comments actually true?

Report findings most-severe-first with `file:line`. Say plainly when a chunk is clean;
do not invent findings to look thorough.

### Standing brief — DOCUMENTER

- Update the affected `docs/code-walkthrough/mobile/*.md`; create new ones for new
  files using `_TEMPLATE.md`.
- Update `docs/_codedocu_build/parts/mobile_learn.md`.
- Delete the walkthrough for any deleted source file.
- Do not rebuild the docx — that happens once, in Chunk 6.
- Document what the code *does now*, never what the plan said it would do.

---

## 5. Session hygiene

One chunk per session. At the end of a session: commit, then update section 6 with the
real state. At the start of a session: read this file and run `git log --oneline -5`
before anything else.

Stop and start a fresh session when any of these is true — the chunk is committed; the
context has been summarized once already; or an agent starts citing files or decisions
that are not in this document.

## 6. State log

| Date | Chunk | Status |
|---|---|---|
| 2026-10-01 | 0 — planning | Decisions D1–D16 locked. Plan written. No application code touched. V3/V4/V5 resolved; V1/V2 deferred to the top of the Chunk 1 session. |
| 2026-10-01 | V1/V2 | Both resolved by investigation. V1 → D17 (rule stays `isAuthorized()`; the web admin lets officers write). V2 → D18 + new Chunk 2.5 (`categories` is authoritative but dirty: 8 duplicate `Food` docs, templates only on ids 1–3, no catch-all, `category_id` type drift). |
| 2026-10-02 | 2 — establishment banner | **Committed.** New `establishment_banner.dart` with a three-step density ladder; mounted above the score header on the live form only (D16), name/owner/address only (D1). Review corrected the plan's 76pt score-header estimate to **~96pt** and found that the `Column`/`Expanded` body clips the checklist outright at 320x568 / scale 2.0 with the keyboard up — hence `[REF: BANNER_KEYBOARD_YIELD]` and the deliberate app-bar name duplication that backs it. `flutter analyze` clean. Docs + new walkthrough at §E.32. **No device or emulator run — every pixel figure in this chunk is derived from source, not observed, and `densityFor` has no test.** |
| 2026-10-01 | 1 — read-only establishments | **Committed.** D1/D2/D3 done. Add/edit screen and both routes deleted; create/edit unreachable from all five entry points; UI trimmed to name/owner/address. Review found two real defects beyond the spec: the "now-dead" preservation branch was not dead (→ D19 upgrade bridge) and `qr_scanner_screen` still rendered the category. `syncData` now parses before clearing, for establishments and templates both. `flutter analyze` clean (2 pre-existing infos in `profile_screen.dart`). Docs + README updated. **Not run on a device.** |

## 7. Open items

**Next session is Chunk 2.5, and it is in a different repo** (`inspectra-web` / the admin
scripts), not here. Chunk 3 must not start before it lands — it is what makes the
category picker's data fit to pick from.

Carried forward, none blocking:

- **Chunks 1 and 2 have never run on a device.** Both were analyzer-clean and
  review-clean, but every layout figure in Chunk 2 is computed from source rather than
  observed, and Chunk 1's upgrade bridge cannot occur on a fresh install. The Chunk 6
  device pass is the first time either is exercised.
- **`assets/data/batangas_psgc.json` is orphaned.** The deleted barangay picker was its
  only consumer and nothing in `lib/` loads any asset now, but it is still declared in
  `pubspec.yaml`. Dropping both is a free size win; left alone because `pubspec.yaml` was
  outside Chunk 1's scope.
- **`EstablishmentBanner.densityFor` is pure and static specifically to be testable, and
  has no test.** The hysteresis arithmetic it encodes was wrong once already.

V1 and V2 were resolved at the top of the Chunk 1 session, as planned.

### Resolved

- ~~**V1** does the web admin create establishments as `admin` or `officer`?~~ — **as
  `officer`, among others.** `src/app/routes.tsx` mounts the same `Establishments` page
  under both the `admin` and the `officer` branch, and `Establishments.tsx:40` (Add) and
  `:132` (Edit) are not role-gated — both call `saveEstablishment`
  (`src/lib/firestore.ts:128`, `[REF: ESTABLISHMENT_WRITE]`). Every self-signup is
  `officer`: the `profiles` create rule pins `role == 'officer'`, and
  `useAuth.tsx:60-69` falls back to `officer`. So narrowing the rule to `isAdmin()`
  would have locked officers out of the web admin. **Rule stays `isAuthorized()`** —
  see D17.
- ~~**V2** is `categories` authoritative, and is there a catch-all?~~ — **authoritative
  but dirty, and no catch-all.** Measurements and the cleanup it forces are in Chunk
  2.5; the decision to clean before building the picker is D18.
- ~~**V3** record `started_at`~~ — yes. See D12. Captured at form open.
- ~~**V4** keep the QR scanner~~ — yes. See D15.
- ~~**V5** banner on details/history~~ — no, live form only. See D16.
