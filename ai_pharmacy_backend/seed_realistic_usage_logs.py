"""
Seed Realistic Usage Logs - Past 1 Year (Malaysia)
====================================================
Rate-limited version for Firestore Spark plan (20K writes/day).

Strategy: Write in small batches (100 docs) with 2s delay between.
Includes retry logic for 429 Quota Exceeded errors.

Run this script and let it complete. If it crashes partway, re-run
and it will continue (it clears and re-seeds from scratch, but with
proper throttling it should finish in ~15 min).
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

# =====================================================================
# BATCH WRITER WITH RETRY
# =====================================================================
BATCH_SIZE = 100
BATCH_DELAY = 2.0  # seconds between commits

def safe_commit(batch, label=""):
    """Commit a batch with retry on quota exceeded."""
    max_retries = 5
    for attempt in range(max_retries):
        try:
            batch.commit()
            return
        except Exception as e:
            err_str = str(e)
            if "429" in err_str or "Quota" in err_str or "RESOURCE_EXHAUSTED" in err_str:
                wait = (attempt + 1) * 10  # 10s, 20s, 30s...
                print(f"    [THROTTLE] Quota hit {label}, waiting {wait}s (attempt {attempt+1}/{max_retries})...")
                time.sleep(wait)
            else:
                raise
    print(f"    [WARNING] Failed after {max_retries} retries {label}. Continuing...")


# =====================================================================
# SEASONAL MODIFIERS
# =====================================================================
def get_day_multiplier(date, clinic_id):
    month = date.month
    day = date.day
    wday = date.weekday()

    multipliers = {}
    base = 1.0

    if wday >= 5:
        base = 0.15
        return {"__base__": base}

    # Dengue (Jan-Mar)
    if month in [1, 2, 3]:
        dengue_mult = 1.8 if month in [1, 2] else 1.4
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)",
                     "Paracetamol 120mg/5ml Syrup (120ml)",
                     "Calamine Cream (30g)", "Calamine Lotion (120ml)",
                     "Cetirizine 10mg Tablet",
                     "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)"]:
            multipliers[item] = dengue_mult

    # Oct-Dec dengue
    if month in [10, 11, 12]:
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)",
                     "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)",
                     "Calamine Cream (30g)", "Calamine Lotion (120ml)"]:
            multipliers[item] = multipliers.get(item, 1.0) * 1.4

    # Monsoon respiratory (Nov-Feb)
    if month in [11, 12, 1, 2]:
        for item in ["Salbutamol 100mcg Inhaler (200 Doses)",
                     "Budesonide 200mcg Inhaler (200 Doses)",
                     "Beclomethasone 100mcg Inhaler (200 Doses)",
                     "Diphenhydramine HCl 14mg/5ml Expectorant (90ml)",
                     "Diphenhydramine HCl 7mg/5ml Expectorant (60ml)",
                     "Amoxicillin 250mg Capsule",
                     "Promethazine HCl 5mg/5ml Syrup"]:
            multipliers[item] = multipliers.get(item, 1.0) * 1.6

    # Haze (Aug-Sep)
    if month in [8, 9]:
        for item in ["Salbutamol 100mcg Inhaler (200 Doses)",
                     "Cetirizine 10mg Tablet",
                     "Salbutamol 0.5% Inhalation Solution"]:
            multipliers[item] = multipliers.get(item, 1.0) * 1.3

    # CNY week (late Jan)
    if month == 1 and 27 <= day <= 31:
        base *= 0.4
    if month == 2 and 1 <= day <= 3:
        base *= 0.4
    if month == 2 and 4 <= day <= 14:
        base *= 1.3

    # Hari Raya (Apr 10-11)
    if month == 4 and 8 <= day <= 13:
        base *= 0.3

    # School holiday (Jun-Jul)
    if (month == 6 and day >= 18) or (month == 7 and day <= 14):
        for item in ["Paracetamol 120mg/5ml Syrup (60ml)",
                     "Paracetamol 120mg/5ml Syrup (120ml)",
                     "Albendazole 200mg/5ml Suspension (10ml)",
                     "Amoxicillin 250mg Capsule"]:
            multipliers[item] = multipliers.get(item, 1.0) * 0.6

    multipliers["__base__"] = base
    return multipliers


def get_epidemic_spike(date, clinic_id, item_name):
    # Event 1: Jul 2024 heat wave clinicA
    if date.year == 2024 and date.month == 7 and 14 <= date.day <= 18:
        if clinic_id == 'clinicA' and "Paracetamol" in item_name:
            return random.randint(30, 80)

    # Event 2: Nov 2024 dengue cluster clinicB
    if date.year == 2024 and date.month == 11 and 4 <= date.day <= 10:
        if clinic_id == 'clinicB':
            if "Calamine" in item_name or "Chlorpheniramine" in item_name or "Paracetamol" in item_name:
                return random.randint(20, 60)

    # Event 3: Jan 2025 flu outbreak all clinics
    if date.year == 2025 and date.month == 1 and 20 <= date.day <= 24:
        if "Paracetamol" in item_name or "Diphenhydramine" in item_name or "Amoxicillin" in item_name:
            return random.randint(15, 45)

    # Event 4: Sep 2024 haze week clinicC/D
    if date.year == 2024 and date.month == 9 and 2 <= date.day <= 6:
        if clinic_id in ['clinicC', 'clinicD'] and "Salbutamol" in item_name:
            return random.randint(10, 25)

    return 0


# =====================================================================
# CLEAR
# =====================================================================
def clear_usage_logs():
    print("Clearing existing usage_logs...")
    deleted = 0
    batch = db.batch()
    batch_count = 0
    docs = db.collection("usage_logs").stream()
    for doc in docs:
        batch.delete(doc.reference)
        batch_count += 1
        deleted += 1
        if batch_count >= BATCH_SIZE:
            safe_commit(batch, f"(clear {deleted})")
            time.sleep(BATCH_DELAY)
            batch = db.batch()
            batch_count = 0
    if batch_count > 0:
        safe_commit(batch, f"(clear final {deleted})")
    print(f"Cleared {deleted} existing usage_log records.")
    return deleted


# =====================================================================
# SEED
# =====================================================================
def seed_usage_logs():
    print("=" * 60)
    print("  Seeding 1 Year of Realistic Usage Logs")
    print("  Coverage: Apr 13, 2024 -> Apr 13, 2025")
    print("  Clinics: 5  |  Medicines: 51")
    print("=" * 60)

    end_date   = datetime(2025, 4, 13, 23, 59, 59)
    start_date = datetime(2024, 4, 13, 0, 0, 0)
    total_days = (end_date - start_date).days

    usage_ref = db.collection("usage_logs")
    batch = db.batch()
    batch_count = 0
    total_added = 0

    for day_offset in range(total_days + 1):
        current_date = start_date + timedelta(days=day_offset)

        if day_offset % 30 == 0:
            pct = int(day_offset / total_days * 100)
            print(f"  [{pct:3d}%] Processing {current_date.strftime('%Y-%m-%d')} ... ({total_added:,} records so far)")

        for clinic_id in CLINICS:
            clinic_mult = CLINIC_THROUGHPUT[clinic_id]
            day_mods = get_day_multiplier(current_date, clinic_id)
            base_mult = day_mods.get("__base__", 1.0)

            # Skip weekends almost entirely
            if base_mult <= 0.2:
                if random.random() > 0.95:
                    qty = random.randint(1, 3)
                    doc_ref = usage_ref.document()
                    hour = random.randint(8, 17)
                    ts = current_date.replace(hour=hour, minute=random.randint(0,59))
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

                # Chronic: 80% chance; others: 45% chance of being dispensed
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

                hour = random.randint(8, 16)
                minute = random.randint(0, 59)
                ts = current_date.replace(hour=hour, minute=minute, second=0)

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
                    safe_commit(batch, f"({total_added:,})")
                    time.sleep(BATCH_DELAY)
                    batch = db.batch()
                    batch_count = 0

    if batch_count > 0:
        safe_commit(batch, f"(final {total_added:,})")

    print()
    print("=" * 60)
    print(f"  DONE! Generated {total_added:,} usage log records.")
    print(f"  Covering {total_days} days for {len(CLINICS)} clinics")
    print(f"  ({len(MEDICINES)} medicines each)")
    print("=" * 60)


if __name__ == "__main__":
    clear_usage_logs()
    print()
    seed_usage_logs()
