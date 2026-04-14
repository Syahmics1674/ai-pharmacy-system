from firebase_config import db

print("=== CLINICS ===")
clinics = list(db.collection("clinics").stream())
for doc in clinics:
    d = doc.to_dict()
    print(f"  Clinic ID: {doc.id} | Name: {d.get('name', 'N/A')} | Route: {d.get('route_id', 'N/A')}")
print(f"Total clinics: {len(clinics)}")

print()
print("=== USER ACCOUNTS (for login) ===")
users = list(db.collection("users").stream())
for doc in users:
    d = doc.to_dict()
    print(f"  Username: {d.get('username', 'N/A')} | Password: {d.get('password', 'N/A')} | Clinic: {d.get('clinic_id', 'N/A')}")
print(f"Total user accounts: {len(users)}")
