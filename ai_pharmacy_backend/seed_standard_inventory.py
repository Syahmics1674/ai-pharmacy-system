from firebase_config import db
import random

# All 5 clinics
CLINICS = ['clinicA', 'clinicB', 'clinicC', 'clinicD', 'clinicE']

# Standardized 10 items (mix of medicine and non-medicine)
STANDARD_ITEMS = [
    # Medicines
    "Paracetamol",
    "Uphamol",
    "Cephalexin 250mg",
    "Amoxicillin 250mg",
    "Salbutamol Inhaler",
    "Metformin 500mg",
    "Amlodipine 5mg",
    "Atorvastatin 20mg",
    # Non-medicine supplies
    "Cetirizine 10mg",
    "Insulin Glargine",
]

# Each clinic gets different quantities (realistic variance)
# Format: { clinic_id: { item: (min_stock, max_stock) } }
# Clinics that are "busier" get lower stock, quieter ones have more
CLINIC_STOCK_PROFILE = {
    'clinicA': (80, 250),   # Moderately stocked
    'clinicB': (30, 120),   # Low stock — needs reorder  
    'clinicC': (150, 400),  # Well stocked — potential donor
    'clinicD': (50, 200),   # Mixed
    'clinicE': (10, 80),    # Critical — mostly low stock
}

def clear_existing_inventory(clinic_id):
    """Delete all existing inventory docs for a clinic."""
    docs = db.collection("inventory").where("clinic_id", "==", clinic_id).stream()
    deleted = 0
    for doc in docs:
        doc.reference.delete()
        deleted += 1
    return deleted

def seed_inventory():
    print("=== Seeding Standard Inventory for All 5 Clinics ===\n")
    
    for clinic_id in CLINICS:
        # Clear old inventory
        deleted = clear_existing_inventory(clinic_id)
        print(f"[{clinic_id}] Cleared {deleted} old inventory records.")
        
        # Seed new standard inventory
        min_q, max_q = CLINIC_STOCK_PROFILE[clinic_id]
        for item in STANDARD_ITEMS:
            random.seed(hash(clinic_id + item))  # Reproducible but different per clinic
            qty = random.randint(min_q, max_q)
            db.collection("inventory").add({
                "clinic_id": clinic_id,
                "item_name": item,
                "current_stock": qty
            })
            print(f"  [OK] {item}: {qty} units")
        print()

    print("=== Done! All 5 clinics now have the same 10 standardized items ===")

if __name__ == "__main__":
    seed_inventory()
