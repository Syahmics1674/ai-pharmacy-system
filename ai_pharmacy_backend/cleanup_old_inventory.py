from collections import Counter, defaultdict

from firebase_config import db
from validate_inventory_schema import validate_inventory, print_missing_fields


BATCH_SIZE = 400


def is_legacy_inventory(data):
    return not data.get("medicine_id") or not data.get("last_updated")


def scan_legacy_inventory():
    legacy_docs = []
    clinic_counts = Counter()

    for doc in db.collection("inventory").stream():
        data = doc.to_dict()
        if not is_legacy_inventory(data):
            continue

        clinic_id = data.get("clinic_id", "UNKNOWN_CLINIC")
        legacy_docs.append(
            {
                "document_id": doc.id,
                "clinic_id": clinic_id,
                "item_name": data.get("item_name"),
                "reference": doc.reference,
            }
        )
        clinic_counts[clinic_id] += 1

    return legacy_docs, clinic_counts


def print_scan_summary(legacy_docs, clinic_counts):
    print(f"Found {len(legacy_docs)} legacy inventory documents")

    if not legacy_docs:
        return

    sample_ids = [doc["document_id"] for doc in legacy_docs[:10]]
    print("Sample document IDs:")
    for document_id in sample_ids:
        print(f"- {document_id}")

    print("Clinic distribution:")
    for clinic_id in sorted(clinic_counts):
        print(f"{clinic_id} -> {clinic_counts[clinic_id]}")


def delete_legacy_inventory(legacy_docs):
    total_docs = len(legacy_docs)
    deleted_count = 0
    failed_deletions = []
    batch = db.batch()
    batch_entries = []

    def commit_batch(entries, deleted_so_far):
        if not entries:
            return deleted_so_far

        local_batch = db.batch()
        for entry in entries:
            local_batch.delete(entry["reference"])

        try:
            local_batch.commit()
            deleted_so_far += len(entries)
            print(f"Deleted {deleted_so_far} / {total_docs}")
        except Exception as exc:  # noqa: BLE001
            print(
                f"Batch delete failed for {len(entries)} documents. "
                "Retrying one by one..."
            )
            for entry in entries:
                try:
                    entry["reference"].delete()
                    deleted_so_far += 1
                    if deleted_so_far % 50 == 0 or deleted_so_far == total_docs:
                        print(f"Deleted {deleted_so_far} / {total_docs}")
                except Exception as item_exc:  # noqa: BLE001
                    failed_deletions.append(
                        {
                            "document_id": entry["document_id"],
                            "clinic_id": entry["clinic_id"],
                            "error": str(item_exc),
                            "batch_error": str(exc),
                        }
                    )

        return deleted_so_far

    for entry in legacy_docs:
        batch.delete(entry["reference"])
        batch_entries.append(entry)

        if len(batch_entries) >= BATCH_SIZE:
            deleted_count = commit_batch(batch_entries, deleted_count)
            batch = db.batch()
            batch_entries = []

    deleted_count = commit_batch(batch_entries, deleted_count)
    return deleted_count, failed_deletions


def post_cleanup_validation():
    print("\nRunning post-cleanup validation...")
    inventory_missing_fields, unresolved_inventory = validate_inventory()
    print_missing_fields("inventory", inventory_missing_fields)

    remaining_legacy = []
    clinic_normalized_counts = defaultdict(int)

    for doc in db.collection("inventory").stream():
        data = doc.to_dict()
        clinic_id = data.get("clinic_id", "UNKNOWN_CLINIC")

        if is_legacy_inventory(data):
            remaining_legacy.append(
                {
                    "document_id": doc.id,
                    "clinic_id": clinic_id,
                    "item_name": data.get("item_name"),
                }
            )
        else:
            clinic_normalized_counts[clinic_id] += 1

    for clinic_id in sorted(clinic_normalized_counts):
        print(f"[OK] {clinic_id} -> {clinic_normalized_counts[clinic_id]} medicines")

    if remaining_legacy:
        print("[WARNING] Remaining legacy inventory documents detected:")
        for item in remaining_legacy[:20]:
            print(
                f"- clinic_id={item['clinic_id']} "
                f"document_id={item['document_id']} item_name={item['item_name']}"
            )
    else:
        print("[OK] All remaining inventory documents contain medicine_id and last_updated")

    if unresolved_inventory:
        print("[WARNING] Unresolved normalized inventory mappings remain:")
        for item in unresolved_inventory[:20]:
            print(
                f"- clinic_id={item['clinic_id']} "
                f"document_id={item['document_id']} item_name={item['item_name']}"
            )


def main():
    legacy_docs, clinic_counts = scan_legacy_inventory()
    print_scan_summary(legacy_docs, clinic_counts)

    if not legacy_docs:
        print("No legacy inventory documents found. Nothing to delete.")
        post_cleanup_validation()
        return

    confirmation = input("Type YES to continue: ").strip()

    if confirmation != "YES":
        print("Cleanup cancelled. No documents were deleted.")
        return

    deleted_count, failed_deletions = delete_legacy_inventory(legacy_docs)

    print("\nCleanup completed successfully")
    print(f"Deleted: {deleted_count} legacy inventory documents")

    if failed_deletions:
        print(f"Failed deletions: {len(failed_deletions)}")
        for item in failed_deletions[:20]:
            print(
                f"- clinic_id={item['clinic_id']} "
                f"document_id={item['document_id']} error={item['error']}"
            )

    post_cleanup_validation()


if __name__ == "__main__":
    main()
