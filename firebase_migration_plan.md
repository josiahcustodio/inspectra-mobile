# Firebase Migration Plan for Inspectra

This document outlines the step-by-step plan to migrate the **Inspectra** mobile application from **Supabase** to **Firebase**.

---

## 📋 Current vs. Future Tech Stack

| Feature | Current (Supabase) | Proposed (Firebase) | Action Required |
| :--- | :--- | :--- | :--- |
| **Authentication** | `supabase_flutter` + Google OAuth | `firebase_auth` + `google_sign_in` | Replace authentication client & flows |
| **Database** | PostgreSQL | Cloud Firestore (NoSQL) | Rewrite CRUD operations & model mappings |
| **Storage** | Supabase Storage (`inspection_evidence`) | Firebase Cloud Storage | Replace file upload & download methods |
| **Offline Sync** | Hive + manual queue in `SyncService` | Native Firestore cache / keep Hive | Decide on sync architecture |
| **Configuration** | `.env` file | Firebase configuration files (`google-services.json`, `GoogleService-Info.plist`) | Set up Firebase CLI & configure project |

---

## 🛠️ Step-by-Step Migration Checklist

### Phase 1: Firebase Project Setup & Configuration
- [ ] Create a project named `inspectra-firebase` (or use existing) in the [Firebase Console](https://console.firebase.google.com/).
- [ ] Enable the following services in the console:
  - **Authentication** (Enable Google Provider)
  - **Cloud Firestore** (Start in test mode or configure rules)
  - **Cloud Storage** (Set up rules for `inspection_evidence` path)
- [ ] Configure Flutterfire in the codebase:
  - Install/Activate the CLI if not already done:
    ```bash
    dart pub global activate flutterfire_cli
    ```
  - Run configuration:
    ```bash
    dart pub global run flutterfire_cli:flutterfire configure --project=inspectra-firebase
    ```
    *(Note: Using `dart pub global run` avoids PATH environment variable issues on Windows).*

### Phase 2: Dependency Updates
- [ ] Modify [`pubspec.yaml`](file:///c:/Users/josia/Downloads/Inspectra%20Firebase/clowtec_inspector/pubspec.yaml):
  - Remove `supabase_flutter`
  - Add:
    * `firebase_core: ^3.0.0` (or latest matching version)
    * `firebase_auth: ^5.0.0`
    * `cloud_firestore: ^5.0.0`
    * `firebase_storage: ^12.0.0`
    * `google_sign_in: ^6.2.1`

### Phase 3: Authentication Migration
- [ ] Update [`main.dart`](file:///c:/Users/josia/Downloads/Inspectra%20Firebase/clowtec_inspector/lib/main.dart) to initialize Firebase:
  ```dart
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  ```
- [ ] Rewrite [`auth_service.dart`](file:///c:/Users/josia/Downloads/Inspectra%20Firebase/clowtec_inspector/lib/data/services/auth_service.dart) to use `FirebaseAuth` and `GoogleSignIn`.
- [ ] Update [`auth_provider.dart`](file:///c:/Users/josia/Downloads/Inspectra%20Firebase/clowtec_inspector/lib/providers/auth_provider.dart) to listen to `FirebaseAuth.instance.authStateChanges()`.

### Phase 4: Database & Offline Sync Migration
- [ ] Determine Firestore document schema:
  - **Option A (Denormalized)**: Store category names directly in `establishments` and `checklist_templates` documents.
  - **Option B (Normalized)**: Reference category documents in a separate `categories` collection.
- [ ] Decide on sync style:
  - **Option A (Firestore Native Offline)**: Let Firestore handle all offline access and synchronization automatically.
  - **Option B (Hive Queue Hybrid)**: Keep the existing Hive local databases and rewrite `SyncService` to upload queued items to Firestore.
- [ ] Rewrite [`sync_service.dart`](file:///c:/Users/josia/Downloads/Inspectra%20Firebase/clowtec_inspector/lib/data/services/sync_service.dart):
  - Adapt `uploadImage` & `uploadBytes` to write to Firebase Storage.
  - Adapt `submitInspectionLog`, `insertEstablishment`, `fetchCategories`, `fetchInspectionHistory`, and `fetchInspectionDetails` to read/write Firestore collections.
- [ ] Update [`offline_service.dart`](file:///c:/Users/josia/Downloads/Inspectra%20Firebase/clowtec_inspector/lib/data/services/offline_service.dart) if Hive is kept or modified.

### Phase 5: Verification & Testing
- [ ] Build and launch application.
- [ ] Test Google Sign-in flow.
- [ ] Test establishment creation (offline & online).
- [ ] Test inspection submission with photo attachments.
- [ ] Validate sync of pending items once the connection is restored.

---

## ❓ Open Questions for User
When you return, let's discuss:
1. **Firestore Schema Design:** Do you want to keep category names embedded directly inside documents, or refer to a separate collection by ID?
2. **Offline Handling:** Do you prefer Firestore's built-in offline support, or do you want to keep the current Hive queue setup?
3. **Flutterfire Installation:** If you encountered issues running `flutterfire`, try:
   ```powershell
   dart pub global activate flutterfire_cli
   dart pub global run flutterfire_cli:flutterfire configure --project=inspectra-firebase
   ```
