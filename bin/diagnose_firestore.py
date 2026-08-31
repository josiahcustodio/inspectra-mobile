import firebase_admin
from firebase_admin import credentials, firestore
import json

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# 1. Categories
print('=== CATEGORIES ===')
cat_list = []
for doc in db.collection('categories').stream():
    d = doc.to_dict()
    d['_id'] = doc.id
    cat_list.append(d)
    print(f'  ID={doc.id} => {json.dumps(d)}')
print(f'  Total: {len(cat_list)}')

# 2. Checklist templates - sample ALL field names from first doc
print()
print('=== CHECKLIST_TEMPLATES ===')
all_tmpl = list(db.collection('checklist_templates').stream())
print(f'  TOTAL templates in Firestore: {len(all_tmpl)}')
for doc in all_tmpl[:10]:
    d = doc.to_dict()
    d['_id'] = doc.id
    print(f'  ID={doc.id} => {json.dumps(d)}')

# Show all unique field names across all templates
all_fields = set()
for doc in all_tmpl:
    all_fields.update(doc.to_dict().keys())
print(f'  All field names found: {sorted(all_fields)}')

# 3. Establishments - sample ALL field names
print()
print('=== ESTABLISHMENTS ===')
all_ests = list(db.collection('establishments').stream())
print(f'  TOTAL establishments in Firestore: {len(all_ests)}')
for doc in all_ests[:5]:
    d = doc.to_dict()
    d['_id'] = doc.id
    print(f'  ID={doc.id} => {json.dumps(d)}')

all_est_fields = set()
for doc in all_ests:
    all_est_fields.update(doc.to_dict().keys())
print(f'  All field names found: {sorted(all_est_fields)}')

# 4. Check alternate names
print()
print('=== ALTERNATE COLLECTION NAMES ===')
for name in ['checklist_items', 'templates', 'checklists', 'items', 'food_templates']:
    try:
        docs = list(db.collection(name).limit(1).stream())
        if docs:
            d = docs[0].to_dict()
            print(f'  FOUND "{name}": {json.dumps(d)}')
        else:
            print(f'  "{name}" = empty/not found')
    except Exception as e:
        print(f'  "{name}" error: {e}')
