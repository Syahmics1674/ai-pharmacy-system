from firebase_config import db

def seed_clinics():
    clinics = ['clinicA', 'clinicB', 'clinicC', 'clinicD', 'clinicE']
    for cid in clinics:
        db.collection('clinics').document(cid).set({
            'name': f'Kuala Lumpur Health Clinic_{cid[-1]}',
            'route_id': 'Route_Alpha'
        })
        print(f"Seeded {cid} with route_id: Route_Alpha")

if __name__ == "__main__":
    seed_clinics()
