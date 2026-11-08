# Inspectra mobile — guide for Claude

This is the Flutter inspector app of **Inspectra**, the sanitary-inspection system of the Batangas City Health Office.
Field inspectors score establishments against weighted checklists here; the web admin (`inspectra-web` repo) manages data;
establishment owners read results and Sanitary Orders in this app's owner mode. Backend is Supabase project `fwtgdgeiffnvqyrobixc`
(Postgres + Auth + RLS). "Clowtec" in paths/ids is the old codename, same product. `README.md` is stale (describes removed QR/signature/photo features).

## Where the full documentation lives

The system docs are kept in the web repo `josiahcustodio/inspectra-web` under `docs/claude/`:
`MOBILE.md` (this app, file by file), `BACKEND.md` (schema, roles, RLS, triggers, Edge Functions, auth config),
`WEB.md` (admin SPA), `FLOWS.md` (end-to-end flows, deployment, timeline, open issues). If that repo is checked out next to this
one, read those before opening source files. If not, the essentials are below.

## Essentials

- **Stack:** `supabase_flutter 2.x`, `provider` (ChangeNotifier), `go_router`, `hive_flutter` (offline cache), `maplibre_gl` (OpenFreeMap style, keyless),
  `geolocator`/`permission_handler` (GPS pin), `ota_update` (self-update), `qr_flutter` (MFA QR only). No Firebase, camera, signature pad or QR scanner anymore
  (`firebase.json`, `firestore.rules`, `bin/*.py`, `web-dashboard/` are dead leftovers).
- **Roles** come from `profiles.role` (`AuthService.fetchRole`, cached in Hive `app_prefs`): `pending` → /pending-approval; `owner` → /my/inspections (read-only, OTP sign-in);
  `officer`/`admin`/`department_head` → inspector shell (TOTP enrolment mandatory, then `/sync`, then `/home`). RLS blocks department_head writes server-side.
- **Router guard order** (`lib/core/router/app_router.dart`): no session → /login; role unknown → /mfa-verify or /sync; pending; owner; AAL1+factor → /mfa-verify;
  unconfirmed email → /verify-email; no factor → /mfa-enroll. `AuthProvider` ignores `tokenRefreshed` on purpose (sign-in loop guard; do not remove).
- **Shell:** branches /home, /establishments, /history, /profile, /map (centre FAB). Other routes: /inspection (form, `extra: Establishment`), /inspection/details/:id.
  The app cannot add or edit establishments.
- **Supabase surface:** tables only, no RPC/Edge Function/Storage calls. `profiles` (role), `categories` / `establishments` / `checklist_templates` (paged pull in
  `offline_service.dart`), `establishments.update(latitude, longitude)` (GPS pin drain), `inspection_logs` upsert/select (`sync_service.dart`, history limit 50, RLS-scoped).
- **Offline:** Hive boxes `establishments`, `checklist_templates`, `categories`, `inspections_queue` (JSON by log id), `app_prefs`. Master data syncs at splash;
  an empty server snapshot never wipes the cache. The queue drains **only** when the user taps Sync Now / Submit (last-write-wins upsert on `id`).
- **Scoring** (`providers/rating_provider.dart`, contract in `core/rating_scale.dart` shared with web): `totalDemerits = Σ weight of FAIL` (missing weight = 5);
  `score = clamp(100 − totalDemerits, 0, 100)` only when every item answered; N/A free. Bands 90–100 Excellent #10B981, 70–89 Very Satisfactory #F59E0B, 0–69 Satisfactory #EF4444.
- **Sanitary Order** (`core/sanitary_order.dart`): offered when any FAIL; needs note + correction per defect, time given, deadline (≤ +365 d), received-by. Writes `so_issued_at`,
  `so_no`, `time_given`, `deadline`, `received_by_name`, `proposed_point_person_name`. `proposed_point_person_email` is written on every inspection and is what makes the
  owner account server-side (DB triggers). `email_sent_at` is server-only.
- **results[]** item shape: `{checklist_item_id, item_name, sub_category, weight, answer:'Pass'|'Fail'|'NA', note, correction, values}`; `values` holds answers to template `fields`.
- **Categories** with all weights 0 (Livestock 17, Industrial 23, Waste Management 24) are disabled in the picker until CHO provides weights.
- **Release:** publish only with `.\release.ps1 "notes"` (split APKs + `update.json` → GitHub release in public `josiahcustodio/inspectra-releases`, then bumps
  `pubspec.yaml` build → commit it). `lib/core/app_updater.dart` checks that manifest on Wi-Fi (startup/connectivity/resume); `APP_BUILD` dart-define 0 = updater off.
  Signing needs gitignored `android/key.properties` + `android/app/release.keystore`; losing the keystore ends in-place updates. Never `flutter clean` with an undistributed APK in `build/`.
- **Tests:** `flutter test` (12 files: updater, category availability/suggester, checklist fields, details card, history provider, inspection_log json, owner OTP dialog, rating scale, sanitary order).
  Keep `flutter analyze` clean.

## Rules

- Authorization lives in Postgres RLS; any new write must be allowed by `is_authorized()` (admin|officer) or it fails silently for other roles.
- Keep the rating contract identical to web `src/lib/ratingScale.ts`; `test/rating_scale_test.dart` guards it.
- Don't reintroduce signatures, photo upload, QR scanning or Google sign-in; they were removed deliberately (2026-11).
- Hive typeIds/field numbers are append-only (Establishment 0–22, ChecklistTemplate 1, InspectionCategory 2).
