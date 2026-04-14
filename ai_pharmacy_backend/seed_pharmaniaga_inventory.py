"""
Seed Pharmaniaga Inventory for All 5 Clinics
==============================================
Replaces existing inventory with 50 selected medicines from the
official Pharmaniaga APPL 2023-2026 catalogue.

Clinic stock profiles:
  clinicA (KL Sentral)  — Moderately stocked, high throughput
  clinicB (Chow Kit)    — Urban dense, low stock, frequent reorders
  clinicC (Bangsar)     — Well stocked, quieter patient volume
  clinicD (Ampang)      — Mixed, mid-range stock
  clinicE (Subang)      — Critical — mostly low / borderline stock
"""

from firebase_config import db
import random

CLINICS = ['clinicA', 'clinicB', 'clinicC', 'clinicD', 'clinicE']

# ─────────────────────────────────────────────────────────────────────────────
# 50 medicines selected from Pharmaniaga APPL 2023-2026 catalogue
# Fields: name, product_code, category, unit, min_order_qty
# ─────────────────────────────────────────────────────────────────────────────
PHARMANIAGA_MEDICINES = [
    # ── Analgesics / Antipyretics ────────────────────────────────────────────
    {"name": "Paracetamol 120mg/5ml Syrup (60ml)",        "code": "D01.3003.11", "category": "Analgesic",       "unit": "Bottle",  "min_order": 100},
    {"name": "Paracetamol 120mg/5ml Syrup (120ml)",       "code": "D01.3003.20", "category": "Analgesic",       "unit": "Bottle",  "min_order": 100},

    # ── Antibiotics ──────────────────────────────────────────────────────────
    {"name": "Amoxicillin 250mg Capsule",                 "code": "D02.0015.04", "category": "Antibiotic",      "unit": "Pack",    "min_order": 50},
    {"name": "Azithromycin 500mg Powder for Infusion",    "code": "D01.5001.01", "category": "Antibiotic",      "unit": "Pack",    "min_order": 10},

    # ── Antihistamines ───────────────────────────────────────────────────────
    {"name": "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)", "code": "D01.0419.02", "category": "Antihistamine", "unit": "Bottle", "min_order": 60},
    {"name": "Diphenhydramine HCl 14mg/5ml Expectorant (90ml)", "code": "D01.0606.03", "category": "Antihistamine", "unit": "Pack", "min_order": 100},
    {"name": "Diphenhydramine HCl 7mg/5ml Expectorant (60ml)", "code": "D01.0607.05", "category": "Antihistamine", "unit": "Pack", "min_order": 100},
    {"name": "Cetirizine 10mg Tablet",                   "code": "D02.0030.10", "category": "Antihistamine",   "unit": "Pack",    "min_order": 100},

    # ── Antihypertensives ────────────────────────────────────────────────────
    {"name": "Amlodipine 5mg Tablet",                    "code": "D02.0011.01A", "category": "Antihypertensive","unit": "Pack",   "min_order": 100},
    {"name": "Amlodipine 10mg Tablet",                   "code": "D02.0011.02A", "category": "Antihypertensive","unit": "Pack",   "min_order": 100},
    {"name": "Atenolol 100mg Tablet",                    "code": "D02.0007.03A", "category": "Antihypertensive","unit": "Pack",   "min_order": 100},

    # ── Antidiabetics ────────────────────────────────────────────────────────
    {"name": "Metformin 500mg Tablet",                   "code": "D02.0095.05", "category": "Antidiabetic",    "unit": "Pack",    "min_order": 100},

    # ── Respiratory ──────────────────────────────────────────────────────────
    {"name": "Salbutamol 100mcg Inhaler (200 Doses)",    "code": "D01.1603.03", "category": "Respiratory",     "unit": "Can",     "min_order": 20},
    {"name": "Budesonide 200mcg Inhaler (200 Doses)",    "code": "D01.0208.12", "category": "Respiratory",     "unit": "Can",     "min_order": 10},
    {"name": "Beclomethasone 100mcg Inhaler (200 Doses)","code": "D01.1609.04", "category": "Respiratory",     "unit": "Can",     "min_order": 10},
    {"name": "Ipratropium Bromide 0.025% Inhalation (250mcg/ml)", "code": "D01.1602.02", "category": "Respiratory", "unit": "Pack", "min_order": 60},
    {"name": "Salbutamol 0.5% Inhalation Solution",      "code": "D01.3666.05", "category": "Respiratory",     "unit": "Pack",    "min_order": 25},

    # ── Antiparasitic / Antihelminthic ───────────────────────────────────────
    {"name": "Albendazole 200mg/5ml Suspension (10ml)",  "code": "D01.3663.04", "category": "Antiparasitic",   "unit": "Bottle",  "min_order": 12},
    {"name": "Albendazole 200mg Tablet",                 "code": "D02.0005.03", "category": "Antiparasitic",   "unit": "Pack",    "min_order": 100},
    {"name": "Oseltamivir 60mg/5ml Oral Suspension",     "code": "D01.2800.02", "category": "Antiviral",       "unit": "Bottle",  "min_order": 10},

    # ── Topical Steroids / Anti-inflammatory ─────────────────────────────────
    {"name": "Betamethasone 17-Valerate 0.025% Cream 15g", "code": "D01.0212.05", "category": "Topical Steroid", "unit": "Pack",  "min_order": 50},
    {"name": "Betamethasone 17-Valerate 0.05% Cream 15g",  "code": "D01.0212.08", "category": "Topical Steroid", "unit": "Pack",  "min_order": 50},
    {"name": "Betamethasone 17-Valerate 0.1% Ointment 15g","code": "D01.0213.02", "category": "Topical Steroid", "unit": "Pack",  "min_order": 50},
    {"name": "Hydrocortisone 1% Cream (15g)",            "code": "D01.1407.04", "category": "Topical Steroid", "unit": "Pack",    "min_order": 50},
    {"name": "Hydrocortisone 1% Ointment 15g",           "code": "D01.1406.06", "category": "Topical Steroid", "unit": "Pack",    "min_order": 50},

    # ── Topical Antifungal / Antiseptics ─────────────────────────────────────
    {"name": "Chlorhexidine Gluconate 1% Cream",         "code": "D01.0406.02", "category": "Antiseptic",      "unit": "Bottle",  "min_order": 10},
    {"name": "Chlorhexidine Gluconate 5% Solution",      "code": "D01.3632.04", "category": "Antiseptic",      "unit": "Bottle",  "min_order": 10},
    {"name": "Chlorhexidine Gluconate 4% Scrub",         "code": "D01.3636.03", "category": "Antiseptic",      "unit": "Bottle",  "min_order": 10},
    {"name": "Chlorhexidine 1:200 in Alcohol with Emollient (500ml)", "code": "D01.0413.06", "category": "Antiseptic", "unit": "Pack", "min_order": 10},
    {"name": "Silver Sulfadiazine 1% Cream 500g",        "code": "D01.3500.05", "category": "Antiseptic",      "unit": "Jar",     "min_order": 5},

    # ── Eye Preparations ─────────────────────────────────────────────────────
    {"name": "Artificial Tears / Hypromellose 0.3% Eye Drops 0.8ml Ampoule", "code": "D01.0003.02", "category": "Eye Preparation", "unit": "Pack", "min_order": 30},
    {"name": "Timolol Maleate 0.5% Eye Drops (5ml)",     "code": "D01.3829.05", "category": "Eye Preparation", "unit": "Pack",    "min_order": 20},

    # ── Skin / Dermatology ───────────────────────────────────────────────────
    {"name": "Calamine Cream (30g)",                     "code": "D01.0401.08", "category": "Dermatology",     "unit": "Pack",    "min_order": 50},
    {"name": "Calamine Lotion (120ml)",                  "code": "D01.2221.07", "category": "Dermatology",     "unit": "Pack",    "min_order": 36},
    {"name": "Aqueous Cream 100g",                       "code": "D01.0033.03", "category": "Dermatology",     "unit": "Jar",     "min_order": 10},
    {"name": "Methyl Salicylate 25% Ointment (30g)",     "code": "D01.2205.09A","category": "Topical Analgesic","unit": "Pack",   "min_order": 40},
    {"name": "Salicylic Acid 2% Ointment 15g",           "code": "D01.3601.05", "category": "Dermatology",     "unit": "Pack",    "min_order": 20},
    {"name": "Benzoic Acid Compound Ointment 450g",      "code": "D01.0211.02", "category": "Dermatology",     "unit": "Jar",     "min_order": 5},
    {"name": "Acriflavine 0.1% Lotion (100ml)",          "code": "D01.0016.05", "category": "Dermatology",     "unit": "Bottle",  "min_order": 10},

    # ── GI / Gastrointestinal ────────────────────────────────────────────────
    {"name": "Promethazine HCl 5mg/5ml Syrup",          "code": "D01.3031.06", "category": "GI / Anti-nausea","unit": "Bottle",  "min_order": 60},
    {"name": "Diphenoxylate HCl 2.5mg & Atropine 25mcg Tablet", "code": "D02.0008.05", "category": "GI / Antidiarrhoeal", "unit": "Pack", "min_order": 100},
    {"name": "Potassium Citrate & Citric Acid Mixture (120ml)", "code": "D01.3023.08", "category": "GI / Urological", "unit": "Pack", "min_order": 50},
    {"name": "Glycerin 25% & Sodium Chloride 15% Enema (20ml)", "code": "D01.0804.04", "category": "GI / Laxative", "unit": "Pack", "min_order": 10},
    {"name": "Bisacodyl 10mg Suppository",               "code": "D01.3659.03", "category": "GI / Laxative",  "unit": "Pack",    "min_order": 10},

    # ── Cardiovascular / Other Systemic ──────────────────────────────────────
    {"name": "Atorvastatin 20mg Tablet",                 "code": "D02.0015.10", "category": "Lipid Lowering",  "unit": "Pack",    "min_order": 100},
    {"name": "Ascorbic Acid 100mg Tablet",               "code": "D02.0006.07", "category": "Vitamin",         "unit": "Pack",    "min_order": 100},
    {"name": "Amiloride HCl 5mg & Hydrochlorothiazide 50mg Tablet", "code": "D02.0010.03", "category": "Diuretic", "unit": "Pack", "min_order": 100},
    {"name": "Azathioprine 50mg Tablet",                 "code": "D02.0009.02", "category": "Immunosuppressant","unit": "Pack",   "min_order": 25},

    # ── Alcohol / Disinfectants ───────────────────────────────────────────────
    {"name": "Alcohol 96% For Internal Use (5L)",        "code": "D01.0019.01", "category": "Disinfectant",    "unit": "Bottle",  "min_order": 5},
    {"name": "Alcohol 96% For External Use (5L)",        "code": "D01.0020.05", "category": "Disinfectant",    "unit": "Bottle",  "min_order": 5},
    {"name": "Ethyl Chloride 100ml Spray",               "code": "D01.3641.03", "category": "Anaesthetic",     "unit": "Can",     "min_order": 10},
]

# ─────────────────────────────────────────────────────────────────────────────
# Stock profile per clinic (min_stock, max_stock multiplier style)
# Reflects clinic "busyness" and strategic stocking decisions
# ─────────────────────────────────────────────────────────────────────────────
CLINIC_STOCK_PROFILE = {
    'clinicA': {'base_min': 80,  'base_max': 300},   # High throughput KL Sentral
    'clinicB': {'base_min': 25,  'base_max': 100},   # Urban dense Chow Kit — low stock
    'clinicC': {'base_min': 150, 'base_max': 450},   # Quieter Bangsar — well stocked
    'clinicD': {'base_min': 60,  'base_max': 200},   # Ampang — mixed
    'clinicE': {'base_min': 10,  'base_max': 80},    # Subang — critical low stock
}

# High-demand medicines get proportionally more stock
HIGH_DEMAND_ITEMS = [
    "Paracetamol 120mg/5ml Syrup (60ml)",
    "Paracetamol 120mg/5ml Syrup (120ml)",
    "Chlorpheniramine Maleate 2mg/5ml Syrup (60ml)",
    "Amoxicillin 250mg Capsule",
    "Metformin 500mg Tablet",
    "Amlodipine 5mg Tablet",
    "Atorvastatin 20mg Tablet",
    "Cetirizine 10mg Tablet",
    "Salbutamol 100mcg Inhaler (200 Doses)",
    "Calamine Cream (30g)",
    "Calamine Lotion (120ml)",
]


def clear_existing_inventory(clinic_id):
    """Delete all existing inventory docs for a clinic."""
    docs = db.collection("inventory").where("clinic_id", "==", clinic_id).stream()
    deleted = 0
    batch = db.batch()
    batch_count = 0
    for doc in docs:
        batch.delete(doc.reference)
        batch_count += 1
        deleted += 1
        if batch_count >= 400:
            batch.commit()
            batch = db.batch()
            batch_count = 0
    if batch_count > 0:
        batch.commit()
    return deleted


def seed_inventory():
    print("=" * 60)
    print("  Seeding Pharmaniaga Inventory for 5 Clinics")
    print("=" * 60)

    for clinic_id in CLINICS:
        # Clear old inventory
        deleted = clear_existing_inventory(clinic_id)
        print(f"\n[{clinic_id}] Cleared {deleted} old inventory records.")

        profile = CLINIC_STOCK_PROFILE[clinic_id]
        base_min = profile['base_min']
        base_max = profile['base_max']

        batch = db.batch()
        batch_count = 0

        for med in PHARMANIAGA_MEDICINES:
            random.seed(hash(clinic_id + med["name"]) % (2**31))

            # High demand meds get 1.5–2x more stock
            if med["name"] in HIGH_DEMAND_ITEMS:
                stock_min = int(base_min * 1.5)
                stock_max = int(base_max * 2.0)
            else:
                stock_min = base_min
                stock_max = base_max

            qty = random.randint(stock_min, stock_max)

            doc_ref = db.collection("inventory").document()
            batch.set(doc_ref, {
                "clinic_id":      clinic_id,
                "item_name":      med["name"],
                "product_code":   med["code"],
                "category":       med["category"],
                "unit":           med["unit"],
                "min_order_qty":  med["min_order"],
                "current_stock":  qty
            })

            batch_count += 1
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0

        if batch_count > 0:
            batch.commit()

        print(f"[{clinic_id}] Seeded {len(PHARMANIAGA_MEDICINES)} medicines.")
        for med in PHARMANIAGA_MEDICINES[:5]:
            print(f"    • {med['name'][:55]}")
        print(f"    ... and {len(PHARMANIAGA_MEDICINES) - 5} more.")

    print("\n" + "=" * 60)
    print(f"  Done! {len(PHARMANIAGA_MEDICINES)} medicines × {len(CLINICS)} clinics")
    print(f"  = {len(PHARMANIAGA_MEDICINES) * len(CLINICS)} total inventory records")
    print("=" * 60)


if __name__ == "__main__":
    seed_inventory()
