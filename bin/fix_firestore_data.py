"""
Fix Firestore data:
1. Populate all empty category documents with proper names
2. Fix all checklist_templates to have correct category field based on category_id
"""
import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# Step 1: Define what the categories SHOULD be
# Based on: ID=1 is "Food" (already there), IDs 2-3 were "Water" and "Institutional"
# The app uses "Food Establishment", "Water", "Institutional" as display names
CATEGORY_NAMES = {
    '1': 'Food',
    '2': 'Water',
    '3': 'Institutional',
    '4': 'Food',
    '5': 'Food',
    '6': 'Food',
    '7': 'Food',
    '8': 'Food',
    '9': 'Food',
    '10': 'Food',
}

print("=== STEP 1: Fixing empty category documents ===")
cats = list(db.collection('categories').stream())
for doc in cats:
    d = doc.to_dict()
    if 'name' not in d or not d.get('name'):
        cat_name = CATEGORY_NAMES.get(doc.id, 'Food')
        db.collection('categories').document(doc.id).set({'name': cat_name})
        print(f"  Fixed category ID={doc.id} => name={cat_name}")
    else:
        print(f"  OK category ID={doc.id} => {d['name']}")

# Step 2: Build category map from what's now in Firestore
print()
print("=== STEP 2: Building category map ===")
category_map = {}
for doc in db.collection('categories').stream():
    d = doc.to_dict()
    category_map[doc.id] = d.get('name', 'Food')
    print(f"  {doc.id} => {category_map[doc.id]}")

# Step 3: Fix all checklist_templates that have empty category
print()
print("=== STEP 3: Fixing checklist_templates category field ===")
all_tmpl = list(db.collection('checklist_templates').stream())
fixed = 0
for doc in all_tmpl:
    d = doc.to_dict()
    cat_id = str(d.get('category_id', '1'))
    correct_name = category_map.get(cat_id, 'Food')
    current_name = d.get('category', '')
    
    if current_name != correct_name:
        db.collection('checklist_templates').document(doc.id).update({'category': correct_name})
        print(f"  Fixed template ID={doc.id}: '{current_name}' -> '{correct_name}' (category_id={cat_id})")
        fixed += 1
    else:
        pass  # already correct

print(f"  Total fixed: {fixed}/{len(all_tmpl)} templates")

# Step 4: Verify by showing category distribution of templates
print()
print("=== STEP 4: Verifying template category distribution ===")
counts = {}
for doc in db.collection('checklist_templates').stream():
    d = doc.to_dict()
    cat = d.get('category', '')
    counts[cat] = counts.get(cat, 0) + 1
for cat, count in sorted(counts.items()):
    print(f"  '{cat}': {count} templates")

print()
print("=== DONE. Re-sync the app and the checklist should now load. ===")
