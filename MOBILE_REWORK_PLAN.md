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
| D20 | Establishment `category` / `category_id` | **Removed from Firestore entirely**, in the session after Chunk 2.5 — this supersedes the "cleanup, not a removal" line that used to close Chunk 2.5. Replaced by a plain display string carrying the city's own business classification (`Line/Kind of Business` in the LGU masterlists: `Retailer (Ice cream)`, `Refreshment Parlor`), which deliberately does **not** feed the checklist pipeline. The historical scheme never matched the checklist types, which is why coupling them was wrong. |
| D21 | Source of `categories` and `checklist_templates` | **`Downloads/Inspectra/checklists.xlsx` is authoritative** for both category names and checklist items. 10 blocks: 9 `DEMERITS` forms of 20 items at weight 5 (20 x 5 = 100), plus Livestock Farm. Re-seeding is a scripted operation, never hand-entry. |
| D22 | Livestock Farm form model | **Seeded as its 13 numbered items only, at `weight: 0`.** The `COMPLIANT (  /  )` column is ruled against the numbered rows, so the 38 fill-in sub-lines are evidence for each mark, not separately scored items. No demerit weighting has ever been published for this form; inventing one to reach 100 would fabricate regulatory data. **Consequence: a completed livestock inspection currently displays 100 / Excellent.** Fixing that needs a per-category scoring mode — its own chunk, and a prerequisite nothing in this plan anticipated. |
| D23 | Source-document typos | **Preserved verbatim** so item text matches the paper form in an inspector's hand. Reported in the seeding transcript, never silently corrected. Known: `SANTARY TOILET FACILITIES` (Port 7), `DISINFECTION IF THE DISTRIBUTION SYSTEM` (Vessel 4), `EQUIPMENTS AND UTENSILS` (Vessel 10), `CARE AND PREPARATION FOOD` (Day Care 13), `Blogas Digester` (Livestock 6), plus pre-existing `Receptable` in live template `'54'`. |
| D24 | What the picker writes, and what the lookup matches on | **Both `category_id` and `category_name` on the inspection log; the in-app template lookup resolves by id.** Both on the log because the document is the audit record and is already deliberately self-describing — every `results[]` row denormalizes its `item_name`, `sub_category` and `weight`, and `establishment_name` is stored for the same reason. A bare `category_id: '15'` would be the only identifier on it a reader could not resolve, and it goes stale the moment a category is renamed, which Chunk 2.5 just did to two of them. The id is the machine key and the one identity in that collection that was never a lie (`'2'` was called `Water` while holding the SUPERMARKETS checklist). The **lookup** moved off the name because name matching is what made the duplicate `Food` docs dangerous: two categories sharing a name merge their templates into one form. That hazard is live — `'1'` and `'9'` are both `Food`, harmless only by accident because `'9'` has zero templates, and seeding one item onto `'9'` would silently have added an item to the real Food checklist. Costs `@HiveField(5) String? categoryId` on `ChecklistTemplate` (nullable so shipped boxes still deserialize) plus a one-release name fallback. |
| D25 | Livestock Farm in the picker, before scoring is fixed | **Shown, disabled, carrying its reason — not hidden, and not fixed here.** Excluded by the derived rule "every template in this category has weight 0, so `100 - totalDemerits` cannot produce a score", never by `id == '17'`: that states the actual reason, generalizes to any future unweighted form, and self-heals the day a weighting is published. Not fixed in Chunk 3 because a COMPLIANT/NON-COMPLIANT form has no percentage — an honest record needs a new `scoring_mode` field and a compliant-count, and the web admin has to learn to render it (different repo, Chunk 5). All three shortcuts fail: `percentage_rating: 100` keeps the exact lie D22 names, `0` invents a failing grade nobody gave, and `null` repurposes a field the web reads, which section 4 forbids. Shown rather than hidden because a missing row is indistinguishable from a failed sync. `'9'` falls out of the adjacent rule — a category with no local templates cannot be inspected. |

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

> **APPLIED 2026-10-02 — and this section's central premise was wrong.** What was
> actually done is in the table below; superseded rows are struck through so the
> correction stays legible. Section 6 has the verified end state.

**The premise that was wrong.** Nothing resolves a checklist by `category_id`.
`inspection_form_screen.dart:51-52` passes `establishment.category` — the **name
string** — into `OfflineService.getLocalTemplatesByCategory`
(`offline_service.dart:212`), which compares it case-insensitively against
`ChecklistTemplate.category`. `syncData` already rewrites each establishment's
`category` from the matching `categories` doc name, so the 14 docs on `'9'`
resolve to `Food` and have **always** found the 20 Food templates. They were never
broken, and repointing them would have repaired nothing. `category_id` was already
vestigial on this path — which is the real argument for D20.

Two further consequences of name-based lookup:

- Creating a category whose name matches an establishment's existing free-text
  `category` silently gives it a working form. `Brizamar beach resort`
  (`category='Swimming Pool and Bathhouse'`, `category_id=null`) went from an empty
  form to the new 20-item checklist with no establishment write at all.
- Two categories sharing a name **merge** their templates into one form. That is what
  made the 8 duplicate `Food` docs dangerous. `'9'` survives as a second `Food` only
  because it has zero templates; **adding templates to it would corrupt the real Food
  checklist.**

| Action | Outcome |
|---|---|
| Rename `'2' 'Water'` -> `Supermarkets` and `'3' 'Institutional'` -> `Public Places` | **Done.** Not in the original plan. Their 20 items each were already, verbatim, the xlsx's SUPERMARKETS and PUBLIC PLACES checklists — the names were lies. Neither had ever been used by an inspection, so correcting them was safe. |
| Delete 6 duplicate `Food` docs (`'4'`-`'8'`, `'10'`) | **Done.** Verified orphans — no establishment or template referenced any of them. |
| Seed the 7 missing categories + 133 templates from `checklists.xlsx` | **Done.** Not in the original plan, which assumed only 3 checklist types existed. |
| ~~Delete `'9'`~~ | **Deliberately NOT done.** 14 establishments still reference it and `establishments` was out of scope. Parked at `sort_order 999`. Deleting it is mobile-safe (`syncData`'s fallback leaves `category='Food'` intact); the only cost is the web admin's dropdown rendering empty when an officer edits one of those 14. Re-run with `--delete-nine`, or let the D20 session drop the field first. |
| ~~Repoint the 14 establishments off `category_id '9'` onto `'1'`~~ | **Not done, and not needed** — see the premise correction above. |
| ~~Normalize `category_id` to a string everywhere~~ | **Not done.** Out of scope once establishments were deferred; 3 docs still hold the int `1` and 2 hold null. D20 removes the field, so this is moot. |
| ~~Decide `Others` / `Swimming Pool and Bathhouse`~~ | **Superseded.** `Swimming Pool and Bathhouse` turned out to be a real checklist type in the xlsx and is now category `'11'` with 20 templates. `Others` was never a checklist type; `zafra` still opens an empty form, and D20 moves that string to the display-only column. |
| One-off admin script, not app code | **Done.** `inspectra-web` at `scripts/chunk25_categories_cleanup.py`, dry-run by default, `--apply` to write. Needed **no** web app code change. |

**One hazard to close while you are in there.** `SyncService.fetchCategories` already
dedupes by name, but it keeps the *first* doc id seen per name. Only ids `1`-`3` have
templates, so the picker is correct today only because Firestore returns doc ids in
lexicographic order and `'1'` sorts ahead of `'10'` and `'4'`. Deleting the duplicates
removes the coincidence this relies on.

~~Establishment `category` / `category_id` stay on the documents — Chunk 3 stops
*reading* them for the inspection (D4), but the web admin still shows the category
badge, so this is a cleanup, not a removal.~~ **Superseded by D20:** both fields come
off the documents entirely in the next session, replaced by a display-only business
classification string. The web admin reads `establishment.category` in three places
(`Establishments.tsx:113`, `EstablishmentHistoryModal.tsx:225`, and the whole category
dropdown in `AddEstablishmentModal.tsx`), so D20 is a web code change too.

### Chunk 3 — Category picked at inspection time

> **APPLIED 2026-10-02.** Section 6 has the verified end state; D24 and D25 record the two
> decisions this section did not anticipate. Two things it got wrong, kept legible rather
> than quietly edited:
>
> - **"the picker needs no dedupe-by-name or has-templates filtering of its own" is false.**
>   That followed from Chunk 2.5 deleting the duplicates — but `'9' 'Food'` was
>   deliberately *not* deleted, so a has-templates rule is required after all. (Dedupe by
>   name genuinely is not needed: ids carry identity now, per D24.)
> - The file table says `_templates` is read in `initState` at "line 46". It was lines
>   51-52.

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

### Chunk 7 — Inspector signature + delisted filter (spec added 2026-10-04)

**Goal:** the mobile half of the masterlist/signature design in the Backend Blueprint
(Rev 3, §4) — capture the inspector's signature at submit, sync it like the evidence
photo, and stop showing delisted establishments. The web half (rendering the PNG over
DATE INSPECTED on the Masterlist grid/export) is a separate web-repo session.

Context: the paper masterlist has the inspector sign across the DATE INSPECTED cell
(the column headed `SSSR` / `Signature` in the LGU workbooks — the importer ignores it
because it only ever held wet ink). The digital replacement lives on `inspection_logs`,
never on `establishments`.

| File | Action |
|---|---|
| `pubspec.yaml` | Re-add `signature` (deleted 2026-09-16 as dead code — this re-introduction is deliberate, per the blueprint) and add `crypto` for SHA-256. |
| `lib/ui/widgets/signature_pad.dart` | Resurrect from `c3b67b8` history, adapted: title, clear/save, `toPngBytes()` on white, target ~600px wide. |
| `lib/ui/screens/inspection_form_screen.dart` | Signature card in the form (near photo evidence). **Required to submit** — it is the sign-off that makes the record official, and capture is fully offline so D9 ("never blocked") is not violated. On submit: write PNG to app documents dir, compute SHA-256, try direct upload (mirror the photo's try-now path); stage the local path otherwise. |
| `lib/data/models/inspection_log.dart` | Add `signatureUrl`, `signatureSha256`, `localSignaturePath`. `toJson` writes `signature_url`+`signature_sha256` as a pair (only when the URL exists). `toQueueJson` adds `local_signature_path` + the hash so a retry re-pairs them. `fromJson` reads all three. |
| `lib/data/services/sync_service.dart` | `signaturePath(estId, logId)` = `signatures/{estId}/{logId}.png` — **deterministic, so a retried upload overwrites itself** (unlike the timestamped photo path). `_uploadStagedSignature(data)` mirrors `_uploadStagedPhoto`, same missing-file forgiveness; called in both queue-drain paths before the Firestore write. Queue entry clears only after Storage upload AND Firestore write succeed (same `photoStillPending` pattern at submit). |
| `lib/data/services/offline_service.dart` | In `syncData`'s establishments pass: skip docs with `status == 'delisted'` before `fromJson` ([REF: DELISTED_FILTER]). Client-side filter, not a query — `where('status' == 'active')` would drop every legacy doc that lacks the field. |
| `storage.rules` | New `signatures/{estId}/{fileName}` block: read `isAuthorized()`; create AND update `isAuthorized()` + `image/png` + `< 200 KB` (update must be allowed because the deterministic path makes retries overwrite — document why this differs from the photo block); no delete (evidence). Deploy with `firebase deploy --only storage` — explicitly, per the standing rule that rules deploys never ride along. |
| `lib/ui/screens/inspection_details_screen.dart` | Show the signature image (network) when `signature_url` exists; nothing when absent (legacy logs). |
| `test/` | Queue round-trip: a log with staged signature survives `toQueueJson` → `jsonEncode` → `fromJson` with path+hash intact; `toJson` never leaks `local_signature_path`; sha pairing rule. |

Also fix while in `_submitForm` (carried open item): the unguarded post-await
`setState` clearing `_isSubmitting` — wrap with `mounted`.

**Not in this chunk:** Chunk 4 (trusted time) is unchanged and still pending; the web
masterlist signature-over-date rendering; any `establishments` write (D2/D5 stand).

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
| 2026-10-02 | 2.5 — `categories` data cleanup | **Applied to production and verified.** Different repo (`inspectra-web`), no mobile code touched. 190 ops in one atomic batch; 53 post-apply assertions, 0 failures. Re-probing first confirmed the plan's numbers but disproved its premise (see the Chunk 2.5 correction) and found the live category *names* mislabeled: `'2' 'Water'` actually held the SUPERMARKETS checklist and `'3' 'Institutional'` held PUBLIC PLACES, verbatim, neither ever used by an inspection. Renamed both; deleted 6 orphan `Food` dupes; created `'11'`-`'17'` + 133 templates from `checklists.xlsx`; fixed 40 stale denormalized `category` strings; added `sort_order` to every category. End state: **11 categories, 193 templates**. `establishments` / `inspection_logs` never written — all 440 historical `checklist_item_id` references still resolve, 0 dangling. CODER/REVIEWER protocol ran; the review found no correctness defect but caught a false claim in the pre-apply transcript, and 8 fixes were applied before writing. The mid-session xlsx replacement (Livestock filled in) was re-parsed and its 13 items verified by hand against the sheet, but that delta was **not independently re-reviewed**. Script, full pre-apply diff and audit log in `inspectra-web` at `scripts/chunk25_*`. **No device or emulator run.** |
| 2026-10-04 | 7 — inspector signature + delisted filter | **Committed.** The blueprint §4 mobile half. New `signature_pad.dart` (resurrected from `c3b67b8`, adapted); signature **required to submit** — guard appended after the completeness guard; UUID minted in `_submitForm` before log construction so the deterministic Storage path (`signatures/{estId}/{logId}.png`) exists at try-now time; PNG staged at `<docs>/signatures/<logId>.png` with SHA-256 from the in-memory bytes; `signature_url`+`signature_sha256` written to Firestore only as a pair (two-way gate); `local_signature_path` stages in the queue exactly like the photo. `[REF: DELISTED_FILTER]` in `syncData` skips `status == 'delisted'` before `fromJson` (client-side on purpose — a `where status=='active'` query drops every legacy doc lacking the field); stale cached copies fall out via the existing `deleteAll`. storage.rules gained `signatures/{estId}/{fileName}` (create AND update for officers — deterministic path means retries overwrite; no delete, evidence) — **deployed via `firebase deploy --only storage`**. Review (fresh context) found 1 HIGH: `_uploadStagedSignature` deleted the staged file after patching the in-memory map, so Storage-ok→Firestore-fail during drain stranded an unsigned record with the PNG orphaned in the bucket; fixed by checkpointing the mutated entry (`box.put`) BEFORE the Firestore write and deleting the file only after `box.delete` — the invariant is now stated at all three sites. Also fixed: disk-staging failure now falls back to a direct `putData` in-memory upload, and if that too fails the submit is **blocked** with an actionable message rather than proceeding unsigned (D9 unviolated: the block is the device's own storage failure, not missing signal); `toPngBytes(width:)` pads rather than upscales — comments corrected; the carried unguarded post-await `setState` in `_submitForm` is fixed. `flutter analyze` clean; **65 tests pass** (9 new queue-round-trip/pairing tests + 1 pairing-direction test). **No device run** — see new device-pass items in Chunk 6's list below. |
| 2026-10-02 | 3 — category picked at inspection time | **Committed.** D4/D5/D6 done, plus two decisions the plan had not anticipated (D24, D25). `establishment.category` no longer feeds the only template lookup in the app — the severance D20 was waiting on. New `category_suggester.dart` (pure Dart, 129 keyword rules over 9 category ids — 51 of them Food, longest-keyword-wins, explainable: a suggestion carries the word it matched), `inspection_category.dart` (Hive typeId 2 + the derived availability rules), `category_picker.dart` (`DropdownMenu` with native type-to-filter). Categories now persist to a new Hive box so the picker works in a dead zone. Suggestion is **hint-only, never pre-selected** — a pre-filled field records identically to a considered choice, and this value lands on an audit record. `fetchCategories` deleted (out-of-table file, reported): the picker reads Hive, not Firestore, and every claim in that function's doc comment had expired. `rating_provider.dart` is in the chunk's file table and was correctly **not** touched — `init()` already cleared atomically and `reset()` already existed. `flutter analyze` clean at baseline; **55 tests pass**, up from 10, including the suggester, the D25 availability rules and the lookup bridge. Review ran twice. Round one found an empty picker on a never-synced device (the `categories` box is new, so a first launch without signal offered zero rows while three separate messages told the inspector to pick one), no defence-in-depth on D25 (withholding rested entirely on `DropdownMenuEntry.enabled`; had it broken, a livestock inspection would have submitted `percentage_rating: 100.0` with no trace it was unscored), an unconditional `clear()` that an empty snapshot would use to wipe the picker, a bridge comment describing a device state it cannot fire in, and a **passing test asserting the wrong thing**. Round two found no functional defect but six surviving comment/test falsehoods — including two in comments round one had just corrected — the sharpest being that the bridge recovers *more* than claimed, not less: the shipped binary rewrites template names from the live category map on every sync, so any box synced since Chunk 2.5 landed carries the current names and the fallback recovers every category, not Food alone. All fixed. **No device or emulator run** — every pixel figure in the picker is derived from source, as in Chunk 2. |

## 7. Open items

**Chunk 3 landed 2026-10-02. D20 is now unblocked, and it is the next session.**

The forced order held: `inspection_form_screen.dart` no longer reads
`establishment.category` for anything, so stripping the field can no longer empty every
inspection form. `grep -rn '\.category' lib/` finds only the denormalizing *writes*
inside `syncData` and the field declaration itself.

1. **D20 — strip `category` / `category_id` off `establishments`** and add the display-only
   business-classification string (`inspectra-web` + a one-off script; three web read sites
   listed at the end of Chunk 2.5). Dropping `'9'` belongs in that session too — it is the
   second `Food` the web dropdown still shows, and mobile no longer cares either way.
2. **Chunk 4 — trusted finish time** (this repo). Unaffected by Chunk 3 except that
   `InspectionLog` has grown two fields; its `toQueueJson` note in section 2.2 still
   stands, since `category_id` / `category_name` are plain strings and raise no
   `Timestamp` serialization problem.

**New, created by Chunk 3 and blocking for livestock work only:**

- **The per-category scoring mode is now a named prerequisite, not a footnote** (D22/D25).
  Livestock Farm is withheld from the picker by the derived weight-0 rule and renders
  disabled with "Scoring not yet published for this form". The fix is a `scoring_mode`
  field plus a compliant-count on the log, a `RatingProvider` that can score a
  COMPLIANT/NON-COMPLIANT form, and a web admin that renders it — mobile and web, so it
  needs its own chunk and probably two. Until then the 13 livestock items are
  unreachable, which is the point.
- **`[REF: TEMPLATE_LOOKUP_ID_BRIDGE]` is a one-release bridge**, to be deleted in Chunk 6
  alongside the D19 establishment bridge. Read its comment before deciding: its trigger is
  a *partial sync*, not "upgraded while offline", and how much it recovers depends on when
  the box was last written. While it is active, `'9' Food` resolves to `'1' Food`'s
  checklist and is startable, so a log can be written against `category_id: '9'` — bounded
  by one sync, and moot once D20 drops `'9'`.
- **`DropdownMenu` can leave half-typed filter text in the picker's field** over a loaded
  checklist: type a filter and tap away without selecting, or highlight a disabled row and
  press the keyboard's done key. Display only — the log takes its category from the
  screen's own state, never the field. Deliberately not fixed, because every candidate fix
  changes framework-interaction behaviour that cannot be verified without a running frame.
  Confirm it in the Chunk 6 device pass and fix it there.
- **Two guards and one empty state are unreachable by design** and documented as such: the
  `_templates.isEmpty` submit guard and the fourth `_buildChecklist` branch. Kept because
  what they prevent — a zero-item inspection submitting as a flat 100 — is one refactor
  away.
- **The establishments and templates sync passes still `clear()` on an empty snapshot.**
  Only the new categories pass guards against it. Pre-existing, now conspicuously
  asymmetric; its worst case is a filled categories box over an emptied template box,
  which shows eleven rows every one of which reports no checklist items.
- **No widget test exists for `CategoryPicker`.** The three things unit tests structurally
  cannot reach are exactly the three worth pinning: that a disabled row is unselectable,
  that the switch dialog clears work, and that the empty-box state says something true.
- **`_submitForm` calls `setState` after an `await` with no `mounted` guard**
  (`inspection_form_screen.dart`, clearing `_isSubmitting`). **Pre-existing** — it is there
  at `34d6460`, so it was left alone as outside this chunk's goal — but Chunk 3 added
  `mounted` checks either side of it, so it is now the only unguarded post-await
  `setState` on the screen. Reachable by a system-back pop while the submit spinner is up,
  which throws `setState() called after dispose()`. Fix it in Chunk 4, which touches this
  method anyway to capture `finished_at`.

**Resolved by Chunk 3:**

- ~~`SyncService.fetchCategories`' dedupe-by-name is no longer load-bearing~~ — the
  function is **deleted**. The picker reads the Hive box, not Firestore, because it has to
  work offline.
- ~~`sort_order` is written but unread~~ — **the mobile picker reads it** (`sort_order`,
  then name, then id; the id tiebreak is not decoration, since `'1'` and `'9'` are both
  named `Food`). The **web admin still ignores it**: `mapCategory` drops the field and
  `useCollection` issues no `orderBy`, so that dropdown is still in doc-id order
  (`'1'`, `'11'`, `'12'`, … `'2'`, `'3'`). Fix it in the D20 session.

Carried forward. The Livestock sub-field item below is blocking for anything that touches
livestock farms; the rest are not blocking:

- **Chunks 1, 2 and 3 have never run on a device.** All three were analyzer-clean and
  review-clean, but every layout figure in Chunks 2 and 3 is computed from source rather
  than observed, and neither upgrade bridge (D19's, and Chunk 3's template-lookup one) can
  occur on a fresh install. The Chunk 6 device pass is the first time any of it is
  exercised, and it is now carrying three chunks of unobserved layout work.
- **Livestock Farm would still display a false score of 100 if it could be reached**
  (D22). `RatingProvider.score` is `100 - totalDemerits` and every livestock item is
  weight 0. The old gate described here — "the lookup is by category name and no
  establishment is named Livestock Farm" — **expired with Chunk 3**, which replaced both
  the lookup and the establishment's role in it. What gates it now is D25: the picker
  refuses it, and `_onCategorySelected` and `_submitForm` refuse it again. The scoring
  mode is tracked as its own prerequisite above.
- **The 38 Livestock sub-fields are captured nowhere.** 30 are plain checkboxes, but 8
  need input types the Pass/Fail/NA card cannot express: 5 measurements
  (`_____m, Septic Tank (Domestic)`, `Distance:______radius`), 2 free-text
  (`Type of Water Source:`, `Trees:`), 1 exclusive choice (`______uphill ______downhill`).
  Capturing them needs a response type per item plus a parent-child relation — additive
  `@HiveField` numbers on `ChecklistTemplate`, never renumbering the existing 0-4.
- **`rating_scale.dart.md` exists but is absent from `build.py`'s `MOBILE_E`**, so it has
  never been built into the docx — a pre-existing gap, surfaced (not fixed) by the Chunk 3
  docs pass. Chunk 3 added three files to `MOBILE_E` in their semantically correct groups,
  which shifted every §E.N above 3: `category_suggester.dart` took §E.4,
  `inspection_category.dart` §E.8, `category_picker.dart` §E.35, and
  `establishment_banner.dart` moved 32→34. `mobile_learn.md`'s 35 citations were updated to
  match. Adding `rating_scale.dart` in Chunk 6 will take §E.5 and shift everything again —
  do it before the docx rebuild, not after.
- **The xlsx precondition gate is title + item-count only.** An edited item *wording*
  would pass and be seeded silently. A content hash over the source cells would close it.
- **5 `inspection_logs` point at establishment ids that no longer exist**, and every log
  stores its results twice (a `results[]` array of 440 rows plus an `inspection_results`
  sub-collection of 340). Both found incidentally during the Chunk 2.5 probe, both out of
  scope, neither investigated.
- **`assets/data/batangas_psgc.json` is orphaned.** The deleted barangay picker was its
  only consumer and nothing in `lib/` loads any asset now, but it is still declared in
  `pubspec.yaml`. Dropping both is a free size win; left alone because `pubspec.yaml` was
  outside Chunk 1's scope.
- **`EstablishmentBanner.densityFor` is pure and static specifically to be testable, and
  has no test.** The hysteresis arithmetic it encodes was wrong once already.

**Added by Chunk 7 to the Chunk 6 device pass:** sign and submit in airplane mode,
kill the app, drain the queue, and confirm the signature lands with matching sha256;
force a Firestore failure between the Storage upload and the log write (the HIGH-fix
checkpoint path is not unit-testable — Hive/Firebase statics, no mocking infra);
delist an establishment on the web and confirm it disappears from the phone after a
sync; verify the pad's export on a tablet-wide signature (`width: null` fallback).

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
