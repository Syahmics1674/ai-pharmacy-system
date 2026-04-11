import random
import time
from datetime import datetime, timedelta
from firebase_config import db

CLINICS = ['clinicA', 'clinicB', 'clinicC', 'clinicD', 'clinicE']
# Based on existing db inventory check tool
ITEMS = [
    "Paracetamol", "Amoxicillin", "Lisinopril", "Metformin", "Omeprazole", 
    "Amlodipine", "Simvastatin", "Losartan", "Albuterol", "Gabapentin"
]

def seed_usage_logs():
    print("Seeding ~6 months of data...")
    usage_ref = db.collection("usage_logs")
    
    # 6 months ago
    start_date = datetime.utcnow() - timedelta(days=180)
    
    batch = db.batch()
    batch_count = 0
    total_added = 0
    
    for day in range(180):
        current_date = start_date + timedelta(days=day)
        
        # Determine if it's "Flu Season" (e.g. days 60 to 90)
        is_flu_season = 60 <= day <= 90
        
        for clinic in CLINICS:
            # Maybe not all clinics use all items every single day
            for item in ITEMS:
                if random.random() > 0.7:  # 30% chance a clinic uses an item on a given day
                    # Base usage
                    base_usage = random.randint(10, 50)
                    
                    # Add spikes for specific items
                    if is_flu_season and item in ["Paracetamol", "Amoxicillin"]:
                        base_usage += random.randint(50, 150)
                        
                    # Random anomaly (epidemic simulation on a random day)
                    if day == 170 and clinic == "clinicA" and item == "Paracetamol":
                        base_usage = 300 # Massive spike 10 days ago!
                        
                    doc_ref = usage_ref.document()
                    batch.set(doc_ref, {
                        "clinic_id": clinic,
                        "item_name": item,
                        "quantity_used": base_usage,
                        "timestamp": current_date
                    })
                    
                    batch_count += 1
                    total_added += 1
                    
                    if batch_count >= 400:
                        batch.commit()
                        batch = db.batch()
                        batch_count = 0
                        print(f"Committed {total_added} records...")

    if batch_count > 0:
        batch.commit()
        print(f"Committed {total_added} records...")
        
    print(f"Seeding complete! Generated {total_added} synthetic usage logs.")

if __name__ == "__main__":
    seed_usage_logs()
