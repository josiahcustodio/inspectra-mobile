import os
import sys
import json
import requests
from dotenv import load_dotenv

# Try importing firebase_admin, prompt to install if missing
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    print("Error: 'firebase-admin' or 'requests' package not found.")
    print("Please install them by running: pip install firebase-admin requests python-dotenv")
    sys.exit(1)

# Load variables from .env
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"

if not SUPABASE_URL or not SUPABASE_ANON_KEY:
    print("Error: SUPABASE_URL or SUPABASE_ANON_KEY not found in .env file.")
    sys.exit(1)

# 1. Initialize Firebase Admin SDK
if not os.path.exists(SERVICE_ACCOUNT_FILE):
    print(f"Error: Firebase Service Account file '{SERVICE_ACCOUNT_FILE}' not found.")
    print("\nHow to get it:")
    print("1. Go to the Firebase Console (https://console.firebase.google.com/).")
    print("2. Click on the gear icon (Project Settings) > 'Service accounts'.")
    print("3. Click 'Generate new private key' under the Firebase Admin SDK tab.")
    print(f"4. Save the downloaded JSON file as '{SERVICE_ACCOUNT_FILE}' in the root directory of this project.")
    sys.exit(1)

print("Initializing Firebase Admin...")
cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
firebase_admin.initialize_app(cred)
db = firestore.client()

# Helper function to fetch from Supabase Rest API
def fetch_supabase_table(table_name):
    print(f"Fetching table '{table_name}' from Supabase...")
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
    }
    url = f"{SUPABASE_URL.rstrip('/')}/rest/v1/{table_name}?select=*"
    
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"Failed to fetch {table_name}: {e}")
        return None

# 2. Migrate Categories
def migrate_categories():
    categories_data = fetch_supabase_table("categories")
    if not categories_data:
        print("No categories found or error occurred. Skipping categories.")
        return
    
    print(f"Migrating {len(categories_data)} categories to Firestore...")
    batch = db.batch()
    categories_ref = db.collection("categories")
    
    for cat in categories_data:
        cat_id = str(cat.get("id"))
        cat_name = cat.get("name") or cat.get("category_name") or "Unknown"
        doc_ref = categories_ref.document(cat_id)
        batch.set(doc_ref, {"name": cat_name})
        
    batch.commit()
    print("Categories migration complete!")

# 3. Migrate Establishments
def migrate_establishments():
    establishments_data = fetch_supabase_table("establishments")
    if not establishments_data:
        print("No establishments found or error occurred. Skipping establishments.")
        return
    
    print(f"Migrating {len(establishments_data)} establishments to Firestore...")
    # Firestore batches are capped at 500 operations
    batch = db.batch()
    count = 0
    
    for est in establishments_data:
        est_id = str(est.get("id"))
        
        # Format the establishment data according to what Flutter's Establishment.fromJson expects
        payload = {
            "business_name": est.get("business_name") or est.get("name") or "",
            "category": est.get("category_name") or est.get("category") or "Unknown",
            "category_id": str(est.get("category_id")) if est.get("category_id") is not None else None,
            "address": est.get("address") or "",
            "owner_name": est.get("owner_name") or "",
            "personnel_count": int(est.get("personnel_count") or 0),
            "personnel_with_hc": int(est.get("personnel_with_hc") or 0),
            "sanitary_permit_no": est.get("sanitary_permit_no") or "",
            "control_no": est.get("control_no") or "",
            "created_at": est.get("created_at") or est.get("created_time") or ""
        }
        
        doc_ref = db.collection("establishments").document(est_id)
        batch.set(doc_ref, payload)
        count += 1
        
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
            
    if count % 400 != 0:
        batch.commit()
        
    print(f"Successfully migrated {count} establishments!")

# 4. Migrate Inspection Logs
def migrate_inspection_logs():
    logs_data = fetch_supabase_table("inspection_logs")
    if not logs_data:
        print("No inspection logs found or error occurred. Skipping inspection_logs.")
        return
        
    print(f"Migrating {len(logs_data)} inspection logs to Firestore...")
    batch = db.batch()
    count = 0
    
    for log in logs_data:
        log_id = str(log.get("id"))
        
        payload = {
            "id": log_id,
            "establishment_id": str(log.get("establishment_id") or ""),
            "inspector_name": log.get("inspector_name") or "",
            "total_demerits": int(log.get("total_demerits") or 0),
            "percentage_rating": float(log.get("percentage_rating") or 0.0),
            "remarks": log.get("remarks"),
            "inspection_date": log.get("inspection_date") or log.get("created_at") or "",
            "photo_evidence_url": log.get("photo_evidence_url")
        }
        
        doc_ref = db.collection("inspection_logs").document(log_id)
        
        # Fetch inspection_results from Supabase and embed them directly into the document
        results_data = fetch_supabase_table(f"inspection_results?inspection_id=eq.{log_id}")
        if results_data:
            # Map results to match the embedded array format
            embedded_results = []
            for r in results_data:
                embedded_results.append({
                    "template_id": str(r.get("template_id") or r.get("item_id") or ""),
                    "is_compliant": r.get("is_compliant") if r.get("is_compliant") is not None else True,
                    "remarks": r.get("remarks") or ""
                })
            payload["results"] = embedded_results
        else:
            payload["results"] = []

        batch.set(doc_ref, payload)
        
        count += 1
        if count % 200 == 0:  # Lower batch size since documents are now larger
            batch.commit()
            batch = db.batch()
            
    if count % 200 != 0:
        batch.commit()
        
    print(f"Successfully migrated {count} inspection logs (with embedded results)!")

# 5. Migrate Checklist Templates
def migrate_checklist_templates():
    templates_data = fetch_supabase_table("checklist_templates")
    if not templates_data:
        print("No checklist_templates table found, trying checklist_items...")
        templates_data = fetch_supabase_table("checklist_items")
        
    if not templates_data:
        print("No checklist templates found or error occurred. Skipping checklist templates.")
        return
        
    print(f"Migrating {len(templates_data)} checklist templates to Firestore...")
    batch = db.batch()
    count = 0
    
    for temp in templates_data:
        temp_id = str(temp.get("id"))
        
        payload = {
            "category": temp.get("category_name") or temp.get("category") or "",
            "category_id": str(temp.get("category_id")) if temp.get("category_id") is not None else None,
            "sub_category": temp.get("sub_category") or "General",
            "item_name": temp.get("item_name") or temp.get("item") or "",
            "weight": int(temp.get("weight") or 5)
        }
        
        doc_ref = db.collection("checklist_templates").document(temp_id)
        batch.set(doc_ref, payload)
        
        count += 1
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
            
    if count % 400 != 0:
        batch.commit()
        
    print(f"Successfully migrated {count} checklist templates!")

if __name__ == "__main__":
    print("=== Supabase to Firestore Migration Script ===")
    migrate_categories()
    migrate_establishments()
    migrate_inspection_logs()
    migrate_checklist_templates()
    print("=== Migration Script Execution Complete ===")
