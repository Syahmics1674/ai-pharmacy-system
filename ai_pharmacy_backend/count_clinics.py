from firebase_config import db
import sys

def count_clinics():
    clinics_ref = db.collection("clinics")
    docs = clinics_ref.get()
    
    print(f"Total clinics counted: {len(docs)}")
    if len(docs) > 0:
        print("Clinic details:")
        for doc in docs:
            data = doc.to_dict()
            name = data.get('clinic_name', 'Unknown')
            print(f"- ID: {doc.id}, Name: {name}")

if __name__ == "__main__":
    count_clinics()
