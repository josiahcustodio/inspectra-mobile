"""
Delete the sheet-named categories created by early masterlist imports.

The first version of the web importer mapped every Excel sheet to a category
and created one per sheet by default ("Bakery", "SariSariStoreA", ...). That
flow was removed — categories in Inspectra are assigned at INSPECTION time,
from the checklist the inspector scores against — so those sheet-categories
are junk that clutters every category dropdown.

They are precisely identifiable: only importer-created categories carry a
`sheet_aliases` field (the real checklist categories — 'Food', 'Supermarkets',
'Public Places', ... — predate it and have none). This script lists them,
asks for confirmation, and deletes them.

It does NOT touch establishments: records from an old-flow import still hold
a category_id pointing at a deleted doc, which nothing resolves anymore —
and the expected cleanup order is to undo that import first anyway
(bin/undo_import_batch.py), then run this, then re-import with the new flow.

Run from the repo root: python bin/delete_sheet_categories.py
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


def main():
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        print(f"Error: '{SERVICE_ACCOUNT_FILE}' not found — run this from the repo root.")
        sys.exit(1)
    firebase_admin.initialize_app(credentials.Certificate(SERVICE_ACCOUNT_FILE))
    db = firestore.client()

    junk = [
        snap for snap in db.collection("categories").stream()
        if (snap.to_dict() or {}).get("sheet_aliases")
    ]
    if not junk:
        print("No sheet-named categories found — nothing to delete.")
        return

    print(f"\n{len(junk)} importer-created categories (they carry sheet_aliases):")
    for snap in junk:
        print(f"  - {(snap.to_dict() or {}).get('name')!r}")
    print("\nReal checklist categories (no sheet_aliases) are untouched.")

    confirm = input(f"\nType DELETE to remove all {len(junk)}: ").strip()
    if confirm != "DELETE":
        print("Did not match. Nothing deleted.")
        return

    for snap in junk:
        snap.reference.delete()
    print(f"Deleted {len(junk)} categories.")

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{now}  DELETE_SHEET_CATEGORIES  count={len(junk)}\n")


if __name__ == "__main__":
    main()
