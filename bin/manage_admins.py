"""
Manage Inspectra admins: list, promote, and demote.

Self-signup can only ever create an 'officer' profile (enforced by
firestore.rules), so admin status has to be granted by hand — this script
does that via the Admin SDK, which bypasses the client-facing security rules.

The city prompt on promotion isn't a real multi-tenant check (Inspectra is
single-city today — every establishment's `city` field is hardcoded to
"Batangas City" in both the web and mobile clients, see
AddEstablishmentModal.tsx / add_establishment_screen.dart). It's here so that
if this ever becomes multi-LGU, `profiles.city` already exists using the same
field name `establishments.city` uses, and so promoting someone requires
deliberately typing the LGU name rather than a blind y/N.

Every promote/demote is appended to admin_actions.log (gitignored) next to
this script, so there's a local record of who granted/revoked admin and when.

Usage: python manage_admins.py
"""

import datetime
import os
import re
import sys

try:
    import firebase_admin
    from firebase_admin import auth, credentials, firestore
    from google.cloud.firestore_v1.base_query import FieldFilter
except ImportError:
    print("Error: 'firebase-admin' package not found.")
    print("Please install it by running: pip install firebase-admin")
    sys.exit(1)

SERVICE_ACCOUNT_FILE = "serviceAccountKey.json"
EXPECTED_CITY = "Batangas City"
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "admin_actions.log")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def init_db():
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        print(f"Error: Firebase Service Account file '{SERVICE_ACCOUNT_FILE}' not found.")
        print("\nHow to get it:")
        print("1. Go to the Firebase Console (https://console.firebase.google.com/).")
        print("2. Click the gear icon (Project Settings) > 'Service accounts'.")
        print("3. Click 'Generate new private key' under the Firebase Admin SDK tab.")
        print(f"4. Save the downloaded JSON file as '{SERVICE_ACCOUNT_FILE}' in this directory.")
        sys.exit(1)

    cred = credentials.Certificate(SERVICE_ACCOUNT_FILE)
    firebase_admin.initialize_app(cred)
    return firestore.client()


def log_action(action, email, uid, detail=""):
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    line = f"{now}  {action}  {email}  uid={uid}  {detail}".rstrip()
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def normalize_email(raw):
    return raw.strip().lower()


def get_user_by_email(email):
    try:
        return auth.get_user_by_email(email)
    except auth.UserNotFoundError:
        return None


def get_admin_docs(db):
    return list(db.collection("profiles").where(filter=FieldFilter("role", "==", "admin")).stream())


def list_admins(db):
    admins = get_admin_docs(db)
    if not admins:
        print("No admins found.")
        return
    print(f"{len(admins)} admin(s):")
    for doc in admins:
        data = doc.to_dict()
        city = data.get("city", "-")
        print(f"  - {data.get('email', '(no email on profile)')}  uid={doc.id}  city={city}")


def confirm_by_retyping_email(email):
    """Require the operator to retype the exact email — a plain y/N is too
    easy to hit by reflex for a privilege change with security consequences."""
    typed = input(f"Type '{email}' again to confirm: ").strip().lower()
    return typed == email


def promote(db):
    email = normalize_email(input("Email address to promote to admin: "))
    if not EMAIL_RE.match(email):
        print("Error: that doesn't look like a valid email address.")
        return

    user = get_user_by_email(email)
    if user is None:
        print(f"Error: no Firebase Auth account found for '{email}'.")
        print("The user needs to sign up in the app first — this only promotes existing accounts.")
        return

    profile_ref = db.collection("profiles").document(user.uid)
    profile_snap = profile_ref.get()
    current_role = profile_snap.to_dict().get("role") if profile_snap.exists else None

    if current_role == "admin":
        print(f"'{email}' (uid={user.uid}) is already an admin. Nothing to do.")
        return

    city = input(f"Type the LGU this admin belongs to (currently only '{EXPECTED_CITY}' is supported): ").strip()
    if city != EXPECTED_CITY:
        print(f"Error: '{city}' doesn't match the only supported LGU ('{EXPECTED_CITY}'). Cancelled.")
        return

    label = current_role or "no profile yet"
    print(f"About to promote '{email}' (uid={user.uid}, current role: {label}) to admin for {city}.")
    if not confirm_by_retyping_email(email):
        print("Email didn't match. Cancelled.")
        return

    profile_ref.set({"role": "admin", "email": email, "city": city}, merge=True)
    log_action("PROMOTE", email, user.uid, f"from={label} city={city}")
    print(f"Done — '{email}' is now an admin.")


def demote(db):
    email = normalize_email(input("Email address to demote from admin: "))
    if not EMAIL_RE.match(email):
        print("Error: that doesn't look like a valid email address.")
        return

    user = get_user_by_email(email)
    if user is None:
        print(f"Error: no Firebase Auth account found for '{email}'.")
        return

    profile_ref = db.collection("profiles").document(user.uid)
    profile_snap = profile_ref.get()
    current_role = profile_snap.to_dict().get("role") if profile_snap.exists else None

    if current_role != "admin":
        print(f"'{email}' (uid={user.uid}) is not currently an admin (role: {current_role or 'none'}). Nothing to do.")
        return

    remaining_admins = [d for d in get_admin_docs(db) if d.id != user.uid]
    if not remaining_admins:
        print(
            f"Error: '{email}' is the ONLY admin. Refusing to demote — this would lock everyone "
            "out of /admin routes and reference-data management. Promote someone else first."
        )
        return

    print(f"About to demote '{email}' (uid={user.uid}) back to officer.")
    if not confirm_by_retyping_email(email):
        print("Email didn't match. Cancelled.")
        return

    profile_ref.set({"role": "officer"}, merge=True)
    log_action("DEMOTE", email, user.uid)
    print(f"Done — '{email}' is now an officer.")


def main():
    db = init_db()
    actions = {
        "1": ("List admins", list_admins),
        "2": ("Promote a user to admin", promote),
        "3": ("Demote an admin to officer", demote),
    }
    while True:
        print("\n=== Inspectra Admin Management ===")
        for key, (label, _) in actions.items():
            print(f"  {key}. {label}")
        print("  4. Exit")
        choice = input("Choose an option: ").strip()
        if choice == "4":
            break
        action = actions.get(choice)
        if action is None:
            print("Invalid option.")
            continue
        action[1](db)


if __name__ == "__main__":
    main()
