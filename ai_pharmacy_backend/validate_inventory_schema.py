from collections import defaultdict

from firebase_config import db
from normalize_inventory_schema import (
    INVENTORY_REQUIRED_FIELDS,
    load_clinics,
    load_medicines,
)
from migrate_inventory import match_medicine


USAGE_REQUIRED_FIELDS = [
    "clinic_id",
    "medicine_id",
    "item_name",
    "quantity_used",
    "timestamp",
]

STOCK_IN_REQUIRED_FIELDS = [
    "clinic_id",
    "medicine_id",
    "item_name",
    "quantity_received",
    "timestamp",
]


def validate_inventory():
    clinics = load_clinics()
    medicines, medicine_lookup, aliases_lookup = load_medicines()
    baseline_ids = {medicine["medicine_id"] for medicine in medicines}

    print(f"Clinics: {len(clinics)}")
    print(f"Medicines: {len(medicines)}")

    missing_fields_report = []
    unresolved_inventory = []

    for clinic in clinics:
        clinic_id = clinic["clinic_id"]
        docs = list(
            db.collection("inventory")
            .where("clinic_id", "==", clinic_id)
            .stream()
        )

        seen_medicine_ids = set()

        for doc in docs:
            data = doc.to_dict()
            medicine_id = data.get("medicine_id")

            if medicine_id:
                seen_medicine_ids.add(medicine_id)
            else:
                matched = match_medicine(
                    data.get("item_name"),
                    medicines=medicines,
                    match_index=aliases_lookup,
                )
                if matched:
                    seen_medicine_ids.add(matched["medicine_id"])
                else:
                    unresolved_inventory.append({
                        "clinic_id": clinic_id,
                        "document_id": doc.id,
                        "item_name": data.get("item_name"),
                    })

            missing_fields = [
                field for field in INVENTORY_REQUIRED_FIELDS
                if field not in data or data.get(field) is None
            ]
            if missing_fields:
                missing_fields_report.append({
                    "clinic_id": clinic_id,
                    "document_id": doc.id,
                    "missing_fields": missing_fields,
                })

        missing_medicine_ids = baseline_ids - seen_medicine_ids
        if not missing_medicine_ids:
            print(f"[OK] {clinic_id} -> {len(seen_medicine_ids)} medicines")
        else:
            print(
                f"[MISSING] {clinic_id} missing {len(missing_medicine_ids)} medicines"
            )

    return missing_fields_report, unresolved_inventory


def validate_usage_logs():
    medicines, _, aliases_lookup = load_medicines()
    unresolved = []
    missing_fields = []

    for doc in db.collection("usage_logs").stream():
        data = doc.to_dict()
        required_missing = [
            field for field in USAGE_REQUIRED_FIELDS
            if field not in data or data.get(field) is None
        ]
        if required_missing:
            missing_fields.append({
                "document_id": doc.id,
                "missing_fields": required_missing,
            })

        if data.get("medicine_id"):
            continue

        matched = match_medicine(
            data.get("item_name"),
            medicines=medicines,
            match_index=aliases_lookup,
        )
        if not matched:
            unresolved.append(data.get("item_name"))

    return missing_fields, sorted(set(unresolved))


def validate_stock_in_logs():
    medicines, _, aliases_lookup = load_medicines()
    unresolved = []
    missing_fields = []

    for doc in db.collection("stock_in_logs").stream():
        data = doc.to_dict()
        required_missing = [
            field for field in STOCK_IN_REQUIRED_FIELDS
            if field not in data or data.get(field) is None
        ]
        if required_missing:
            missing_fields.append({
                "document_id": doc.id,
                "missing_fields": required_missing,
            })

        if data.get("medicine_id"):
            continue

        matched = match_medicine(
            data.get("item_name"),
            medicines=medicines,
            match_index=aliases_lookup,
        )
        if not matched:
            unresolved.append(data.get("item_name"))

    return missing_fields, sorted(set(unresolved))


def print_missing_fields(title, items):
    if not items:
        print(f"[OK] {title}: no missing fields")
        return

    print(f"[WARNING] {title}: {len(items)} documents missing fields")
    for item in items[:20]:
        print(f"- {item}")


def main():
    inventory_missing_fields, unresolved_inventory = validate_inventory()
    usage_missing_fields, unresolved_usage = validate_usage_logs()
    stock_missing_fields, unresolved_stock = validate_stock_in_logs()

    print_missing_fields("inventory", inventory_missing_fields)
    print_missing_fields("usage_logs", usage_missing_fields)
    print_missing_fields("stock_in_logs", stock_missing_fields)

    for item_name in unresolved_inventory[:20]:
        print(
            f"[WARNING] unresolved inventory item: "
            f"{item_name['clinic_id']} -> {item_name['item_name']}"
        )

    for item_name in unresolved_usage[:20]:
        print(f"[WARNING] unresolved usage_logs item: \"{item_name}\"")

    for item_name in unresolved_stock[:20]:
        print(f"[WARNING] unresolved stock_in_logs item: \"{item_name}\"")

    print("Schema summary:")
    print(f"- inventory missing-field docs: {len(inventory_missing_fields)}")
    print(f"- inventory unresolved mappings: {len(unresolved_inventory)}")
    print(f"- usage_logs missing-field docs: {len(usage_missing_fields)}")
    print(f"- usage_logs unresolved mappings: {len(unresolved_usage)}")
    print(f"- stock_in_logs missing-field docs: {len(stock_missing_fields)}")
    print(f"- stock_in_logs unresolved mappings: {len(unresolved_stock)}")


if __name__ == "__main__":
    main()
