"""
Resume seeding usage logs from where we left off.
==================================================
This script checks the latest date already in Firestore and
only writes records from that date onward, avoiding duplicates.

Run this when the Firestore daily quota has reset.
The Spark plan quota resets at midnight Pacific Time (3pm MYT next day).

Usage:
  python seed_resume_usage_logs.py
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
BATCH_DELAY = 2.5  # seconds

def safe_commit(batch, label=""):
    max_retries = 5
    for attempt in range(max_retries):
        try:
            batch.commit()
            return True
        except Exception as e:
            err_str = str(e)
            if "429" in err_str or "Quota" in err_str or "RESOURCE_EXHAUSTED" in err_str:
                wait = (attempt + 1) * 15
                print(f"    [THROTTLE] Quota hit {label}, waiting {wait}s (attempt {attempt+1}/{max_retries})...")
                time.sleep(wait)
            else:
                raise
    print(f"    [FAILED] Could not commit after {max_retries} retries {label}.")
    return False


def get_day_multiplier(date, clinic_id):
    month = date.month
    day = date.day
    wday = date.weekday()
    multipliers = {}
    base = 1.0

    if wday >= 5:
        return {"__base__": 0.15}

    if month in [1, 2, 3]:
        m = 1.8 if month in [1, 2] else 1.4
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)", "Paracetamol 120mg/5ml Syrup (120ml)",
                     "Calamine Cream (30g)", "Calamine Lotion (120ml)", "Cetirizine 10mg Tablet",
                     "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)"]:
            multipliers[item] = m

    if month in [10, 11, 12]:
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)", "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)",
                     "Calamine Cream (30g)", "Calamine Lotion (120ml)"]:
            multipliers[item] = multipliers.get(item, 1.0) * 1.4

    if month in [11, 12, 1, 2]:
        for item in ["Salbutamol 100mcg Inhaler (200 Doses)", "Budesonide 200mcg Inhaler (200 Doses)",
                     "Beclomethasone 100mcg Inhaler (200 Doses)",
                     "Diphenhydramine HCl 14mg/5ml Expectorant (90ml)",
                     "Diphenhydramine HCl 7mg/5ml Expectorant (60ml)",
                     "Amoxicillin 250mg Capsule", "Promethazine HCl 5mg/5ml Syrup"]:
            multipliers[item] = multipliers.get(item, 1.0) * 1.6

    if month in [8, 9]:
        for item in ["Salbutamol 100mcg Inhaler (200 Doses)", "Cetirizine 10mg Tablet",
                     "Salbutamol 0.5% Inhalation Solution"]:
            multipliers[item] = multipliers.get(item, 1.0) * 1.3

    if month == 1 and 27 <= day <= 31: base *= 0.4
    if month == 2 and 1 <= day <= 3: base *= 0.4
    if month == 2 and 4 <= day <= 14: base *= 1.3
    if month == 4 and 8 <= day <= 13: base *= 0.3

    if (month == 6 and day >= 18) or (month == 7 and day <= 14):
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)", "Paracetamol 120mg/5ml Syrup (120ml)",
                     "Albendazole 200mg/5ml Suspension (10ml)", "Amoxicillin 250mg Capsule"]:
            multipliers[item] = multipliers.get(item, 1.0) * 0.6

    multipliers["__base__"] = base
    return multipliers


def get_epidemic_spike(date, clinic_id, item_name):
    if date.year == 2024 and date.month == 7 and 14 <= date.day <= 18:
        if clinic_id == 'clinicA' and "Paracetamol" in item_name:
            return random.randint(30, 80)
    if date.year == 2024 and date.month == 11 and 4 <= date.day <= 10:
        if clinic_id == 'clinicB':
            if "Calamine" in item_name or "Chlorpheniramine" in item_name or "Paracetamol" in item_name:
                return random.randint(20, 60)
    if date.year == 2025 and date.month == 1 and 20 <= date.day <= 24:
        if "Paracetamol" in item_name or "Diphenhydramine" in item_name or "Amoxicillin" in item_name:
            return random.randint(15, 45)
    if date.year == 2024 and date.month == 9 and 2 <= date.day <= 6:
        if clinic_id in ['clinicC', 'clinicD'] and "Salbutamol" in item_name:
            return random.randint(10, 25)
    return 0


def find_latest_date():
    """Find the latest timestamp in existing usage_logs."""
    print("Finding latest existing record...")
    try:
        docs = db.collection("usage_logs").order_by(
            "timestamp", direction="DESCENDING"
        ).limit(1).stream()
        for doc in docs:
            ts = doc.to_dict().get("timestamp")
            if ts:
                print(f"  Latest record: {ts}")
                return ts
    except Exception as e:
        print(f"  Error querying: {e}")
    return None


def seed_from_date(resume_date):
    """Seed usage logs starting from resume_date to Apr 13, 2025."""

    end_date = datetime(2025, 4, 13, 23, 59, 59)
    start_date = resume_date.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)

    if hasattr(start_date, 'tzinfo') and start_date.tzinfo:
        start_date = start_date.replace(tzinfo=None)

    total_days = (end_date - start_date).days
    if total_days <= 0:
        print("  No more days to seed! Data is complete.")
        return

    print("=" * 60)
    print(f"  RESUMING from {start_date.strftime('%Y-%m-%d')}")
    print(f"  Remaining: {total_days} days to seed")
    print("=" * 60)

    usage_ref = db.collection("usage_logs")
    batch = db.batch()
    batch_count = 0
    total_added = 0
    commits = 0

    # Use same random seed offset so epidemic events are reproducible
    random.seed(42)

    for day_offset in range(total_days + 1):
        current_date = start_date + timedelta(days=day_offset)

        if day_offset % 15 == 0:
            pct = int(day_offset / max(total_days, 1) * 100)
            print(f"  [{pct:3d}%] {current_date.strftime('%Y-%m-%d')} | {total_added:,} records | {commits} commits")

        for clinic_id in CLINICS:
            clinic_mult = CLINIC_THROUGHPUT[clinic_id]
            day_mods = get_day_multiplier(current_date, clinic_id)
            base_mult = day_mods.get("__base__", 1.0)

            if base_mult <= 0.2:
                if random.random() > 0.95:
                    qty = random.randint(1, 3)
                    doc_ref = usage_ref.document()
                    ts = current_date.replace(hour=random.randint(8,17), minute=random.randint(0,59))
                    batch.set(doc_ref, {
                        "clinic_id": clinic_id,
                        "item_name": "Paracetamol 120mg/5ml Syrup (60ml)",
                        "quantity_used": qty,
                        "timestamp": ts,
                    })
                    batch_count += 1
                    total_added += 1
                continue

            for item_name, (base_min, base_max) in MEDICINES.items():
                chronic = any(k in item_name for k in [
                    "Metformin", "Amlodipine", "Atenolol", "Atorvastatin",
                    "Azathioprine", "Amiloride", "Ascorbic"
                ])

                skip_chance = 0.20 if chronic else 0.55
                if random.random() < skip_chance:
                    continue

                item_mult = day_mods.get(item_name, 1.0)
                effective_mult = base_mult * clinic_mult * item_mult

                qty_min = max(1, int(base_min * effective_mult))
                qty_max = max(qty_min + 1, int(base_max * effective_mult))
                qty = random.randint(qty_min, qty_max)

                spike = get_epidemic_spike(current_date, clinic_id, item_name)
                qty += spike

                if random.random() < 0.05:
                    qty = int(qty * random.uniform(1.2, 1.5))

                ts = current_date.replace(
                    hour=random.randint(8, 16),
                    minute=random.randint(0, 59),
                    second=0
                )

                doc_ref = usage_ref.document()
                batch.set(doc_ref, {
                    "clinic_id": clinic_id,
                    "item_name": item_name,
                    "quantity_used": qty,
                    "timestamp": ts,
                })
                batch_count += 1
                total_added += 1

                if batch_count >= BATCH_SIZE:
                    ok = safe_commit(batch, f"({total_added:,})")
                    if not ok:
                        print(f"\n  [STOPPED] Quota exhausted at {total_added:,} records.")
                        print(f"  Resume point: {current_date.strftime('%Y-%m-%d')}")
                        print(f"  Re-run this script after quota resets.")
                        return
                    time.sleep(BATCH_DELAY)
                    batch = db.batch()
                    batch_count = 0
                    commits += 1

    if batch_count > 0:
        safe_commit(batch, f"(final {total_added:,})")

    print()
    print("=" * 60)
    print(f"  DONE! Generated {total_added:,} additional usage log records.")
    print("=" * 60)


if __name__ == "__main__":
    latest = find_latest_date()
    if latest:
        seed_from_date(latest)
    else:
        print("No existing data found. Run seed_realistic_usage_logs.py first.")
        print("Or starting from scratch...")
        start = datetime(2024, 4, 13)
        seed_from_date(start)
