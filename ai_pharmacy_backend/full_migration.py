import argparse
import json
from datetime import datetime
from pathlib import Path

from firebase_config import db
from migrate_inventory import (
    build_match_index,
    commit_batch,
    initialize_clinic_inventory as base_initialize_clinic_inventory,
    list_medicines,
    log_unmatched_items,
    match_medicine,
    seed_medicines,
)


REPORT_PATH = Path(__file__).with_name("migration_report.json")


def load_medicines():
    medicines = seed_medicines()
    aliases_lookup = build_match_index(medicines)
    medicine_lookup = {
        medicine["medicine_id"]: medicine
        for medicine in medicines
    }
    return medicine_lookup, aliases_lookup


def get_medicine_by_alias(detected_text):
    medicine_lookup, aliases_lookup = load_medicines()
    medicine = match_medicine(
        detected_text,
        medicines=list(medicine_lookup.values()),
        match_index=aliases_lookup,
    )
    if not medicine:
        return None

    return {
        "medicine_id": medicine["medicine_id"],
        "name": medicine["name"],
    }


def initialize_clinic_inventory(clinic_id):
    return base_initialize_clinic_inventory(clinic_id)


def _resolve_medicine(data, medicine_lookup, aliases_lookup):
    medicine_id = data.get("medicine_id")
    if medicine_id and medicine_id in medicine_lookup:
        return medicine_lookup[medicine_id]

    item_name = data.get("item_name")
    return match_medicine(
        item_name,
        medicines=list(medicine_lookup.values()),
        match_index=aliases_lookup,
    )


def migrate_inventory(medicine_lookup, aliases_lookup, batch_size=400):
    docs = list(db.collection("inventory").stream())
    batch = db.batch()
    operation_count = 0
    migrated_count = 0
    unmatched = []

    for index, doc in enumerate(docs, start=1):
        data = doc.to_dict()
        medicine = _resolve_medicine(data, medicine_lookup, aliases_lookup)

        if not medicine:
            unmatched.append({
                "document_id": doc.id,
                "clinic_id": data.get("clinic_id"),
                "item_name": data.get("item_name"),
            })
            continue

        update_data = {
            "medicine_id": medicine["medicine_id"],
            "item_name": medicine["name"],
            "last_updated": datetime.utcnow(),
        }
        batch.update(doc.reference, update_data)
        operation_count += 1
        migrated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=f"Inventory migration progress: {migrated_count}/{len(docs)}",
            )

        if index % 100 == 0:
            print(
                f"Inventory processed {index}/{len(docs)} "
                f"(migrated={migrated_count}, unmatched={len(unmatched)})"
            )

    commit_batch(
        batch,
        operation_count,
        progress_message=f"Inventory migration complete. Migrated {migrated_count} records.",
    )
    return migrated_count, unmatched


def migrate_usage_logs(medicine_lookup, aliases_lookup, batch_size=400):
    docs = list(db.collection("usage_logs").stream())
    batch = db.batch()
    operation_count = 0
    migrated_count = 0
    unmatched = []

    for index, doc in enumerate(docs, start=1):
        data = doc.to_dict()
        medicine = _resolve_medicine(data, medicine_lookup, aliases_lookup)

        if not medicine:
            unmatched.append({
                "document_id": doc.id,
                "clinic_id": data.get("clinic_id"),
                "item_name": data.get("item_name"),
            })
            continue

        update_data = {
            "medicine_id": medicine["medicine_id"],
            "item_name": medicine["name"],
        }
        batch.update(doc.reference, update_data)
        operation_count += 1
        migrated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=f"Usage log migration progress: {migrated_count}/{len(docs)}",
            )

        if index % 200 == 0:
            print(
                f"Usage logs processed {index}/{len(docs)} "
                f"(migrated={migrated_count}, unmatched={len(unmatched)})"
            )

    commit_batch(
        batch,
        operation_count,
        progress_message=f"Usage log migration complete. Migrated {migrated_count} records.",
    )
    return migrated_count, unmatched


def migrate_stock_in_logs(medicine_lookup, aliases_lookup, batch_size=400):
    docs = list(db.collection("stock_in_logs").stream())
    batch = db.batch()
    operation_count = 0
    migrated_count = 0
    unmatched = []

    for index, doc in enumerate(docs, start=1):
        data = doc.to_dict()
        medicine = _resolve_medicine(data, medicine_lookup, aliases_lookup)

        if not medicine:
            unmatched.append({
                "document_id": doc.id,
                "clinic_id": data.get("clinic_id"),
                "item_name": data.get("item_name"),
            })
            continue

        quantity_received = data.get("qty_received")
        if quantity_received is None:
            quantity_received = data.get("qty_added", data.get("quantity_added"))

        update_data = {
            "medicine_id": medicine["medicine_id"],
            "item_name": medicine["name"],
        }

        if quantity_received is not None:
            update_data["qty_received"] = quantity_received

        batch.update(doc.reference, update_data)
        operation_count += 1
        migrated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=f"Stock-in log migration progress: {migrated_count}/{len(docs)}",
            )

        if index % 200 == 0:
            print(
                f"Stock-in logs processed {index}/{len(docs)} "
                f"(migrated={migrated_count}, unmatched={len(unmatched)})"
            )

    commit_batch(
        batch,
        operation_count,
        progress_message=f"Stock-in log migration complete. Migrated {migrated_count} records.",
    )
    return migrated_count, unmatched


def migrate_orders(medicine_lookup, aliases_lookup, batch_size=200):
    docs = list(db.collection("orders").stream())
    batch = db.batch()
    operation_count = 0
    migrated_count = 0
    unmatched = []

    for doc in docs:
        data = doc.to_dict()
        items = data.get("items", [])
        updated_items = []
        changed = False

        for item in items:
            medicine = _resolve_medicine(item, medicine_lookup, aliases_lookup)
            if not medicine:
                unmatched.append({
                    "document_id": doc.id,
                    "clinic_id": data.get("clinic_id"),
                    "item_name": item.get("item_name"),
                })
                updated_items.append(item)
                continue

            quantity = item.get("qty")
            if quantity is None:
                quantity = item.get("suggested_qty", item.get("quantity", 0))

            updated_item = dict(item)
            updated_item.update({
                "medicine_id": medicine["medicine_id"],
                "item_name": medicine["name"],
                "qty": quantity,
                "suggested_qty": item.get("suggested_qty", quantity),
            })
            updated_items.append(updated_item)
            changed = True

        if not changed:
            continue

        batch.update(doc.reference, {"items": updated_items})
        operation_count += 1
        migrated_count += 1

        if operation_count >= batch_size:
            batch, operation_count = commit_batch(
                batch,
                operation_count,
                progress_message=f"Order migration progress: {migrated_count}/{len(docs)}",
            )

    commit_batch(
        batch,
        operation_count,
        progress_message=f"Order migration complete. Migrated {migrated_count} records.",
    )
    return migrated_count, unmatched


def write_migration_report(report):
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Migration report saved to {REPORT_PATH}")


def run_full_migration():
    medicine_lookup, aliases_lookup = load_medicines()

    inventory_migrated, unmatched_inventory = migrate_inventory(
        medicine_lookup,
        aliases_lookup,
    )
    usage_migrated, unmatched_usage = migrate_usage_logs(
        medicine_lookup,
        aliases_lookup,
    )
    stock_in_migrated, unmatched_stock = migrate_stock_in_logs(
        medicine_lookup,
        aliases_lookup,
    )
    orders_migrated, unmatched_orders = migrate_orders(
        medicine_lookup,
        aliases_lookup,
    )

    report = {
        "summary": {
            "inventory_migrated": inventory_migrated,
            "usage_logs_migrated": usage_migrated,
            "stock_in_logs_migrated": stock_in_migrated,
            "orders_migrated": orders_migrated,
        },
        "unmatched_inventory_items": unmatched_inventory,
        "unmatched_usage_logs": unmatched_usage,
        "unmatched_stock_in_logs": unmatched_stock,
        "unmatched_order_items": unmatched_orders,
    }

    write_migration_report(report)
    log_unmatched_items(
        unmatched_inventory + unmatched_usage + unmatched_stock + unmatched_orders
    )
    print("Full migration completed.")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run full Firestore migration to medicine_id-based architecture.",
    )
    parser.add_argument(
        "--init-clinic",
        dest="init_clinic",
        help="Initialize all medicine inventory rows for a new clinic.",
    )
    args = parser.parse_args()

    if args.init_clinic:
        result = initialize_clinic_inventory(args.init_clinic)
        print(
            f"Initialized clinic inventory for {result['clinic_id']} "
            f"with {result['created_count']} new rows."
        )
    else:
        run_full_migration()
