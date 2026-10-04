"""
Undo one masterlist import batch — the cleanup tool for test uploads.

Every document the web importer writes is stamped with its batch id, which
is what makes a precise undo possible:

  DELETED by this script (they did not exist before the batch):
    - establishments whose source_batch_id == the batch (created by it),
      including their permits sub-collection
    - permit documents under OTHER establishments where the permit's
      source_batch_id == the batch (renewal docs added to existing records)
    - review_queue items with batch_id == the batch
    - the upload_batches record itself (last, so a crash mid-undo leaves
      the batch visible and the undo re-runnable)

  REPORTED but NOT undone (no snapshot of the old values exists):
    - establishments that existed before and were UPDATED by the batch
      (matched rows merge owner/address/category onto them). The script
      lists them so you can eyeball whether anything real was touched.
    - categories created or aliased during the import (not batch-tagged);
      delete those by hand in the Firebase console if the test made junk.

  NEVER touched, by design: inspection_logs. The importer has no write path
  to them and neither does this script.

Run from the repo root (it looks for serviceAccountKey.json in the cwd,
same as manage_admins.py):  python bin/undo_import_batch.py
"""

import datetime
import os
import sys

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    from google.cloud.firestore_v1.base_query import FieldFilter
except ImportError:
    print("Error: 'firebase-admin' package not found.")
    print("Please install it by running: pip install firebase-admin")
    sys.exit(1)

SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "admin_actions.log")


def init_db():
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        print(f"Error: Firebase Service Account file '{SERVICE_ACCOUNT_FILE}' not found.")
        print("Run this from the repo root, next to where manage_admins.py finds it.")
        sys.exit(1)
    cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
    firebase_admin.initialize_app(cred)
    return firestore.client()


def log_action(line):
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{now}  {line}\n")


def pick_batch(db):
    """Show recent import batches, newest first, and let the user pick one."""
    batches = list(
        db.collection("upload_batches")
        .order_by("started_at", direction=firestore.Query.DESCENDING)
        .limit(15)
        .stream()
    )
    if not batches:
        print("No import batches found — nothing to undo.")
        sys.exit(0)

    print("\nRecent import batches (newest first):")
    for i, snap in enumerate(batches, 1):
        b = snap.to_dict()
        counters = b.get("counters", {})
        print(
            f"  {i:2}. {b.get('started_at', '?')}  [{b.get('status', '?')}]  "
            f"{b.get('file_name', '?')}  ({b.get('group', '?')})  "
            f"created={counters.get('created', '?')} updated={counters.get('updated', '?')} "
            f"renewals={counters.get('renewals', '?')}"
        )

    choice = input("\nWhich batch number do you want to UNDO? ").strip()
    if not choice.isdigit() or not (1 <= int(choice) <= len(batches)):
        print("Not a valid number. Nothing done.")
        sys.exit(0)
    return batches[int(choice) - 1]


def collect(db, batch_id):
    """Everything the batch touched, split into deletable vs report-only."""
    created = list(
        db.collection("establishments")
        .where(filter=FieldFilter("source_batch_id", "==", batch_id))
        .stream()
    )
    created_ids = {snap.id for snap in created}

    # Touched = stamped last_seen by the batch. Touched-but-not-created means
    # the record existed before: its merged field updates cannot be undone,
    # but any permit DOC the batch added under it can be.
    touched = list(
        db.collection("establishments")
        .where(filter=FieldFilter("last_seen_batch_id", "==", batch_id))
        .stream()
    )
    updated = [snap for snap in touched if snap.id not in created_ids]

    renewal_permits = []
    for snap in updated:
        for permit in (
            snap.reference.collection("permits")
            .where(filter=FieldFilter("source_batch_id", "==", batch_id))
            .stream()
        ):
            renewal_permits.append(permit)

    reviews = list(
        db.collection("review_queue")
        .where(filter=FieldFilter("batch_id", "==", batch_id))
        .stream()
    )
    return created, updated, renewal_permits, reviews


def main():
    db = init_db()
    batch_snap = pick_batch(db)
    batch_id = batch_snap.id
    file_name = (batch_snap.to_dict() or {}).get("file_name", "?")

    print(f"\nScanning everything written by batch {batch_id} ({file_name})...")
    created, updated, renewal_permits, reviews = collect(db, batch_id)

    print("\nThis undo will DELETE:")
    print(f"  - {len(created)} establishments created by the batch (plus their permit docs)")
    print(f"  - {len(renewal_permits)} permit docs the batch added under pre-existing establishments")
    print(f"  - {len(reviews)} review-queue items")
    print("  - the batch record itself")
    print("\nIt can NOT undo (report only):")
    print(f"  - {len(updated)} pre-existing establishments whose fields the batch merged into:")
    for snap in updated[:20]:
        e = snap.to_dict()
        print(f"      * {e.get('business_name', '(unnamed)')}  ({snap.id})")
    if len(updated) > 20:
        print(f"      ...and {len(updated) - 20} more")
    print("  - categories created/aliased during the import (clean up in the console if needed)")
    print("  - inspection_logs were never touched by the import, so there is nothing to undo there")

    confirm = input(f"\nType the batch file name exactly ('{file_name}') to proceed: ").strip()
    if confirm != file_name:
        print("Did not match. Nothing deleted.")
        sys.exit(0)

    # Children before parents, batch record last — a crash at any point
    # leaves a state where simply re-running this script finishes the job.
    deleted = 0
    for snap in created:
        for permit in snap.reference.collection("permits").stream():
            permit.reference.delete()
            deleted += 1
        snap.reference.delete()
        deleted += 1
    for permit in renewal_permits:
        permit.reference.delete()
        deleted += 1
    for review in reviews:
        review.reference.delete()
        deleted += 1
    batch_snap.reference.delete()
    deleted += 1

    print(f"\nDone. Deleted {deleted} documents.")
    if updated:
        print(f"Reminder: {len(updated)} pre-existing establishments keep the merged values listed above.")
    log_action(
        f"UNDO_IMPORT batch={batch_id} file={file_name} "
        f"deleted={deleted} updated_not_reverted={len(updated)}"
    )


if __name__ == "__main__":
    main()
