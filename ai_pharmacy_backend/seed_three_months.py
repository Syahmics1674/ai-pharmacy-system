"""
Seed 3 Months of Realistic Usage Logs (Malaysia)
==================================================
Fits within the Firestore Spark plan 20K write quota.

Strategy: 
  - Past 90 days (approx. Jan 13 -> Apr 13, 2025)
  - Small batches (100 docs) with 2.5s delay
  - Retry-on-429 logic
"""

import random
import time
from datetime import datetime, timedelta
from firebase_config import db

CLINICS = ['clinicA', 'clinicB', 'clinicC', 'clinicD', 'clinicE']

CLINIC_THROUGHPUT = {
    'clinicA': 1.3,
    'clinicB': 1.1,
    'clinicC': 0.7,
    'clinicD': 0.9,
    'clinicE': 0.8,
}

# 51 Medicines
MEDICINES = {
    "Paracetamol 120mg/5ml Syrup (60ml)":                  (5,  30),
    "Paracetamol 120mg/5ml Syrup (120ml)":                 (3,  20),
    "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)":       (4,  25),
    "Diphenhydramine HCl 14mg/5ml Expectorant (90ml)":     (3,  18),
    "Diphenhydramine HCl 7mg/5ml Expectorant (60ml)":      (3,  18),
    "Albendazole 200mg/5ml Suspension (10ml)":             (1,   8),
    "Promethazine HCl 5mg/5ml Syrup":                      (2,  12),
    "Salbutamol 100mcg Inhaler (200 Doses)":               (2,  12),
    "Budesonide 200mcg Inhaler (200 Doses)":               (1,   5),
    "Beclomethasone 100mcg Inhaler (200 Doses)":           (1,   5),
    "Ipratropium Bromide 0.025% Inhalation (250mcg/ml)":   (2,   8),
    "Salbutamol 0.5% Inhalation Solution":                 (2,   8),
    "Amoxicillin 250mg Capsule":                           (5,  30),
    "Azithromycin 500mg Powder for Infusion":              (1,   5),
    "Cetirizine 10mg Tablet":                              (5,  20),
    "Amlodipine 5mg Tablet":                               (8,  25),
    "Amlodipine 10mg Tablet":                              (4,  15),
    "Atenolol 100mg Tablet":                               (5,  18),
    "Metformin 500mg Tablet":                             (10,  35),
    "Atorvastatin 20mg Tablet":                            (8,  25),
    "Amiloride HCl 5mg & Hydrochlorothiazide 50mg Tablet": (3,  12),
    "Azathioprine 50mg Tablet":                            (1,   5),
    "Ascorbic Acid 100mg Tablet":                          (3,  15),
    "Calamine Cream (30g)":                                (3,  20),
    "Calamine Lotion (120ml)":                             (3,  20),
    "Betamethasone 17-Valerate 0.025% Cream 15g":          (2,  10),
    "Betamethasone 17-Valerate 0.05% Cream 15g":           (2,  10),
    "Betamethasone 17-Valerate 0.1% Ointment 15g":         (2,  10),
    "Hydrocortisone 1% Cream (15g)":                       (3,  12),
    "Hydrocortisone 1% Ointment 15g":                      (2,   8),
    "Methyl Salicylate 25% Ointment (30g)":                (2,   8),
    "Salicylic Acid 2% Ointment 15g":                      (1,   6),
    "Benzoic Acid Compound Ointment 450g":                 (1,   4),
    "Acriflavine 0.1% Lotion (100ml)":                     (1,   6),
    "Aqueous Cream 100g":                                  (1,   6),
    "Chlorhexidine Gluconate 1% Cream":                    (1,   6),
    "Chlorhexidine Gluconate 5% Solution":                 (1,   5),
    "Chlorhexidine Gluconate 4% Scrub":                    (1,   5),
    "Chlorhexidine 1:200 in Alcohol with Emollient (500ml)":(1,  5),
    "Silver Sulfadiazine 1% Cream 500g":                   (1,   3),
    "Alcohol 96% For Internal Use (5L)":                   (1,   3),
    "Alcohol 96% For External Use (5L)":                   (1,   3),
    "Ethyl Chloride 100ml Spray":                          (1,   4),
    "Artificial Tears / Hypromellose 0.3% Eye Drops 0.8ml Ampoule": (3, 15),
    "Timolol Maleate 0.5% Eye Drops (5ml)":               (2,   8),
    "Albendazole 200mg Tablet":                            (2,   8),
    "Oseltamivir 60mg/5ml Oral Suspension":                (1,   6),
    "Diphenoxylate HCl 2.5mg & Atropine 25mcg Tablet":    (2,   8),
    "Potassium Citrate & Citric Acid Mixture (120ml)":     (2,   8),
    "Glycerin 25% & Sodium Chloride 15% Enema (20ml)":    (1,   4),
    "Bisacodyl 10mg Suppository":                          (1,   4),
}

BATCH_SIZE = 100
BATCH_DELAY = 1.0  # seconds

def safe_commit(batch, label=""):
    max_retries = 10
    for attempt in range(max_retries):
        try:
            batch.commit()
            return True
        except Exception as e:
            err_str = str(e)
            if "429" in err_str or "Quota" in err_str or "RESOURCE_EXHAUSTED" in err_str:
                wait = (attempt + 1) * 30  # Wait much longer (30s, 60s, 90s...)
                print(f"    [THROTTLE] Quota hit {label}, waiting {wait}s (attempt {attempt+1}/{max_retries})...")
                time.sleep(wait)
            else:
                raise
    print(f"    [FAILED] Could not commit {label}.")
    return False

def get_day_multiplier(date, clinic_id):
    month = date.month
    day = date.day
    wday = date.weekday()
    multipliers = {}
    
    if wday >= 5: return {"__base__": 0.15}
    
    # Dengue/Flu (Jan-Feb)
    if month in [1, 2]:
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)", "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)"]:
            multipliers[item] = 1.8
            
    # CNY (late Jan/early Feb)
    if month == 1 and 27 <= day <= 31: return {"__base__": 0.4}
    
    return {"__base__": 1.1}

def clear_usage_logs():
    print("Clearing usage logs...")
    batch = db.batch()
    count = 0
    docs = db.collection("usage_logs").limit(500).stream() 
    for doc in docs:
        batch.delete(doc.reference)
        count += 1
        if count >= BATCH_SIZE:
            safe_commit(batch, "(clear)")
            batch = db.batch()
            count = 0
            time.sleep(BATCH_DELAY)
    if count > 0: safe_commit(batch, "(clear-final)")

def seed_three_months():
    end_date = datetime.now()
    start_date = end_date - timedelta(days=90)
    print(f"Seeding from {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}...")
    
    usage_ref = db.collection("usage_logs")
    batch = db.batch()
    batch_count = 0
    total_added = 0
    
    current_date = start_date
    while current_date <= end_date:
        for clinic_id in CLINICS:
            clinic_mult = CLINIC_THROUGHPUT[clinic_id]
            day_mods = get_day_multiplier(current_date, clinic_id)
            base_mult = day_mods.get("__base__", 1.0)
            
            if base_mult <= 0.2: continue # Simplified: skip weekends
            
            for item_name, (base_min, base_max) in MEDICINES.items():
                # Scale down probability to stay under quota
                if random.random() < 0.6: continue
                
                item_mult = day_mods.get(item_name, 1.0)
                qty = random.randint(base_min, base_max)
                qty = int(qty * clinic_mult * base_mult * item_mult)
                
                doc_ref = usage_ref.document()
                batch.set(doc_ref, {
                    "clinic_id": clinic_id,
                    "item_name": item_name,
                    "quantity_used": qty,
                    "timestamp": current_date.replace(hour=random.randint(8,16), minute=random.randint(0,59))
                })
                batch_count += 1
                total_added += 1
                
                if batch_count >= BATCH_SIZE:
                    print(f"  Writing {total_added} records...")
                    safe_commit(batch, f"(seed-{total_added})")
                    batch = db.batch()
                    batch_count = 0
                    time.sleep(BATCH_DELAY)
                    
        current_date += timedelta(days=1)
        
    if batch_count > 0: safe_commit(batch, "(seed-final)")
    print(f"Done! Seeded {total_added} records.")

if __name__ == "__main__":
    clear_usage_logs()
    seed_three_months()
