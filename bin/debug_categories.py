import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

est_docs = db.collection("establishments").stream()
temp_docs = db.collection("checklist_templates").stream()
cat_docs = db.collection("categories").stream()

categories = {doc.id: doc.to_dict().get('name') for doc in cat_docs}
print("Categories Lookup Table:", categories)

est_cats = set()
for doc in est_docs:
    d = doc.to_dict()
    cat = d.get('category')
    cat_id = d.get('category_id')
    est_cats.add(f"category='{cat}', category_id='{cat_id}'")

temp_cats = set()
for doc in temp_docs:
    d = doc.to_dict()
    cat = d.get('category')
    cat_id = d.get('category_id')
    temp_cats.add(f"category='{cat}', category_id='{cat_id}'")

print("\nEstablishment Categories found in DB:")
for c in est_cats: print(" -", c)

print("\nTemplate Categories found in DB:")
for c in temp_cats: print(" -", c)
