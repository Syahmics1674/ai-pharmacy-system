import argparse
import json
import re
from pathlib import Path

from firebase_admin import firestore

from firebase_config import db


DEFAULT_MIN_QTY = 100
UNMATCHED_LOG_PATH = Path(__file__).with_name("unmatched_inventory_items.json")

MEDICINES = [
    {"id": "PCM001", "name": "Paracetamol 500mg Tablet", "category": "Analgesic", "unit": "Tablet"},
    {"id": "PCM002", "name": "Paracetamol Syrup 120mg/5ml", "category": "Analgesic", "unit": "Bottle"},
    {"id": "IBU001", "name": "Ibuprofen 200mg Tablet", "category": "Analgesic", "unit": "Tablet"},
    {"id": "MEF001", "name": "Mefenamic Acid 250mg Capsule", "category": "Analgesic", "unit": "Capsule"},
    {"id": "NAP001", "name": "Naproxen 275mg Tablet", "category": "Analgesic", "unit": "Tablet"},
    {"id": "ANT001", "name": "Chlorpheniramine 4mg Tablet", "category": "Antihistamine", "unit": "Tablet"},
    {"id": "ANT002", "name": "Cetirizine 10mg Tablet", "category": "Antihistamine", "unit": "Tablet"},
    {"id": "ANT003", "name": "Cetirizine Syrup", "category": "Antihistamine", "unit": "Bottle"},
    {"id": "ANT004", "name": "Loratadine 10mg Tablet", "category": "Antihistamine", "unit": "Tablet"},
    {"id": "ANT005", "name": "Diphenhydramine Expectorant", "category": "Antihistamine", "unit": "Bottle"},
    {"id": "RESP001", "name": "Salbutamol Tablet", "category": "Respiratory", "unit": "Tablet"},
    {"id": "RESP002", "name": "Salbutamol Syrup", "category": "Respiratory", "unit": "Bottle"},
    {"id": "RESP003", "name": "Salbutamol Inhaler", "category": "Respiratory", "unit": "Inhaler"},
    {"id": "RESP004", "name": "Ipratropium Bromide Inhalation", "category": "Respiratory", "unit": "Bottle"},
    {"id": "RESP005", "name": "Terbutaline 2.5mg Tablet", "category": "Respiratory", "unit": "Tablet"},
    {"id": "RESP006", "name": "Dextromethorphan Syrup", "category": "Respiratory", "unit": "Bottle"},
    {"id": "RESP007", "name": "Cough Mixture", "category": "Respiratory", "unit": "Bottle"},
    {"id": "RESP008", "name": "Cold Syrup", "category": "Respiratory", "unit": "Bottle"},
    {"id": "GI001", "name": "Oral Rehydration Salts", "category": "GI", "unit": "Sachet"},
    {"id": "GI002", "name": "Loperamide 2mg Capsule", "category": "GI", "unit": "Capsule"},
    {"id": "GI003", "name": "Omeprazole 20mg Capsule", "category": "GI", "unit": "Capsule"},
    {"id": "GI004", "name": "Metoclopramide 10mg Tablet", "category": "GI", "unit": "Tablet"},
    {"id": "GI005", "name": "Domperidone 10mg Tablet", "category": "GI", "unit": "Tablet"},
    {"id": "GI006", "name": "Hyoscine Butylbromide Tablet", "category": "GI", "unit": "Tablet"},
    {"id": "GI007", "name": "Antacid Suspension", "category": "GI", "unit": "Bottle"},
    {"id": "GI008", "name": "Activated Charcoal", "category": "GI", "unit": "Bottle"},
    {"id": "GI009", "name": "Oral Laxative Syrup", "category": "GI", "unit": "Bottle"},
    {"id": "ABX001", "name": "Cephalexin 250mg Capsule", "category": "Antibiotic", "unit": "Capsule"},
    {"id": "ABX002", "name": "Cephalexin Suspension", "category": "Antibiotic", "unit": "Bottle"},
    {"id": "ABX003", "name": "Amoxicillin 250mg Capsule", "category": "Antibiotic", "unit": "Capsule"},
    {"id": "ABX004", "name": "Amoxicillin 500mg Capsule", "category": "Antibiotic", "unit": "Capsule"},
    {"id": "ABX005", "name": "Co-Amoxiclav 625mg Tablet", "category": "Antibiotic", "unit": "Tablet"},
    {"id": "ABX006", "name": "Co-Trimoxazole Suspension", "category": "Antibiotic", "unit": "Bottle"},
    {"id": "ABX007", "name": "Metronidazole 200mg Tablet", "category": "Antibiotic", "unit": "Tablet"},
    {"id": "ABX008", "name": "Doxycycline 100mg Capsule", "category": "Antibiotic", "unit": "Capsule"},
    {"id": "ABX009", "name": "Azithromycin 250mg Tablet", "category": "Antibiotic", "unit": "Tablet"},
    {"id": "ABX010", "name": "Ciprofloxacin 500mg Tablet", "category": "Antibiotic", "unit": "Tablet"},
    {"id": "ABX011", "name": "Phenoxymethyl Penicillin Tablet", "category": "Antibiotic", "unit": "Tablet"},
    {"id": "ABX012", "name": "Erythromycin Suspension", "category": "Antibiotic", "unit": "Bottle"},
    {"id": "CRM001", "name": "Hydrocortisone 1% Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM002", "name": "Calamine Lotion", "category": "Topical", "unit": "Bottle"},
    {"id": "CRM003", "name": "Betamethasone Valerate Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM004", "name": "Miconazole Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM005", "name": "Clotrimazole Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM006", "name": "Fusidic Acid Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM007", "name": "Gentamicin Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM008", "name": "Silver Sulphadiazine Cream", "category": "Topical", "unit": "Tube"},
    {"id": "CRM009", "name": "Aqueous Cream", "category": "Topical", "unit": "Bottle"},
    {"id": "ANTSP001", "name": "Chlorhexidine Gluconate 4% Scrub", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ANTSP002", "name": "Povidone Iodine Solution", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ANTSP003", "name": "Alcohol 70%", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ANTSP004", "name": "Alcohol 96%", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ANTSP005", "name": "Acriflavine Lotion", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ANTSP006", "name": "Hydrogen Peroxide", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ANTSP007", "name": "Chlorhexidine in Alcohol", "category": "Antiseptic", "unit": "Bottle"},
    {"id": "ENT001", "name": "Artificial Tears", "category": "Eye", "unit": "Bottle"},
    {"id": "ENT002", "name": "Chloramphenicol Eye Drops", "category": "Eye", "unit": "Bottle"},
    {"id": "ENT003", "name": "Sodium Chloride Eye Drops", "category": "Eye", "unit": "Bottle"},
    {"id": "ENT004", "name": "Xylometazoline Nasal Drops", "category": "ENT", "unit": "Bottle"},
    {"id": "ENT005", "name": "Normal Saline Irrigation", "category": "ENT", "unit": "Bottle"},
    {"id": "INJ001", "name": "Adrenaline Injection", "category": "Injection", "unit": "Ampoule"},
    {"id": "INJ002", "name": "Hydrocortisone Injection", "category": "Injection", "unit": "Ampoule"},
    {"id": "INJ003", "name": "Normal Saline 0.9% IV", "category": "Injection", "unit": "Bag"},
    {"id": "INJ004", "name": "Dextrose 5% IV", "category": "Injection", "unit": "Bag"},
    {"id": "INJ005", "name": "Atropine Injection", "category": "Injection", "unit": "Ampoule"},
    {"id": "INJ006", "name": "Midazolam Injection", "category": "Injection", "unit": "Ampoule"},
    {"id": "INJ007", "name": "Lidocaine Injection", "category": "Injection", "unit": "Vial"},
    {"id": "INJ008", "name": "Furosemide Injection", "category": "Injection", "unit": "Ampoule"},
    {"id": "MCH001", "name": "Ferrous Fumarate Tablet", "category": "Maternal", "unit": "Tablet"},
    {"id": "MCH002", "name": "Folic Acid Tablet", "category": "Maternal", "unit": "Tablet"},
    {"id": "MCH003", "name": "Iron Syrup", "category": "Maternal", "unit": "Bottle"},
    {"id": "MCH004", "name": "Vitamin Drops Infant", "category": "Maternal", "unit": "Bottle"},
    {"id": "MCH005", "name": "Zinc Tablet", "category": "Maternal", "unit": "Tablet"},
    {"id": "CHR001", "name": "Gliclazide 80mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "CHR002", "name": "Metformin 500mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "CHR003", "name": "Metformin XR 500mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "CHR004", "name": "Simvastatin 20mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "CHR005", "name": "Simvastatin 40mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "CHR006", "name": "Atenolol 100mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "CHR007", "name": "Metoprolol 100mg Tablet", "category": "Chronic", "unit": "Tablet"},
    {"id": "WND001", "name": "Gauze Swab", "category": "Wound Care", "unit": "Pack"},
    {"id": "WND002", "name": "Cotton Balls", "category": "Wound Care", "unit": "Pack"},
    {"id": "WND003", "name": "Adhesive Plaster", "category": "Wound Care", "unit": "Roll"},
    {"id": "WND004", "name": "Bandage Roll", "category": "Wound Care", "unit": "Roll"},
    {"id": "WND005", "name": "Crepe Bandage", "category": "Wound Care", "unit": "Roll"},
    {"id": "WND006", "name": "Surgical Tape", "category": "Wound Care", "unit": "Roll"},
    {"id": "WND007", "name": "Sterile Dressing Set", "category": "Wound Care", "unit": "Pack"},
    {"id": "SUP001", "name": "Syringe 1ml", "category": "Supply", "unit": "Unit"},
    {"id": "SUP002", "name": "Syringe 3ml", "category": "Supply", "unit": "Unit"},
    {"id": "SUP003", "name": "Syringe 5ml", "category": "Supply", "unit": "Unit"},
    {"id": "SUP004", "name": "Needle", "category": "Supply", "unit": "Unit"},
    {"id": "SUP005", "name": "Gloves Latex", "category": "Supply", "unit": "Box"},
    {"id": "SUP006", "name": "Gloves Non Latex", "category": "Supply", "unit": "Box"},
    {"id": "SUP007", "name": "Face Mask", "category": "Supply", "unit": "Box"},
    {"id": "SUP008", "name": "Thermometer", "category": "Supply", "unit": "Unit"},
    {"id": "VIT001", "name": "Vitamin B Complex Tablet", "category": "Vitamin", "unit": "Tablet"},
    {"id": "VIT002", "name": "Calcium Carbonate Tablet", "category": "Vitamin", "unit": "Tablet"},
    {"id": "VIT003", "name": "Calcium Lactate Tablet", "category": "Vitamin", "unit": "Tablet"},
    {"id": "ADD001", "name": "Prednisolone 5mg Tablet", "category": "Steroid", "unit": "Tablet"},
    {"id": "ADD002", "name": "Triamcinolone 4mg Tablet", "category": "Steroid", "unit": "Tablet"},
    {"id": "ADD003", "name": "Diazepam 5mg Tablet", "category": "Sedative", "unit": "Tablet"},
    {"id": "ADD004", "name": "Diazepam 10mg Tablet", "category": "Sedative", "unit": "Tablet"},
    {"id": "ADD005", "name": "ORS Citrate", "category": "GI", "unit": "Sachet"},
    {"id": "ADD006", "name": "ORS Bicarbonate", "category": "GI", "unit": "Sachet"},
]

CUSTOM_ALIASES = {
    "PCM001": ["Paracetamol", "PCM"],
    "PCM002": ["Paracetamol Syrup", "PCM Syrup"],
    "IBU001": ["Ibuprofen"],
    "MEF001": ["Mefenamic Acid"],
    "NAP001": ["Naproxen"],
    "ANT001": ["Chlorpheniramine", "CPM"],
    "ANT002": ["Cetirizine"],
    "ANT003": ["Cetirizine Syrup"],
    "ANT004": ["Loratadine"],
    "ANT005": ["Diphenhydramine"],
    "RESP001": ["Salbutamol", "Albuterol", "Salbutamol Tablet", "Albuterol Tablet"],
    "RESP002": ["Salbutamol Syrup", "Albuterol Syrup"],
    "RESP003": ["Salbutamol Inhaler", "Albuterol Inhaler", "Ventolin Inhaler"],
    "GI001": ["ORS", "Oral Rehydration Salts"],
    "GI003": ["Omeprazole"],
    "ABX001": ["Cephalexin"],
    "ABX002": ["Cephalexin Suspension", "Cephalexin Syrup"],
    "ABX003": ["Amoxicillin"],
    "CHR002": ["Metformin"],
    "CHR004": ["Simvastatin"],
    "ADD005": ["ORS Citrate"],
    "ADD006": ["ORS Bicarbonate"],
}

FORM_WORDS = {
    "tablet",
    "capsule",
    "syrup",
    "bottle",
    "tube",
    "cream",
    "solution",
    "sachet",
    "ampoule",
    "bag",
    "vial",
    "pack",
    "roll",
    "unit",
    "inhaler",
    "drops",
    "drop",
    "lotion",
    "suspension",
    "iv",
    "scrub",
}


def normalize_text(value):
    if value is None:
        return ""

    value = str(value).strip().lower()
    value = value.replace("&", "and")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return " ".join(value.split())


def remove_strength_tokens(value):
    cleaned = re.sub(r"\b\d+(\.\d+)?\s*(mg|mcg|g|ml|%)(/\d+ml)?\b", " ", value, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b\d+(\.\d+)?\b", " ", cleaned)
    return " ".join(cleaned.split())


def build_aliases(medicine):
    alias_set = set(CUSTOM_ALIASES.get(medicine["id"], []))
    alias_set.add(medicine["name"])

    simplified_name = remove_strength_tokens(medicine["name"])
    alias_set.add(simplified_name)

    normalized_tokens = [
        token for token in normalize_text(simplified_name).split()
        if token not in FORM_WORDS
    ]
    if normalized_tokens:
        alias_set.add(" ".join(normalized_tokens))
        alias_set.add(normalized_tokens[0])

    ordered_aliases = []
    seen = set()

    for alias in alias_set:
        cleaned = " ".join(str(alias).strip().split())
        if not cleaned:
            continue
        normalized = normalize_text(cleaned)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        ordered_aliases.append(cleaned)

    ordered_aliases.sort(key=lambda alias: (len(normalize_text(alias)), alias.lower()))
    return ordered_aliases


def build_medicine_document(medicine):
    return {
        "medicine_id": medicine["id"],
        "name": medicine["name"],
        "category": medicine["category"],
        "product_code": medicine.get("product_code", medicine["id"]),
        "unit": medicine["unit"],
        "aliases": build_aliases(medicine),
        "standard_min_qty": DEFAULT_MIN_QTY,
    }


def get_baseline_medicines():
    return [build_medicine_document(medicine) for medicine in MEDICINES]


def list_medicines():
    docs = list(db.collection("medicines").stream())

    if not docs:
        return get_baseline_medicines()

    medicines = []
    for doc in docs:
        data = doc.to_dict()
        if "medicine_id" not in data:
            data["medicine_id"] = doc.id
        medicines.append(data)

    medicines.sort(key=lambda medicine: medicine["medicine_id"])
    return medicines


def seed_medicines(batch_size=400):
    medicines = get_baseline_medicines()
    batch = db.batch()
    operation_count = 0

    for index, medicine in enumerate(medicines, start=1):
        doc_ref = db.collection("medicines").document(medicine["medicine_id"])
        batch.set(doc_ref, medicine, merge=True)
        operation_count += 1

        if operation_count >= batch_size:
            batch.commit()
            print(f"Seeded {index} medicine SKUs...")
            batch = db.batch()
            operation_count = 0

    if operation_count:
        batch.commit()

    print(f"Medicine seeding complete. Total SKUs available: {len(medicines)}")
    return medicines


def build_match_index(medicines):
    match_index = {}

    for medicine in medicines:
        values = [medicine["name"], *medicine.get("aliases", [])]

        for value in values:
            normalized = normalize_text(value)
            if normalized and normalized not in match_index:
                match_index[normalized] = medicine

    return match_index


def match_medicine(item_name, medicines=None, match_index=None):
    if not item_name:
        return None

    medicines = medicines or list_medicines()
    match_index = match_index or build_match_index(medicines)
    normalized_item = normalize_text(item_name)

    if not normalized_item:
        return None

    if normalized_item in match_index:
        return match_index[normalized_item]

    best_match = None
    best_score = -1

    for medicine in medicines:
        candidates = [medicine["name"], *medicine.get("aliases", [])]

        for candidate in candidates:
            normalized_candidate = normalize_text(candidate)
            if not normalized_candidate:
                continue

            if normalized_item in normalized_candidate or normalized_candidate in normalized_item:
                score = min(len(normalized_item), len(normalized_candidate))
                if score > best_score:
                    best_score = score
                    best_match = medicine

    return best_match


def commit_batch(batch, operation_count, progress_message=None):
    if operation_count == 0:
        return db.batch(), 0

    batch.commit()
    if progress_message:
        print(progress_message)
    return db.batch(), 0


def migrate_inventory(batch_size=400):
    medicines = seed_medicines()
    match_index = build_match_index(medicines)
    inventory_docs = list(db.collection("inventory").stream())
    batch = db.batch()
    operation_count = 0
    migrated_count = 0
    skipped_count = 0
    unmatched_items = []

    for index, doc in enumerate(inventory_docs, start=1):
        data = doc.to_dict()
        item_name = data.get("item_name")

        if data.get("medicine_id"):
            skipped_count += 1
            continue

        medicine = match_medicine(item_name, medicines=medicines, match_index=match_index)

        if medicine is None:
            unmatched_items.append({
                "document_id": doc.id,
                "clinic_id": data.get("clinic_id"),
                "item_name": item_name,
            })
            continue

        batch.update(doc.reference, {"medicine_id": medicine["medicine_id"]})
        operation_count += 1
        migrated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=(
                    f"Migrated {migrated_count}/{len(inventory_docs)} inventory documents..."
                ),
            )

        if index % 100 == 0:
            print(
                f"Processed {index}/{len(inventory_docs)} inventory documents "
                f"(matched: {migrated_count}, unmatched: {len(unmatched_items)})"
            )

    batch, _ = commit_batch(
        batch,
        operation_count,
        progress_message=f"Final migration commit complete. Updated {migrated_count} documents.",
    )

    print(
        f"Inventory migration finished. "
        f"Migrated: {migrated_count}, already linked: {skipped_count}, unmatched: {len(unmatched_items)}"
    )

    log_unmatched_items(unmatched_items)
    return unmatched_items


def log_unmatched_items(unmatched_items):
    if not unmatched_items:
        print("No unmatched inventory items found.")

        if UNMATCHED_LOG_PATH.exists():
            UNMATCHED_LOG_PATH.unlink()

        return

    UNMATCHED_LOG_PATH.write_text(
        json.dumps(unmatched_items, indent=2),
        encoding="utf-8",
    )

    print("Unmatched inventory items:")
    for item in unmatched_items:
        print(
            f"- clinic_id={item.get('clinic_id')} | "
            f"item_name={item.get('item_name')} | document_id={item.get('document_id')}"
        )

    print(f"Saved unmatched item report to {UNMATCHED_LOG_PATH}")


def initialize_clinic_inventory(clinic_id, batch_size=400):
    if not clinic_id:
        raise ValueError("clinic_id is required")

    medicines = seed_medicines()
    match_index = build_match_index(medicines)
    medicine_map = {medicine["medicine_id"]: medicine for medicine in medicines}
    existing_docs = list(
        db.collection("inventory")
        .where("clinic_id", "==", clinic_id)
        .stream()
    )

    existing_medicine_ids = set()
    batch = db.batch()
    operation_count = 0

    for doc in existing_docs:
        data = doc.to_dict()
        medicine_id = data.get("medicine_id")

        if medicine_id:
            existing_medicine_ids.add(medicine_id)
            medicine = medicine_map.get(medicine_id, {})
            batch.update(
                doc.reference,
                {
                    "clinic_id": data.get("clinic_id", clinic_id),
                    "item_name": medicine.get("name", data.get("item_name")),
                    "category": medicine.get("category", data.get("category", "")),
                    "product_code": medicine.get(
                        "product_code",
                        data.get("product_code", medicine_id),
                    ),
                    "unit": medicine.get("unit", data.get("unit", "")),
                    "min_order_qty": data.get(
                        "min_order_qty",
                        medicine.get("standard_min_qty", DEFAULT_MIN_QTY),
                    ),
                    "last_updated": data.get("last_updated", firestore.SERVER_TIMESTAMP),
                },
            )
            operation_count += 1
            if operation_count >= batch_size:
                batch, operation_count = commit_batch(
                    batch,
                    operation_count,
                    progress_message=(
                        f"Updated existing inventory schema for clinic {clinic_id}..."
                    ),
                )
            continue

        medicine = match_medicine(
            data.get("item_name"),
            medicines=medicines,
            match_index=match_index,
        )
        if medicine is None:
            continue

        batch.update(
            doc.reference,
            {
                "clinic_id": data.get("clinic_id", clinic_id),
                "medicine_id": medicine["medicine_id"],
                "item_name": medicine["name"],
                "category": medicine.get("category", ""),
                "product_code": medicine.get("product_code", medicine["medicine_id"]),
                "unit": medicine.get("unit", ""),
                "min_order_qty": data.get(
                    "min_order_qty",
                    medicine.get("standard_min_qty", DEFAULT_MIN_QTY),
                ),
                "last_updated": data.get("last_updated", firestore.SERVER_TIMESTAMP),
            },
        )
        operation_count += 1
        existing_medicine_ids.add(medicine["medicine_id"])

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=(
                    f"Linked existing inventory rows for clinic {clinic_id}..."
                ),
            )

    created_count = 0

    for medicine_id, medicine in medicine_map.items():
        if medicine_id in existing_medicine_ids:
            continue

        doc_ref = db.collection("inventory").document()
        batch.set(
            doc_ref,
            {
                "clinic_id": clinic_id,
                "medicine_id": medicine_id,
                "item_name": medicine["name"],
                "category": medicine.get("category", ""),
                "product_code": medicine.get("product_code", medicine_id),
                "unit": medicine.get("unit", ""),
                "current_stock": 0,
                "min_order_qty": medicine.get("standard_min_qty", DEFAULT_MIN_QTY),
                "last_updated": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        operation_count += 1
        created_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=(
                    f"Created {created_count} inventory rows for clinic {clinic_id}..."
                ),
            )

    commit_batch(
        batch,
        operation_count,
        progress_message=(
            f"Clinic inventory initialization complete for {clinic_id}. "
            f"New rows created: {created_count}"
        ),
    )

    return {
        "clinic_id": clinic_id,
        "created_count": created_count,
        "total_medicines": len(medicines),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Seed medicine SKUs and migrate clinic inventory to medicine_id-based records.",
    )
    parser.add_argument(
        "--init-clinic",
        dest="init_clinic",
        help="Initialize full inventory rows for a clinic using the medicines catalog.",
    )
    parser.add_argument(
        "--seed-only",
        action="store_true",
        help="Seed the medicines collection without migrating inventory.",
    )
    args = parser.parse_args()

    if args.init_clinic:
        result = initialize_clinic_inventory(args.init_clinic)
        print(
            f"Initialized inventory for {result['clinic_id']} "
            f"with {result['created_count']} new medicine rows."
        )
        return

    if args.seed_only:
        seed_medicines()
        return

    migrate_inventory()


if __name__ == "__main__":
    main()
