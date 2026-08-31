"""
fix_category_ids.py

Patches establishments in Firestore that are missing a `category_id` field
by inferring it from the `category` string using the categories collection.

Also patches checklist_templates the same way for consistency.

Run from the project root:
    python bin/fix_category_ids.py
"""

import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# -- 1. Build category name to ID map from Firestore --------------------------
print('=== Loading categories ===')
cat_name_to_id = {}
for doc in db.collection('categories').stream():
    name = doc.to_dict().get('name', '')
    cat_name_to_id[name.lower().strip()] = doc.id
    print(f'  {doc.id} => "{name}"')

# Hardcoded fallbacks (mirrors offline_service.dart)
hardcoded = {
    'food establishment': '1',
    'water': '2',
    'institutional': '3',
    # Raw short names that may exist in some docs
    'food': '1',
}
for k, v in hardcoded.items():
    if k not in cat_name_to_id:
        cat_name_to_id[k] = v

print(f'\nCategory name->ID map: {cat_name_to_id}\n')


def resolve_id(data):
    """Return the best category_id for a document, or None if unknown."""
    cat_raw = str(data.get('category', '')).lower().strip()
    return cat_name_to_id.get(cat_raw)


# -- 2. Patch establishments --------------------------------------------------
print('=== Patching establishments ===')
est_patched = 0
est_skipped = 0
for doc in db.collection('establishments').stream():
    data = doc.to_dict()
    if data.get('category_id') is not None:
        est_skipped += 1
        continue  # already has category_id, skip

    cat_id = resolve_id(data)
    if cat_id is None:
        print(f'  [WARN] Cannot resolve category_id for "{doc.id}" '
              f'(category="{data.get("category")}")')
        continue

    db.collection('establishments').document(doc.id).update(
        {'category_id': cat_id}
    )
    print(f'  [PATCHED] {doc.id} ({data.get("business_name", "?")}) '
          f'category="{data.get("category")}" -> category_id="{cat_id}"')
    est_patched += 1

print(f'  Done: {est_patched} patched, {est_skipped} already had category_id.\n')

# -- 3. Patch checklist_templates ---------------------------------------------
print('=== Patching checklist_templates ===')
tmpl_patched = 0
tmpl_skipped = 0
for doc in db.collection('checklist_templates').stream():
    data = doc.to_dict()
    if data.get('category_id') is not None:
        tmpl_skipped += 1
        continue

    cat_id = resolve_id(data)
    if cat_id is None:
        print(f'  [WARN] Cannot resolve category_id for template "{doc.id}" '
              f'(category="{data.get("category")}")')
        continue

    db.collection('checklist_templates').document(doc.id).update(
        {'category_id': cat_id}
    )
    print(f'  [PATCHED] template {doc.id} category="{data.get("category")}" '
          f'-> category_id="{cat_id}"')
    tmpl_patched += 1

print(f'  Done: {tmpl_patched} patched, {tmpl_skipped} already had category_id.\n')

print('=== All done! Re-run the app and trigger a sync to reload. ===')
