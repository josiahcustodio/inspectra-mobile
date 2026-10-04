"""
Clean-slate the Inspectra database: delete test/transactional data, keep the
things that are real.

Everything in this project's `establishments`, `review_queue`, `upload_batches`
and `inspection_logs` today is mock — imported masterlist rows and demo
inspections of Jollibee/MCDO/Starbucks. This script removes them so a fresh
import and a fresh round of field testing start from zero.

WHAT IT DELETES
  Tier 1 — masterlist data (always, when you confirm):
    establishments/*            (and every permits/* sub-document under them)
    review_queue/*              (fuzzy matches awaiting a decision)
    upload_batches/*            (and any rows/* staging sub-documents)
  Tier 2 — inspection history (asked separately, so you can keep it):
    inspection_logs/*           (and legacy inspection_results/* sub-documents)

WHAT IT NEVER TOUCHES, and why
    profiles/*            Account roles. Deleting your own profile would strip
                          your 'admin' role and lock you out of /admin/* —
                          there is no self-promotion path back (see
                          firestore.rules and bin/manage_admins.py).
    categories/*          The real checklist categories (Food, Supermarkets,
    checklist_templates/* Public Places, ...) and their ~193 scored items.
                          This is hand-maintained reference data, not test
                          data: wiping it leaves inspectors with nothing to
                          score an inspection against.
    Firebase Auth users   The logins themselves. Use the Firebase console if
                          you ever need to remove a test account.
    Storage objects       Inspection photos (and later, signatures) are files,
                          not documents. Orphaned ones are harmless — they are
                          unreachable without a log pointing at them, and the
                          storage rules still gate them — so clean them in the
                          console only if you care about the bytes.

Deletion is recursive and irreversible. There is no undo: unlike
bin/undo_import_batch.py (which reverses one import batch), this removes
everything regardless of which batch wrote it.

Run from the repo root: python bin/reset_test_data.py
"""

import datetime
import os
import sys

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    print("Error: 'firebase-admin' package not found.")
    print("Please install it by running: pip install firebase-admin")
    sys.exit(1)

SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "admin_actions.log")

# Collections this script is allowed to empty, in two tiers.
MASTERLIST_COLLECTIONS = ["establishments", "review_queue", "upload_batches"]
INSPECTION_COLLECTIONS = ["inspection_logs"]

# Named here only so the summary can prove they were considered and spared.
PRESERVED = ["profiles", "categories", "checklist_templates"]


def init_db():
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        print(f"Error: '{SERVICE_ACCOUNT_FILE}' not found — run this from the repo root,")
        print("the same place bin/manage_admins.py finds it.")
        sys.exit(1)
    cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
    app = firebase_admin.initialize_app(cred)
    return firestore.client(), app.project_id


def count_of(db, collection):
    """Document count, or None when the aggregation query is unavailable."""
    try:
        return db.collection(collection).count().get()[0][0].value
    except Exception:
        return None


def show(db, collections, heading):
    print(f"\n{heading}")
    total = 0
    for name in collections:
        n = count_of(db, name)
        total += n or 0
        print(f"   {name:<22} {n if n is not None else '?':>6} documents (plus any sub-documents)")
    return total


def wipe(db, collections):
    """Recursive delete, which also removes sub-collections (permits/*,
    inspection_results/*, rows/*) that a plain collection delete would orphan."""
    deleted = 0
    for name in collections:
        print(f"   deleting {name} ...", end="", flush=True)
        n = db.recursive_delete(db.collection(name))
        # recursive_delete returns a count on current client versions; older
        # ones return None, so don't let that break the tally.
        deleted += n or 0
        print(f" done ({n if n is not None else 'ok'})")
    return deleted


def log_action(line):
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{now}  {line}\n")


def main():
    db, project_id = init_db()

    print("=" * 66)
    print(f"CLEAN SLATE — Firebase project: {project_id}")
    print("=" * 66)

    show(db, MASTERLIST_COLLECTIONS, "WILL DELETE — masterlist data:")
    show(db, INSPECTION_COLLECTIONS, "WILL DELETE (only if you say yes) — inspection history:")
    show(db, PRESERVED, "WILL KEEP — real accounts and checklist reference data:")

    print("\nFirebase Auth logins and Storage files are not touched either.")

    # Two confirmations, because these are different kinds of loss: masterlist
    # rows can be re-imported from the Excel file, but an inspection is a field
    # visit that cannot be re-done.
    print()
    drop_inspections = input("Also delete the inspection history? (yes/no): ").strip().lower() in ("yes", "y")
    targets = MASTERLIST_COLLECTIONS + (INSPECTION_COLLECTIONS if drop_inspections else [])

    print(f"\nAbout to recursively delete: {', '.join(targets)}")
    print("This cannot be undone.")
    confirm = input(f"Type the project id ({project_id}) to proceed: ").strip()
    if confirm != project_id:
        print("Did not match. Nothing deleted.")
        return

    print()
    deleted = wipe(db, targets)
    print(f"\nDeleted {deleted} documents.")
    print("Kept: " + ", ".join(PRESERVED) + ", Firebase Auth users, Storage files.")
    print("\nNext: re-import the masterlist from the web admin's Import page.")
    print("If a test phone still holds queued offline inspections, clear that")
    print("app's data too — otherwise they will sync into the fresh database.")

    log_action(
        f"RESET_TEST_DATA project={project_id} collections={'+'.join(targets)} deleted={deleted}"
    )


if __name__ == "__main__":
    main()
