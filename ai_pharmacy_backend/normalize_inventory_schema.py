from collections import defaultdict

from firebase_admin import firestore

from firebase_config import db
from migrate_inventory import (
    build_match_index,
    commit_batch,
    list_medicines,
    match_medicine,
)


INVENTORY_REQUIRED_FIELDS = [
    "clinic_id",
    "medicine_id",
    "item_name",
    "category",
    "product_code",
    "unit",
    "current_stock",
    "min_order_qty",
    "last_updated",
]


def load_clinics():
    clinics = []
    for doc in db.collection("clinics").stream():
        data = doc.to_dict()
        clinics.append({
            "clinic_id": doc.id,
            "name": data.get("name", doc.id),
        })
    clinics.sort(key=lambda clinic: clinic["clinic_id"])
    return clinics


def load_medicines():
    medicines = list_medicines()
    medicines.sort(key=lambda medicine: medicine["medicine_id"])
    medicine_lookup = {
        medicine["medicine_id"]: medicine
        for medicine in medicines
        if medicine.get("medicine_id")
    }
    aliases_lookup = build_match_index(medicines)
    return medicines, medicine_lookup, aliases_lookup


def _normalize_product_code(medicine):
    return medicine.get("product_code", medicine.get("medicine_id", ""))


def _full_inventory_payload(clinic_id, medicine, current_stock=0, existing_data=None):
    existing_data = existing_data or {}

    return {
        "clinic_id": existing_data.get("clinic_id", clinic_id),
        "medicine_id": medicine["medicine_id"],
        "item_name": medicine["name"],
        "category": medicine.get("category", existing_data.get("category", "")),
        "product_code": medicine.get(
            "product_code",
            existing_data.get("product_code", _normalize_product_code(medicine)),
        ),
        "unit": medicine.get("unit", existing_data.get("unit", "")),
        "current_stock": existing_data.get("current_stock", current_stock),
        "min_order_qty": existing_data.get(
            "min_order_qty",
            medicine.get("standard_min_qty", 100),
        ),
        "last_updated": existing_data.get("last_updated", firestore.SERVER_TIMESTAMP),
    }


def _resolve_inventory_medicine(data, medicines, aliases_lookup, medicine_lookup):
    medicine_id = data.get("medicine_id")
    if medicine_id and medicine_id in medicine_lookup:
        return medicine_lookup[medicine_id]

    return match_medicine(
        data.get("item_name"),
        medicines=medicines,
        match_index=aliases_lookup,
    )


def normalize_inventory_schema(batch_size=400):
    clinics = load_clinics()
    medicines, medicine_lookup, aliases_lookup = load_medicines()
    total_medicines = len(medicines)

    batch = db.batch()
    operation_count = 0
    created_count = 0
    updated_count = 0
    unresolved_items = []
    duplicate_medicines = defaultdict(list)

    for clinic in clinics:
        clinic_id = clinic["clinic_id"]
        clinic_inventory_docs = list(
            db.collection("inventory")
            .where("clinic_id", "==", clinic_id)
            .stream()
        )

        existing_by_medicine = {}

        for doc in clinic_inventory_docs:
            data = doc.to_dict()
            medicine = _resolve_inventory_medicine(
                data,
                medicines,
                aliases_lookup,
                medicine_lookup,
            )

            if medicine is None:
                unresolved_items.append({
                    "clinic_id": clinic_id,
                    "document_id": doc.id,
                    "item_name": data.get("item_name"),
                })
                continue

            medicine_id = medicine["medicine_id"]

            if medicine_id in existing_by_medicine:
                duplicate_medicines[clinic_id].append(medicine_id)
                continue

            existing_by_medicine[medicine_id] = doc
            payload = _full_inventory_payload(
                clinic_id,
                medicine,
                current_stock=data.get("current_stock", 0),
                existing_data=data,
            )
            batch.set(doc.reference, payload, merge=True)
            operation_count += 1
            updated_count += 1

            if operation_count >= batch_size:
                batch, operation_count = commit_batch(
                    batch,
                    operation_count,
                    progress_message=(
                        f"Inventory normalization progress: updated={updated_count}, "
                        f"created={created_count}"
                    ),
                )

        for medicine in medicines:
            medicine_id = medicine["medicine_id"]
            if medicine_id in existing_by_medicine:
                continue

            doc_ref = db.collection("inventory").document()
            payload = _full_inventory_payload(clinic_id, medicine, current_stock=0)
            batch.set(doc_ref, payload, merge=True)
            operation_count += 1
            created_count += 1

            if operation_count >= batch_size:
                batch, operation_count = commit_batch(
                    batch,
                    operation_count,
                    progress_message=(
                        f"Inventory normalization progress: updated={updated_count}, "
                        f"created={created_count}"
                    ),
                )

        print(
            f"[CLINIC] {clinic_id} -> normalized {len(existing_by_medicine)}/{total_medicines} "
            f"existing mappings"
        )

    commit_batch(
        batch,
        operation_count,
        progress_message=(
            f"Inventory normalization complete. Updated={updated_count}, created={created_count}"
        ),
    )

    if unresolved_items:
        print("Unresolved inventory matches:")
        for item in unresolved_items:
            print(
                f"- clinic_id={item['clinic_id']} "
                f"document_id={item['document_id']} item_name={item['item_name']}"
            )

    if duplicate_medicines:
        print("Duplicate medicine mappings detected (not deleted):")
        for clinic_id, medicine_ids in duplicate_medicines.items():
            unique_ids = sorted(set(medicine_ids))
            print(f"- {clinic_id}: {', '.join(unique_ids)}")

    return {
        "created_count": created_count,
        "updated_count": updated_count,
        "unresolved_items": unresolved_items,
        "duplicate_medicines": {key: sorted(set(value)) for key, value in duplicate_medicines.items()},
    }


def normalize_usage_logs(batch_size=400):
    medicines, medicine_lookup, aliases_lookup = load_medicines()
    docs = list(db.collection("usage_logs").stream())
    batch = db.batch()
    operation_count = 0
    updated_count = 0
    unresolved = []

    for index, doc in enumerate(docs, start=1):
        data = doc.to_dict()
        medicine = _resolve_inventory_medicine(
            data,
            medicines,
            aliases_lookup,
            medicine_lookup,
        )

        if medicine is None:
            unresolved.append({
                "document_id": doc.id,
                "clinic_id": data.get("clinic_id"),
                "item_name": data.get("item_name"),
            })
            continue

        quantity_used = data.get("quantity_used", data.get("qty_used", 0))
        batch.set(
            doc.reference,
            {
                "clinic_id": data.get("clinic_id"),
                "medicine_id": medicine["medicine_id"],
                "item_name": medicine["name"],
                "quantity_used": quantity_used,
                "timestamp": data.get("timestamp", firestore.SERVER_TIMESTAMP),
            },
            merge=True,
        )
        operation_count += 1
        updated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=f"Usage logs normalized: {updated_count}/{len(docs)}",
            )

        if index % 500 == 0:
            print(f"Processed usage_logs {index}/{len(docs)}")

    commit_batch(
        batch,
        operation_count,
        progress_message=f"Usage logs normalization complete. Updated {updated_count}",
    )

    if unresolved:
        print("Unresolved usage_logs matches:")
        for item in unresolved:
            print(
                f"- clinic_id={item['clinic_id']} "
                f"document_id={item['document_id']} item_name={item['item_name']}"
            )

    return {"updated_count": updated_count, "unresolved": unresolved}


def normalize_stock_in_logs(batch_size=400):
    medicines, medicine_lookup, aliases_lookup = load_medicines()
    docs = list(db.collection("stock_in_logs").stream())
    batch = db.batch()
    operation_count = 0
    updated_count = 0
    unresolved = []

    for index, doc in enumerate(docs, start=1):
        data = doc.to_dict()
        medicine = _resolve_inventory_medicine(
            data,
            medicines,
            aliases_lookup,
            medicine_lookup,
        )

        if medicine is None:
            unresolved.append({
                "document_id": doc.id,
                "clinic_id": data.get("clinic_id"),
                "item_name": data.get("item_name"),
            })
            continue

        quantity_received = data.get(
            "quantity_received",
            data.get("qty_received", data.get("qty_added", data.get("quantity_added", 0))),
        )

        batch.set(
            doc.reference,
            {
                "clinic_id": data.get("clinic_id"),
                "medicine_id": medicine["medicine_id"],
                "item_name": medicine["name"],
                "quantity_received": quantity_received,
                "timestamp": data.get("timestamp", firestore.SERVER_TIMESTAMP),
            },
            merge=True,
        )
        operation_count += 1
        updated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=f"Stock-in logs normalized: {updated_count}/{len(docs)}",
            )

        if index % 500 == 0:
            print(f"Processed stock_in_logs {index}/{len(docs)}")

    commit_batch(
        batch,
        operation_count,
        progress_message=f"Stock-in logs normalization complete. Updated {updated_count}",
    )

    if unresolved:
        print("Unresolved stock_in_logs matches:")
        for item in unresolved:
            print(
                f"- clinic_id={item['clinic_id']} "
                f"document_id={item['document_id']} item_name={item['item_name']}"
            )

    return {"updated_count": updated_count, "unresolved": unresolved}


def main():
    inventory_result = normalize_inventory_schema()
    usage_result = normalize_usage_logs()
    stock_in_result = normalize_stock_in_logs()

    print("Normalization summary:")
    print(
        f"- inventory updated={inventory_result['updated_count']} "
        f"created={inventory_result['created_count']}"
    )
    print(f"- usage_logs updated={usage_result['updated_count']}")
    print(f"- stock_in_logs updated={stock_in_result['updated_count']}")


if __name__ == "__main__":
    main()
