from firebase_config import db

BATCH_SIZE = 400

DEMO_CLINICS = {"clinicA", "clinicB", "clinicC", "clinicD", "clinicE"}

COLLECTIONS = ["clinics", "inventory", "usage_logs", "orders", "stock_in_logs"]

DRY_RUN = False
CONFIRM_DELETE = True


def query_docs(collection_name, clinic_id):
    return list(
        db.collection(collection_name)
        .where("clinic_id", "==", clinic_id)
        .stream()
    )


def query_clinic_doc(clinic_id):
    doc = db.collection("clinics").document(clinic_id).get()
    return [doc] if doc.exists else []


def collect_all():
    summaries = []
    all_refs = []

    for collection in COLLECTIONS:
        for clinic_id in sorted(DEMO_CLINICS):
            if collection == "clinics":
                docs = query_clinic_doc(clinic_id)
            else:
                docs = query_docs(collection, clinic_id)

            if not docs:
                continue

            refs = [doc.reference for doc in docs]
            summaries.append({
                "collection": collection,
                "clinic_id": clinic_id,
                "count": len(refs),
            })
            all_refs.extend(refs)

    return summaries, all_refs


def delete_batch(refs):
    total = len(refs)
    deleted = 0
    batch = db.batch()
    batch_entries = []

    def commit():
        nonlocal deleted
        if not batch_entries:
            return
        batch.commit()
        deleted += len(batch_entries)
        batch_entries.clear()

    for ref in refs:
        batch.delete(ref)
        batch_entries.append(ref)
        if len(batch_entries) >= BATCH_SIZE:
            commit()

    commit()
    return deleted


def main():
    print("=" * 60)
    print("  DEMO CLINIC CLEANUP SCRIPT")
    print("=" * 60)
    print()
    print(f"  DRY_RUN = {DRY_RUN}")
    print(f"  Demo clinics: {', '.join(sorted(DEMO_CLINICS))}")
    print(f"  Collections: {', '.join(COLLECTIONS)}")
    print()

    summaries, all_refs = collect_all()

    if not summaries:
        print("  No documents found for demo clinics.")
        print()
        remaining_clinics = sum(1 for _ in db.collection("clinics").stream())
        remaining_inventory = sum(1 for _ in db.collection("inventory").stream())
        print(f"  Remaining clinics:   {remaining_clinics}")
        print(f"  Remaining inventory: {remaining_inventory}")
        print()
        print("=" * 60)
        return

    print("-" * 60)
    print("  SCAN SUMMARY")
    print("-" * 60)
    for s in summaries:
        print(f"  {s['collection']:15s} | clinic_id={s['clinic_id']:7s} | "
              f"{s['count']:>5} docs")
    print()
    total_found = sum(s["count"] for s in summaries)
    print(f"  Total documents found: {total_found}")
    print()

    should_delete = False

    if DRY_RUN:
        print("  DRY RUN — no documents deleted.")
        print()
        if CONFIRM_DELETE:
            answer = input("Type YES to continue with actual deletion: ").strip()
            if answer == "YES":
                should_delete = True
        else:
            print("  Set CONFIRM_DELETE = True and re-run to perform deletion.")
    else:
        answer = input("Type YES to continue with deletion: ").strip()
        if answer == "YES":
            should_delete = True
        else:
            print("Cleanup cancelled. No documents were deleted.")

    if should_delete:
        print()
        print("Deleting documents...")
        total_deleted = delete_batch(all_refs)
        print()
        print("-" * 60)
        print("  CLEANUP COMPLETE")
        print("-" * 60)
        for s in summaries:
            print(f"  {s['collection']:15s} | clinic_id={s['clinic_id']:7s} | "
                  f"{s['count']:>5} docs")
        print()
        print(f"  Total documents deleted: {total_deleted}")
    else:
        print("No documents were deleted.")

    print()
    remaining_clinics = sum(1 for _ in db.collection("clinics").stream())
    remaining_inventory = sum(1 for _ in db.collection("inventory").stream())
    print(f"  Remaining clinics:   {remaining_clinics}")
    print(f"  Remaining inventory: {remaining_inventory}")
    print()
    print("=" * 60)


if __name__ == "__main__":
    main()
